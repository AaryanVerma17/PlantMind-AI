from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from app.database.db import get_db
from app.services.report_generator import ReportGenerator, REPORTS_DIR

router = APIRouter(prefix="/api/reports", tags=["reports"])
generator = ReportGenerator()

class ReportRequest(BaseModel):
    report_type: str
    equipment_tag: Optional[str] = None
    incident_description: Optional[str] = None
    export_format: str = "pdf"

@router.post("/generate")
def generate_report(req: ReportRequest, db: Session = Depends(get_db)):
    try:
        report = generator.generate(
            db, req.report_type,
            equipment_tag=req.equipment_tag,
            incident_description=req.incident_description,
        )
    except ValueError as e:
        raise HTTPException(400, str(e))

    if req.export_format == "pdf":
        filepath = generator.export_pdf(report)
    elif req.export_format == "docx":
        filepath = generator.export_docx(report)
    else:
        raise HTTPException(400, "export_format must be 'pdf' or 'docx'")

    return {
        "title": report["title"],
        "report_type": report["report_type"],
        "download_url": f"/api/reports/download/{filepath.name}",
    }

@router.get("/download/{filename}")
def download_report(filename: str):
    filepath = REPORTS_DIR / filename
    if not filepath.exists():
        raise HTTPException(404, "Report not found")
    return FileResponse(filepath, filename=filename)
