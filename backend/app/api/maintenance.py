from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.database.db import get_db
from app.services.maintenance import MaintenanceIntelligence
from app.services.root_cause import RootCauseAnalyzer

router = APIRouter(prefix="/api/maintenance", tags=["maintenance"])
maintenance = MaintenanceIntelligence()
rca = RootCauseAnalyzer()

@router.get("/health-overview")
def health_overview(db: Session = Depends(get_db)):
    return maintenance.equipment_health_overview(db)

@router.get("/predictive-alerts")
def predictive_alerts(lookahead_days: int = 30, db: Session = Depends(get_db)):
    return maintenance.predictive_alerts(db, lookahead_days)

@router.get("/failure-trends")
def failure_trends(equipment_tag: str = None, db: Session = Depends(get_db)):
    return maintenance.failure_trends(db, equipment_tag)

class RCARequest(BaseModel):
    incident_description: str

@router.post("/root-cause-analysis")
def root_cause_analysis(req: RCARequest):
    return rca.analyze(req.incident_description)
