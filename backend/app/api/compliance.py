from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database.db import get_db
from app.database.models import MaintenanceRecord
from app.services.compliance import ComplianceEngine

router = APIRouter(prefix="/api/compliance", tags=["compliance"])
engine = ComplianceEngine()

@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db)):
    return engine.dashboard_summary(db)

@router.get("/equipment/{equipment_tag}")
def equipment_compliance(equipment_tag: str, equipment_category: str = None, db: Session = Depends(get_db)):
    # If no category provided, try to infer from equipment tag naming convention
    resolved_category = equipment_category
    if not resolved_category:
        record = db.query(MaintenanceRecord.equipment_tag).filter(
            MaintenanceRecord.equipment_tag == equipment_tag
        ).first()
        if record:
            resolved_category = engine._infer_category(equipment_tag)
        else:
            resolved_category = "Pump"  # Fallback default
    return engine.evaluate(db, equipment_tag, resolved_category)
