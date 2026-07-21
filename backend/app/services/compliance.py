from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.database.models import ComplianceRule, ComplianceStatus, MaintenanceRecord

class ComplianceEngine:
    def evaluate(self, db: Session, equipment_tag: str, equipment_category: str):
        rules = db.query(ComplianceRule).filter(
            ComplianceRule.equipment_category == equipment_category
        ).all()

        results = []
        for rule in rules:
            status_row = (
                db.query(ComplianceStatus)
                .filter(ComplianceStatus.rule_id == rule.id, ComplianceStatus.equipment_tag == equipment_tag)
                .first()
            )

            if not status_row:
                results.append({
                    "requirement": rule.requirement,
                    "status": "missing",
                    "mandatory": rule.mandatory,
                    "notes": "No record found for this requirement.",
                })
                continue

            current_status = status_row.status
            if rule.frequency_days and status_row.last_verified_date:
                expiry = status_row.last_verified_date + timedelta(days=rule.frequency_days)
                if datetime.utcnow() > expiry:
                    current_status = "expired"

            results.append({
                "requirement": rule.requirement,
                "status": current_status,
                "mandatory": rule.mandatory,
                "last_verified": status_row.last_verified_date.isoformat() if status_row.last_verified_date else None,
                "notes": status_row.notes,
            })

        return {
            "equipment_tag": equipment_tag,
            "equipment_category": equipment_category,
            "total_requirements": len(rules),
            "gaps": [r for r in results if r["status"] in ("missing", "expired")],
            "all_requirements": results,
        }

    def dashboard_summary(self, db: Session):
        all_status = db.query(ComplianceStatus).all()
        total = len(all_status)
        if total == 0:
            return {"total": 0, "met": 0, "missing": 0, "expired": 0, "compliance_rate": 0.0}

        met = sum(1 for s in all_status if s.status == "met")
        missing = sum(1 for s in all_status if s.status == "missing")
        expired = sum(1 for s in all_status if s.status == "expired")

        return {
            "total": total,
            "met": met,
            "missing": missing,
            "expired": expired,
            "compliance_rate": round(met / total * 100, 1),
        }

    def auto_populate_from_maintenance(self, db: Session, equipment_tag: str = None):
        """
        Auto-generate ComplianceStatus records from MaintenanceRecord data.
        For each equipment tag that has maintenance records, create compliance status
        entries if they don't already exist.
        """
        query = db.query(
            MaintenanceRecord.equipment_tag,
            MaintenanceRecord.event_type,
            func.count(MaintenanceRecord.id).label("event_count"),
            func.max(MaintenanceRecord.event_date).label("last_event_date"),
        ).group_by(
            MaintenanceRecord.equipment_tag,
            MaintenanceRecord.event_type,
        )

        if equipment_tag:
            query = query.filter(MaintenanceRecord.equipment_tag == equipment_tag)

        records = query.all()
        created_count = 0

        # Mapping from equipment tag to its approximate category based on context
        tag_category_cache = {}

        for tag, event_type, event_count, last_event_date in records:
            # Try to infer equipment category from the tag prefix/naming convention
            category = self._infer_category(tag)
            tag_category_cache[tag] = category

            # Find matching compliance rules for this category
            rules = db.query(ComplianceRule).filter(
                ComplianceRule.equipment_category == category
            ).all()

            for rule in rules:
                existing = db.query(ComplianceStatus).filter(
                    ComplianceStatus.rule_id == rule.id,
                    ComplianceStatus.equipment_tag == tag,
                ).first()

                if not existing:
                    # Create a new compliance status entry
                    status = "met" if event_count > 0 else "missing"
                    notes = f"Auto-populated from maintenance records ({event_count} {event_type} events)"
                    db.add(ComplianceStatus(
                        rule_id=rule.id,
                        equipment_tag=tag,
                        status=status,
                        last_verified_date=last_event_date or datetime.utcnow(),
                        notes=notes,
                    ))
                    created_count += 1

        if created_count > 0:
            db.commit()

        return created_count

    def _infer_category(self, equipment_tag: str) -> str:
        """Infer equipment category from tag naming convention."""
        tag_upper = equipment_tag.upper()
        # Check more specific patterns first
        if any(p in tag_upper for p in ["PRV", "VESSEL", "VSL"]):
            return "Pressure Vessel"
        elif any(p in tag_upper for p in ["TANK", "STORAGE"]):
            return "Storage Tank"
        elif any(p in tag_upper for p in ["BOIL", "B-"]) and "BOILER" not in tag_upper:
            return "Boiler"
        elif tag_upper == "BOILER" or "BOILER" in tag_upper:
            return "Boiler"
        elif any(p in tag_upper for p in ["PUMP", "P-"]):
            return "Pump"
        elif any(p in tag_upper for p in ["COMP", "C-"]):
            return "Compressor"
        elif any(p in tag_upper for p in ["PANEL", "ELEC", "SWITCH"]):
            return "Electrical Panel"
        # Default fallback
        return "Pump"

