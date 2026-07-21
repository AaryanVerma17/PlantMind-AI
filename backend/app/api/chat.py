from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
import json

from app.database.db import get_db
from app.database.models import QueryLog
from app.services.rag import RAGEngine

router = APIRouter(prefix="/api/chat", tags=["chat"])


def get_rag():
    """Create a fresh RAGEngine on each request so recently uploaded
    documents (vectors persisted to disk) are picked up."""
    return RAGEngine()


class QueryRequest(BaseModel):
    question: str
    top_k: int = 5


@router.post("/query")
def query(req: QueryRequest, db: Session = Depends(get_db)):
    rag = get_rag()
    result = rag.query(req.question, top_k=req.top_k)

    log = QueryLog(
        question=req.question,
        answer=result["answer"],
        confidence=result["confidence"],
        sources=json.dumps(result["sources"]),
    )
    db.add(log)
    db.commit()

    return result
