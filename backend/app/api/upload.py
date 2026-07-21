from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from pathlib import Path
import uuid

from app.database.db import get_db
from app.database.models import Document
from app.services.ingestion import IngestionPipeline
from app.config import UPLOAD_DIR, ALLOWED_EXTENSIONS, MAX_FILE_SIZE_MB

router = APIRouter(prefix="/api/documents", tags=["documents"])
pipeline = IngestionPipeline()

@router.post("/upload")
async def upload_document(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    category: str = Form("uncategorized"),
    equipment_tag: str = Form(None),
    db: Session = Depends(get_db),
):
    ext = Path(file.filename).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Unsupported file type: {ext}")

    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE_MB * 1024 * 1024:
        raise HTTPException(400, f"File exceeds {MAX_FILE_SIZE_MB}MB limit")

    safe_name = f"{uuid.uuid4().hex}{ext}"
    filepath = UPLOAD_DIR / safe_name
    with open(filepath, "wb") as f:
        f.write(contents)

    document = Document(
        filename=safe_name,
        original_name=file.filename,
        file_type=ext.replace(".", ""),
        category=category,
        equipment_tag=equipment_tag,
        status="processing",
    )
    db.add(document)
    db.commit()
    db.refresh(document)

    background_tasks.add_task(
    pipeline.process,
    document.id,
    filepath,
    )

    return {"id": document.id, "filename": document.original_name, "status": "processing"}

@router.get("/")
def list_documents(db: Session = Depends(get_db)):
    docs = db.query(Document).order_by(Document.upload_date.desc()).all()
    return [
        {
            "id": d.id, "name": d.original_name, "category": d.category,
            "equipment_tag": d.equipment_tag, "status": d.status,
            "chunks": d.chunk_count, "uploaded": d.upload_date.isoformat(),
        }
        for d in docs
    ]

@router.delete("/{document_id}")
def delete_document(document_id: int, db: Session = Depends(get_db)):
    doc = db.query(Document).filter(Document.id == document_id).first()
    if not doc:
        raise HTTPException(404, "Document not found")
    pipeline.store.delete_document(document_id)
    db.delete(doc)
    db.commit()
    return {"status": "deleted"}
