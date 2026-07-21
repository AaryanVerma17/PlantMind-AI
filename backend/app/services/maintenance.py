from google import genai
from sqlalchemy.orm import Session
from sqlalchemy import func, Integer as SAInteger
from datetime import datetime
import json

from app.config import GEMINI_API_KEY, LLM_MODEL
from app.database.models import MaintenanceRecord, Chunk

client = genai.Client(api_key=GEMINI_API_KEY)

EXTRACTION_PROMPT = """You extract structured maintenance events from industrial text.
From the given text, extract any maintenance/inspection/breakdown events mentioned.
Return STRICT JSON: {"events": [{"equipment_tag": str, "event_type": "scheduled"|"breakdown"|"inspection",
"description": str, "failure_cause": str or null, "event_date": "YYYY-MM-DD" or null, "downtime_hours": float}]}
If no equipment tag is explicit, infer a short label from context (e.g. "Pump P-102"). If no events found, return {"events": []}.
Do not fabricate dates you cannot find in the text - use null.
"""


def _extract_json_from_response(text: str) -> dict:
    """Extract JSON from Gemini response, stripping markdown code fences if present."""
    if not text:
        return {"events": []}
    cleaned = text.strip()
    if cleaned.startswith("```"):
        # Remove opening fence (```json or ```)
        cleaned = cleaned.split("\n", 1)[-1] if "\n" in cleaned else cleaned
        # Remove closing fence
        if "```" in cleaned:
            cleaned = cleaned.rsplit("```", 1)[0]
    cleaned = cleaned.strip()
    return json.loads(cleaned)


class MaintenanceIntelligence:
    def extract_from_document(self, db: Session, document_id: int):
        chunks = db.query(Chunk).filter(Chunk.document_id == document_id).all()
        extracted_count = 0

        for chunk in chunks:
            try:
                prompt = f"{EXTRACTION_PROMPT}\n\nText:\n{chunk.text}"
                response = client.models.generate_content(
                    model=LLM_MODEL,
                    contents=prompt,
                )
                text = response.text if hasattr(response, "text") and response.text else ""
                parsed = _extract_json_from_response(text)
                for event in parsed.get("events", []):
                    if not event.get("equipment_tag"):
                        continue
                    event_date = None
                    if event.get("event_date"):
                        try:
                            event_date = datetime.strptime(event["event_date"], "%Y-%m-%d")
                        except ValueError:
                            event_date = None

                    record = MaintenanceRecord(
                        equipment_tag=event["equipment_tag"],
                        document_id=document_id,
                        event_type=event.get("event_type", "scheduled"),
                        description=event.get("description", ""),
                        failure_cause=event.get("failure_cause"),
                        event_date=event_date or datetime.utcnow(),
                        downtime_hours=event.get("downtime_hours") or 0.0,
                    )
                    db.add(record)
                    extracted_count += 1
            except Exception as e:
                print(f"Maintenance extraction failed for chunk {chunk.id}: {e}")
                continue

        db.commit()
        return extracted_count

    def equipment_health_overview(self, db: Session):
        rows = (
            db.query(
                MaintenanceRecord.equipment_tag,
                func.count(MaintenanceRecord.id).label("total_events"),
                func.sum(
                    func.cast(MaintenanceRecord.event_type == "breakdown", SAInteger)
                ).label("breakdowns"),
                func.sum(MaintenanceRecord.downtime_hours).label("total_downtime"),
            )
            .group_by(MaintenanceRecord.equipment_tag)
            .all()
        )

        overview = []
        for tag, total, breakdowns, downtime in rows:
            breakdowns = breakdowns or 0
            risk = self._risk_level(total, breakdowns)
            overview.append({
                "equipment_tag": tag,
                "total_events": total,
                "breakdowns": breakdowns,
                "total_downtime_hours": round(downtime or 0.0, 1),
                "risk_level": risk,
            })
        return sorted(overview, key=lambda x: x["breakdowns"], reverse=True)

    def _risk_level(self, total_events: int, breakdowns: int) -> str:
        if total_events == 0:
            return "unknown"
        ratio = breakdowns / total_events
        if ratio >= 0.5:
            return "high"
        elif ratio >= 0.2:
            return "medium"
        return "low"

    def predictive_alerts(self, db: Session, lookahead_days: int = 30):
        tags = db.query(MaintenanceRecord.equipment_tag).distinct().all()
        alerts = []

        for (tag,) in tags:
            breakdowns = (
                db.query(MaintenanceRecord)
                .filter(MaintenanceRecord.equipment_tag == tag, MaintenanceRecord.event_type == "breakdown")
                .order_by(MaintenanceRecord.event_date)
                .all()
            )
            if len(breakdowns) < 2:
                continue

            intervals = [
                (breakdowns[i + 1].event_date - breakdowns[i].event_date).days
                for i in range(len(breakdowns) - 1)
            ]
            avg_interval = sum(intervals) / len(intervals)
            last_breakdown = breakdowns[-1].event_date
            days_since = (datetime.utcnow() - last_breakdown).days
            days_until_due = round(avg_interval - days_since, 1)

            if days_until_due <= lookahead_days:
                alerts.append({
                    "equipment_tag": tag,
                    "avg_failure_interval_days": round(avg_interval, 1),
                    "days_since_last_failure": days_since,
                    "predicted_days_until_next_failure": days_until_due,
                    "urgency": "overdue" if days_until_due < 0 else "upcoming",
                })

        return sorted(alerts, key=lambda x: x["predicted_days_until_next_failure"])

    def failure_trends(self, db: Session, equipment_tag: str = None):
        query = db.query(MaintenanceRecord).filter(MaintenanceRecord.event_type == "breakdown")
        if equipment_tag:
            query = query.filter(MaintenanceRecord.equipment_tag == equipment_tag)

        records = query.all()
        cause_counts = {}
        for r in records:
            cause = r.failure_cause or "unspecified"
            cause_counts[cause] = cause_counts.get(cause, 0) + 1

        return sorted(
            [{"cause": k, "count": v} for k, v in cause_counts.items()],
            key=lambda x: x["count"], reverse=True
        )
