"""
Seeds baseline compliance rules for demo/first-run purposes.
Run with: python -m app.seed
"""
from datetime import datetime, timedelta
from app.database.db import SessionLocal, init_db
from app.database.models import ComplianceRule, ComplianceStatus

RULES = [
    ("Pressure Vessel", "Annual pressure test certificate", 365, "yes"),
    ("Pressure Vessel", "Safety valve calibration record", 180, "yes"),
    ("Boiler", "Boiler inspection certificate (IBR)", 365, "yes"),
    ("Boiler", "Water quality test log", 30, "yes"),
    ("Pump", "Vibration analysis report", 90, "no"),
    ("Pump", "Lubrication schedule compliance", 30, "yes"),
    ("Compressor", "Oil analysis report", 90, "yes"),
    ("Compressor", "Vibration monitoring log", 90, "no"),
    ("Electrical Panel", "Thermography inspection report", 180, "yes"),
    ("Electrical Panel", "Earthing resistance test", 365, "yes"),
    ("Storage Tank", "Tank integrity inspection", 365, "yes"),
    ("Storage Tank", "Fire safety NOC", 365, "yes"),
]

DEMO_STATUSES = [
    ("P-102", "Vibration analysis report", "met", 20),
    ("P-102", "Lubrication schedule compliance", "met", 10),
    ("B-3", "Boiler inspection certificate (IBR)", "expired", 400),
    ("B-3", "Water quality test log", "met", 5),
    ("C-204", "Oil analysis report", "missing", None),
]

def seed():
    init_db()
    db = SessionLocal()
    try:
        if db.query(ComplianceRule).count() > 0:
            print("Compliance rules already seeded, skipping.")
        else:
            rule_lookup = {}
            for category, requirement, freq, mandatory in RULES:
                rule = ComplianceRule(
                    equipment_category=category, requirement=requirement,
                    frequency_days=freq, mandatory=mandatory,
                )
                db.add(rule)
                db.flush()
                rule_lookup[requirement] = rule.id
            db.commit()
            print(f"Seeded {len(RULES)} compliance rules.")

            for tag, requirement_text, status, days_ago in DEMO_STATUSES:
                rule_id = rule_lookup.get(requirement_text)
                if not rule_id:
                    continue
                last_verified = (
                    datetime.utcnow() - timedelta(days=days_ago) if days_ago is not None else None
                )
                db.add(ComplianceStatus(
                    rule_id=rule_id, equipment_tag=tag, status=status,
                    last_verified_date=last_verified,
                    notes="Seeded demo record" if status != "missing" else "No record found yet",
                ))
            db.commit()
            print(f"Seeded {len(DEMO_STATUSES)} demo compliance statuses.")
    finally:
        db.close()

if __name__ == "__main__":
    seed()
