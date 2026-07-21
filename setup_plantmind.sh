#!/bin/bash
# PlantMind AI — full project scaffold
# Skips existing folders (mkdir -p is idempotent) and skips existing files.

set -e

ROOT="PlantMind-AI"
mkdir -p "$ROOT"
cd "$ROOT"

# ---------- helper ----------
write_file() {
  local path="$1"
  if [ -f "$path" ]; then
    echo "Skip (exists): $path"
    return
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  echo "Created: $path"
}

# ---------- folders ----------
mkdir -p frontend/public
mkdir -p frontend/src/assets
mkdir -p frontend/src/components
mkdir -p frontend/src/pages
mkdir -p frontend/src/services
mkdir -p backend/app/api
mkdir -p backend/app/services
mkdir -p backend/app/database
mkdir -p backend/app/utils
mkdir -p data/uploads
mkdir -p data/vectorstore
mkdir -p data/reports
mkdir -p docs

touch data/uploads/.gitkeep data/vectorstore/.gitkeep data/reports/.gitkeep

# ==================================================
# BACKEND
# ==================================================

write_file backend/app/config.py << 'EOF'
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR.parent / "data"
UPLOAD_DIR = DATA_DIR / "uploads"
VECTORSTORE_DIR = DATA_DIR / "vectorstore"
DB_PATH = DATA_DIR / "plantmind.db"

for d in (UPLOAD_DIR, VECTORSTORE_DIR):
    d.mkdir(parents=True, exist_ok=True)

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "all-MiniLM-L6-v2")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-4o-mini")

CHUNK_SIZE = 800
CHUNK_OVERLAP = 150
TOP_K = 5
MAX_FILE_SIZE_MB = 50
ALLOWED_EXTENSIONS = {".pdf", ".docx", ".txt", ".csv", ".xlsx", ".png", ".jpg", ".jpeg"}
EOF

write_file backend/app/database/db.py << 'EOF'
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from app.config import DB_PATH

DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{DB_PATH}")
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db():
    from app.database import models  # noqa
    Base.metadata.create_all(bind=engine)
EOF

write_file backend/app/database/models.py << 'EOF'
from sqlalchemy import Column, Integer, String, DateTime, Text, Float, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from .db import Base

class Document(Base):
    __tablename__ = "documents"
    id = Column(Integer, primary_key=True, index=True)
    filename = Column(String, nullable=False)
    original_name = Column(String, nullable=False)
    file_type = Column(String, nullable=False)
    category = Column(String, default="uncategorized")
    equipment_tag = Column(String, nullable=True, index=True)
    upload_date = Column(DateTime, default=datetime.utcnow)
    version = Column(Integer, default=1)
    status = Column(String, default="processing")
    page_count = Column(Integer, default=0)
    chunk_count = Column(Integer, default=0)
    chunks = relationship("Chunk", back_populates="document", cascade="all, delete-orphan")

class Chunk(Base):
    __tablename__ = "chunks"
    id = Column(Integer, primary_key=True, index=True)
    document_id = Column(Integer, ForeignKey("documents.id"))
    chunk_index = Column(Integer, nullable=False)
    text = Column(Text, nullable=False)
    vector_id = Column(Integer, nullable=False)
    page_number = Column(Integer, nullable=True)
    document = relationship("Document", back_populates="chunks")

class QueryLog(Base):
    __tablename__ = "query_logs"
    id = Column(Integer, primary_key=True, index=True)
    question = Column(Text, nullable=False)
    answer = Column(Text, nullable=False)
    confidence = Column(Float, default=0.0)
    sources = Column(Text)
    timestamp = Column(DateTime, default=datetime.utcnow)

class MaintenanceRecord(Base):
    __tablename__ = "maintenance_records"
    id = Column(Integer, primary_key=True, index=True)
    equipment_tag = Column(String, nullable=False, index=True)
    document_id = Column(Integer, ForeignKey("documents.id"), nullable=True)
    event_type = Column(String, nullable=False)
    description = Column(Text, nullable=False)
    failure_cause = Column(String, nullable=True)
    event_date = Column(DateTime, nullable=False)
    downtime_hours = Column(Float, default=0.0)

class ComplianceRule(Base):
    __tablename__ = "compliance_rules"
    id = Column(Integer, primary_key=True, index=True)
    equipment_category = Column(String, nullable=False)
    requirement = Column(String, nullable=False)
    frequency_days = Column(Integer, nullable=True)
    mandatory = Column(String, default="yes")

class ComplianceStatus(Base):
    __tablename__ = "compliance_status"
    id = Column(Integer, primary_key=True, index=True)
    rule_id = Column(Integer, ForeignKey("compliance_rules.id"))
    equipment_tag = Column(String, nullable=False, index=True)
    status = Column(String, default="unknown")
    last_verified_date = Column(DateTime, nullable=True)
    supporting_document_id = Column(Integer, ForeignKey("documents.id"), nullable=True)
    notes = Column(Text, nullable=True)
EOF

write_file backend/app/services/parser.py << 'EOF'
import fitz
import docx
import pandas as pd
import pytesseract
from PIL import Image
from pathlib import Path
from typing import List, Dict

class DocumentParser:
    def parse(self, filepath: Path) -> List[Dict]:
        ext = filepath.suffix.lower()
        if ext == ".pdf":
            return self._parse_pdf(filepath)
        elif ext == ".docx":
            return self._parse_docx(filepath)
        elif ext == ".txt":
            return self._parse_txt(filepath)
        elif ext == ".csv":
            return self._parse_csv(filepath)
        elif ext == ".xlsx":
            return self._parse_xlsx(filepath)
        elif ext in (".png", ".jpg", ".jpeg"):
            return self._parse_image(filepath)
        else:
            raise ValueError(f"Unsupported file type: {ext}")

    def _parse_pdf(self, filepath: Path) -> List[Dict]:
        pages = []
        doc = fitz.open(filepath)
        for i, page in enumerate(doc):
            text = page.get_text("text").strip()
            if len(text) < 20:
                pix = page.get_pixmap(dpi=200)
                img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
                text = pytesseract.image_to_string(img).strip()
            if text:
                pages.append({"page_number": i + 1, "text": text})
        doc.close()
        return pages

    def _parse_docx(self, filepath: Path) -> List[Dict]:
        d = docx.Document(filepath)
        full_text = []
        for para in d.paragraphs:
            if para.text.strip():
                full_text.append(para.text.strip())
        for table in d.tables:
            for row in table.rows:
                row_text = " | ".join(c.text.strip() for c in row.cells if c.text.strip())
                if row_text:
                    full_text.append(row_text)
        return [{"page_number": None, "text": "\n".join(full_text)}]

    def _parse_txt(self, filepath: Path) -> List[Dict]:
        text = filepath.read_text(encoding="utf-8", errors="ignore")
        return [{"page_number": None, "text": text}]

    def _parse_csv(self, filepath: Path) -> List[Dict]:
        df = pd.read_csv(filepath)
        return [{"page_number": None, "text": df.to_string(index=False)}]

    def _parse_xlsx(self, filepath: Path) -> List[Dict]:
        xls = pd.ExcelFile(filepath)
        chunks = []
        for sheet in xls.sheet_names:
            df = xls.parse(sheet)
            chunks.append({"page_number": None, "text": f"Sheet: {sheet}\n{df.to_string(index=False)}"})
        return chunks

    def _parse_image(self, filepath: Path) -> List[Dict]:
        text = pytesseract.image_to_string(Image.open(filepath)).strip()
        return [{"page_number": None, "text": text}]
EOF

write_file backend/app/services/embeddings.py << 'EOF'
from sentence_transformers import SentenceTransformer
from app.config import EMBEDDING_MODEL, CHUNK_SIZE, CHUNK_OVERLAP
from typing import List, Dict
import numpy as np

class EmbeddingService:
    def __init__(self):
        self.model = SentenceTransformer(EMBEDDING_MODEL)
        self.dimension = self.model.get_sentence_embedding_dimension()

    def chunk_text(self, pages: List[Dict]) -> List[Dict]:
        chunks = []
        for page in pages:
            text = page["text"]
            page_num = page.get("page_number")
            start = 0
            while start < len(text):
                end = start + CHUNK_SIZE
                chunk_text = text[start:end].strip()
                if chunk_text:
                    chunks.append({"text": chunk_text, "page_number": page_num})
                start += CHUNK_SIZE - CHUNK_OVERLAP
        return chunks

    def embed(self, texts: List[str]) -> np.ndarray:
        embeddings = self.model.encode(
            texts, convert_to_numpy=True, normalize_embeddings=True, show_progress_bar=False
        )
        return embeddings.astype("float32")
EOF

write_file backend/app/services/vectorstore.py << 'EOF'
import faiss
import numpy as np
import pickle
from app.config import VECTORSTORE_DIR

INDEX_PATH = VECTORSTORE_DIR / "index.faiss"
META_PATH = VECTORSTORE_DIR / "meta.pkl"

class VectorStore:
    def __init__(self, dimension: int):
        self.dimension = dimension
        self.metadata = {}
        if INDEX_PATH.exists() and META_PATH.exists():
            self.index = faiss.read_index(str(INDEX_PATH))
            with open(META_PATH, "rb") as f:
                self.metadata = pickle.load(f)
        else:
            self.index = faiss.IndexFlatIP(dimension)

    def add(self, vectors: np.ndarray, meta_entries: list) -> list:
        start_id = self.index.ntotal
        self.index.add(vectors)
        vector_ids = []
        for i, meta in enumerate(meta_entries):
            vid = start_id + i
            self.metadata[vid] = meta
            vector_ids.append(vid)
        self._persist()
        return vector_ids

    def search(self, query_vector: np.ndarray, k: int = 5):
        if self.index.ntotal == 0:
            return []
        scores, indices = self.index.search(query_vector.reshape(1, -1), min(k, self.index.ntotal))
        results = []
        for score, idx in zip(scores[0], indices[0]):
            if idx == -1:
                continue
            meta = self.metadata.get(int(idx), {})
            results.append({**meta, "score": float(score)})
        return results

    def delete_document(self, document_id: int):
        keep_ids = [vid for vid, m in self.metadata.items() if m.get("document_id") != document_id]
        if len(keep_ids) == self.index.ntotal:
            return
        new_index = faiss.IndexFlatIP(self.dimension)
        new_metadata = {}
        if keep_ids:
            vectors = np.vstack([self.index.reconstruct(vid) for vid in keep_ids])
            new_index.add(vectors)
            for new_id, old_id in enumerate(keep_ids):
                new_metadata[new_id] = self.metadata[old_id]
        self.index = new_index
        self.metadata = new_metadata
        self._persist()

    def _persist(self):
        faiss.write_index(self.index, str(INDEX_PATH))
        with open(META_PATH, "wb") as f:
            pickle.dump(self.metadata, f)
EOF

write_file backend/app/services/rag.py << 'EOF'
from openai import OpenAI
from app.config import OPENAI_API_KEY, LLM_MODEL, TOP_K
from app.services.embeddings import EmbeddingService
from app.services.vectorstore import VectorStore
import json

client = OpenAI(api_key=OPENAI_API_KEY)

SYSTEM_PROMPT = """You are PlantMind AI, an industrial engineering copilot.
Answer ONLY using the provided context chunks from plant documents.
Rules:
- If the answer isn't in the context, say so explicitly - never invent specs, procedures, or numbers.
- Always reference which source document(s) you used.
- Be precise and technical; this is used for real maintenance decisions.
- Return your response strictly as JSON with keys: "answer", "confidence" (0-1 float), "reasoning".
"""

class RAGEngine:
    def __init__(self):
        self.embedder = EmbeddingService()
        self.store = VectorStore(dimension=self.embedder.dimension)

    def query(self, question: str, top_k: int = TOP_K) -> dict:
        query_vec = self.embedder.embed([question])[0]
        retrieved = self.store.search(query_vec, k=top_k)

        if not retrieved:
            return {
                "answer": "No documents have been indexed yet, or nothing relevant was found.",
                "confidence": 0.0,
                "sources": [],
            }

        context_blocks = []
        for chunk in retrieved:
            tag = f"[Doc {chunk.get('document_id')} | chunk {chunk.get('chunk_id')}]"
            context_blocks.append(f"{tag}\n{chunk['text']}")
        context = "\n\n---\n\n".join(context_blocks)

        user_prompt = f"Context:\n{context}\n\nQuestion: {question}"

        response = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
        )

        parsed = json.loads(response.choices[0].message.content)
        avg_similarity = sum(c["score"] for c in retrieved) / len(retrieved)
        final_confidence = round((parsed.get("confidence", 0.5) + avg_similarity) / 2, 2)

        return {
            "answer": parsed.get("answer"),
            "reasoning": parsed.get("reasoning"),
            "confidence": final_confidence,
            "sources": [
                {
                    "document_id": c.get("document_id"),
                    "page_number": c.get("page_number"),
                    "excerpt": c["text"][:200],
                    "similarity": round(c["score"], 3),
                }
                for c in retrieved
            ],
        }
EOF

write_file backend/app/services/ingestion.py << 'EOF'
from pathlib import Path
from sqlalchemy.orm import Session
from app.database.models import Document, Chunk
from app.services.parser import DocumentParser
from app.services.embeddings import EmbeddingService
from app.services.vectorstore import VectorStore
from app.services.maintenance import MaintenanceIntelligence

class IngestionPipeline:
    def __init__(self):
        self.parser = DocumentParser()
        self.embedder = EmbeddingService()
        self.store = VectorStore(dimension=self.embedder.dimension)

    def process(self, db: Session, document: Document, filepath: Path):
        try:
            pages = self.parser.parse(filepath)
            document.page_count = len(pages)

            chunks = self.embedder.chunk_text(pages)
            if not chunks:
                document.status = "failed"
                db.commit()
                return

            texts = [c["text"] for c in chunks]
            vectors = self.embedder.embed(texts)

            chunk_rows = []
            for i, c in enumerate(chunks):
                row = Chunk(document_id=document.id, chunk_index=i, text=c["text"],
                             vector_id=-1, page_number=c.get("page_number"))
                db.add(row)
                chunk_rows.append(row)
            db.flush()

            meta_entries = [
                {"document_id": document.id, "chunk_id": row.id, "text": row.text,
                 "page_number": row.page_number}
                for row in chunk_rows
            ]
            vector_ids = self.store.add(vectors, meta_entries)

            for row, vid in zip(chunk_rows, vector_ids):
                row.vector_id = vid

            document.status = "ready"
            document.chunk_count = len(chunks)
            db.commit()

            MaintenanceIntelligence().extract_from_document(db, document.id)

        except Exception as e:
            document.status = "failed"
            db.commit()
            raise e
EOF

write_file backend/app/services/maintenance.py << 'EOF'
from openai import OpenAI
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime
import json

from app.config import OPENAI_API_KEY, LLM_MODEL
from app.database.models import MaintenanceRecord, Chunk

client = OpenAI(api_key=OPENAI_API_KEY)

EXTRACTION_PROMPT = """You extract structured maintenance events from industrial text.
From the given text, extract any maintenance/inspection/breakdown events mentioned.
Return STRICT JSON: {"events": [{"equipment_tag": str, "event_type": "scheduled"|"breakdown"|"inspection",
"description": str, "failure_cause": str or null, "event_date": "YYYY-MM-DD" or null, "downtime_hours": float}]}
If no equipment tag is explicit, infer a short label from context (e.g. "Pump P-102"). If no events found, return {"events": []}.
Do not fabricate dates you cannot find in the text - use null.
"""

class MaintenanceIntelligence:
    def extract_from_document(self, db: Session, document_id: int):
        chunks = db.query(Chunk).filter(Chunk.document_id == document_id).all()
        extracted_count = 0

        for chunk in chunks:
            try:
                response = client.chat.completions.create(
                    model=LLM_MODEL,
                    messages=[
                        {"role": "system", "content": EXTRACTION_PROMPT},
                        {"role": "user", "content": chunk.text},
                    ],
                    response_format={"type": "json_object"},
                    temperature=0.0,
                )
                parsed = json.loads(response.choices[0].message.content)
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
            except Exception:
                continue

        db.commit()
        return extracted_count

    def equipment_health_overview(self, db: Session):
        rows = (
            db.query(
                MaintenanceRecord.equipment_tag,
                func.count(MaintenanceRecord.id).label("total_events"),
                func.sum(
                    func.cast(MaintenanceRecord.event_type == "breakdown", type_=__import__("sqlalchemy").Integer)
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
EOF

write_file backend/app/services/root_cause.py << 'EOF'
from openai import OpenAI
import json

from app.config import OPENAI_API_KEY, LLM_MODEL
from app.services.rag import RAGEngine

client = OpenAI(api_key=OPENAI_API_KEY)

RCA_PROMPT = """You are an industrial root-cause-analysis expert.
Given an incident description and related historical context from plant records,
identify the most likely root cause(s), cite similar past incidents if present in the context,
and recommend both corrective and preventive actions.

Return STRICT JSON:
{
  "likely_causes": [str, ...],
  "similar_past_incidents": [str, ...],
  "corrective_actions": [str, ...],
  "preventive_recommendations": [str, ...],
  "confidence": float
}
"""

class RootCauseAnalyzer:
    def __init__(self):
        self.rag = RAGEngine()

    def analyze(self, incident_description: str) -> dict:
        retrieval = self.rag.query(incident_description, top_k=6)
        context = "\n\n".join(s["excerpt"] for s in retrieval.get("sources", []))

        response = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": RCA_PROMPT},
                {"role": "user", "content": f"Incident: {incident_description}\n\nHistorical context:\n{context}"},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
        )
        result = json.loads(response.choices[0].message.content)
        result["sources"] = retrieval.get("sources", [])
        return result
EOF

write_file backend/app/services/compliance.py << 'EOF'
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from app.database.models import ComplianceRule, ComplianceStatus

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
EOF

write_file backend/app/services/report_generator.py << 'EOF'
from openai import OpenAI
from sqlalchemy.orm import Session
from datetime import datetime
import json

from app.config import OPENAI_API_KEY, LLM_MODEL, DATA_DIR
from app.services.maintenance import MaintenanceIntelligence
from app.services.compliance import ComplianceEngine
from app.services.rag import RAGEngine

client = OpenAI(api_key=OPENAI_API_KEY)

REPORTS_DIR = DATA_DIR / "reports"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

REPORT_PROMPTS = {
    "maintenance": """Write a formal Maintenance Report section-by-section using the provided data.
Include: Overview, Equipment Health Summary, Key Failures, Downtime Analysis, Recommendations.
Be specific with numbers from the data. Do not invent figures not present in the data.""",
    "incident": """Write a formal Incident Report based on the provided incident/RCA data.
Include: Incident Summary, Root Cause, Corrective Actions Taken, Preventive Recommendations, Sign-off section.""",
    "audit_summary": """Write a formal Audit Summary Report using the provided compliance data.
Include: Overview, Compliance Rate, Non-Conformances (missing/expired), Risk Assessment, Action Items.""",
    "equipment_summary": """Write a formal Equipment Summary Report for the specified equipment using the provided data.
Include: Equipment Overview, Maintenance History, Failure Trends, Current Compliance Status, Recommendations.""",
    "executive": """Write a concise Executive Report (1-2 pages) summarizing plant-wide status using the provided data.
Include: Executive Summary, Key Metrics, Top Risks, Compliance Snapshot, Strategic Recommendations.
Keep language high-level and suited for leadership, not floor engineers.""",
}

class ReportGenerator:
    def __init__(self):
        self.maintenance = MaintenanceIntelligence()
        self.compliance = ComplianceEngine()
        self.rag = RAGEngine()

    def _gather_data(self, db: Session, report_type: str, equipment_tag: str = None) -> dict:
        data = {}
        if report_type in ("maintenance", "executive", "equipment_summary"):
            data["health_overview"] = self.maintenance.equipment_health_overview(db)
            data["predictive_alerts"] = self.maintenance.predictive_alerts(db)
        if report_type in ("audit_summary", "executive", "equipment_summary"):
            data["compliance_summary"] = self.compliance.dashboard_summary(db)
        if report_type == "equipment_summary" and equipment_tag:
            data["failure_trends"] = self.maintenance.failure_trends(db, equipment_tag)
            data["equipment_health"] = [
                e for e in data["health_overview"] if e["equipment_tag"] == equipment_tag
            ]
        return data

    def generate(self, db: Session, report_type: str, equipment_tag: str = None,
                 incident_description: str = None) -> dict:
        if report_type not in REPORT_PROMPTS:
            raise ValueError(f"Unknown report type: {report_type}")

        if report_type == "incident":
            if not incident_description:
                raise ValueError("incident_description is required for incident reports")
            from app.services.root_cause import RootCauseAnalyzer
            rca_result = RootCauseAnalyzer().analyze(incident_description)
            data = {"incident_description": incident_description, "rca": rca_result}
        else:
            data = self._gather_data(db, report_type, equipment_tag)

        response = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": REPORT_PROMPTS[report_type] +
                 "\n\nReturn STRICT JSON: {\"title\": str, \"sections\": [{\"heading\": str, \"content\": str}]}"},
                {"role": "user", "content": f"Data:\n{json.dumps(data, default=str, indent=2)}"},
            ],
            response_format={"type": "json_object"},
            temperature=0.3,
        )

        report_content = json.loads(response.choices[0].message.content)
        report_content["report_type"] = report_type
        report_content["generated_at"] = datetime.utcnow().isoformat()
        return report_content

    def export_pdf(self, report: dict):
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
        from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
        from reportlab.lib.units import inch

        filename = f"{report['report_type']}_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}.pdf"
        filepath = REPORTS_DIR / filename

        doc = SimpleDocTemplate(str(filepath), pagesize=A4)
        styles = getSampleStyleSheet()
        title_style = ParagraphStyle("TitleStyle", parent=styles["Title"], spaceAfter=20)
        heading_style = ParagraphStyle("Heading", parent=styles["Heading2"], spaceBefore=14, spaceAfter=8)

        story = [Paragraph(report["title"], title_style),
                 Paragraph(f"Generated: {report['generated_at']}", styles["Normal"]),
                 Spacer(1, 0.2 * inch)]

        for section in report["sections"]:
            story.append(Paragraph(section["heading"], heading_style))
            for para in section["content"].split("\n"):
                if para.strip():
                    story.append(Paragraph(para.strip(), styles["Normal"]))
                    story.append(Spacer(1, 0.1 * inch))

        doc.build(story)
        return filepath

    def export_docx(self, report: dict):
        from docx import Document as DocxDocument
        from docx.shared import Pt

        filename = f"{report['report_type']}_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}.docx"
        filepath = REPORTS_DIR / filename

        doc = DocxDocument()
        doc.add_heading(report["title"], level=0)
        meta = doc.add_paragraph(f"Generated: {report['generated_at']}")
        meta.runs[0].italic = True

        for section in report["sections"]:
            doc.add_heading(section["heading"], level=1)
            for para in section["content"].split("\n"):
                if para.strip():
                    p = doc.add_paragraph(para.strip())
                    p.style.font.size = Pt(11)

        doc.save(filepath)
        return filepath
EOF

write_file backend/app/utils/helpers.py << 'EOF'
# Shared helper utilities for the backend (extend as needed).
def truncate(text: str, length: int = 200) -> str:
    return text if len(text) <= length else text[:length] + "..."
EOF

write_file backend/app/api/upload.py << 'EOF'
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

    background_tasks.add_task(pipeline.process, db, document, filepath)

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
EOF

write_file backend/app/api/chat.py << 'EOF'
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
import json

from app.database.db import get_db
from app.database.models import QueryLog
from app.services.rag import RAGEngine

router = APIRouter(prefix="/api/chat", tags=["chat"])
rag = RAGEngine()

class QueryRequest(BaseModel):
    question: str
    top_k: int = 5

@router.post("/query")
def query(req: QueryRequest, db: Session = Depends(get_db)):
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
EOF

write_file backend/app/api/maintenance.py << 'EOF'
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
EOF

write_file backend/app/api/compliance.py << 'EOF'
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database.db import get_db
from app.services.compliance import ComplianceEngine

router = APIRouter(prefix="/api/compliance", tags=["compliance"])
engine = ComplianceEngine()

@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db)):
    return engine.dashboard_summary(db)

@router.get("/equipment/{equipment_tag}")
def equipment_compliance(equipment_tag: str, equipment_category: str, db: Session = Depends(get_db)):
    return engine.evaluate(db, equipment_tag, equipment_category)
EOF

write_file backend/app/api/reports.py << 'EOF'
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
EOF

write_file backend/app/main.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database.db import init_db
from app.api import upload, chat, maintenance, compliance, reports

app = FastAPI(title="PlantMind AI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()

app.include_router(upload.router)
app.include_router(chat.router)
app.include_router(maintenance.router)
app.include_router(compliance.router)
app.include_router(reports.router)

@app.get("/")
def health():
    return {"status": "ok", "service": "PlantMind AI"}
EOF

write_file backend/app/seed.py << 'EOF'
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
EOF

write_file backend/requirements.txt << 'EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.35
pydantic==2.9.2
python-dotenv==1.0.1
openai==1.51.0
faiss-cpu==1.8.0
sentence-transformers==3.1.1
PyMuPDF==1.24.11
python-docx==1.1.2
pandas==2.2.3
openpyxl==3.1.5
pytesseract==0.3.13
Pillow==10.4.0
python-multipart==0.0.12
reportlab==4.2.5
psycopg2-binary==2.9.9
EOF

write_file backend/.env << 'EOF'
OPENAI_API_KEY=your_openai_api_key_here
EMBEDDING_MODEL=all-MiniLM-L6-v2
LLM_MODEL=gpt-4o-mini
DATABASE_URL=
EOF

# ==================================================
# FRONTEND
# ==================================================

write_file frontend/src/services/api.js << 'EOF'
import axios from "axios";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:8000";

const api = axios.create({
  baseURL: API_BASE,
  headers: { "Content-Type": "application/json" },
});

export const uploadDocument = (file, category, equipmentTag) => {
  const formData = new FormData();
  formData.append("file", file);
  formData.append("category", category || "uncategorized");
  if (equipmentTag) formData.append("equipment_tag", equipmentTag);
  return api.post("/api/documents/upload", formData, {
    headers: { "Content-Type": "multipart/form-data" },
  });
};
export const listDocuments = () => api.get("/api/documents/");
export const deleteDocument = (id) => api.delete(`/api/documents/${id}`);

export const askQuestion = (question, topK = 5) =>
  api.post("/api/chat/query", { question, top_k: topK });

export const getHealthOverview = () => api.get("/api/maintenance/health-overview");
export const getPredictiveAlerts = (lookaheadDays = 30) =>
  api.get(`/api/maintenance/predictive-alerts?lookahead_days=${lookaheadDays}`);
export const getFailureTrends = (equipmentTag) =>
  api.get("/api/maintenance/failure-trends", { params: { equipment_tag: equipmentTag } });
export const runRootCauseAnalysis = (incidentDescription) =>
  api.post("/api/maintenance/root-cause-analysis", { incident_description: incidentDescription });

export const getComplianceDashboard = () => api.get("/api/compliance/dashboard");
export const getEquipmentCompliance = (equipmentTag, equipmentCategory) =>
  api.get(`/api/compliance/equipment/${equipmentTag}`, { params: { equipment_category: equipmentCategory } });

export const generateReport = (payload) => api.post("/api/reports/generate", payload);

export default api;
EOF

write_file frontend/src/components/Sidebar.jsx << 'EOF'
import { NavLink } from "react-router-dom";
import {
  LayoutDashboard, MessageSquare, FileText, Wrench, ShieldCheck, FileBarChart2,
} from "lucide-react";

const navItems = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/chat", label: "AI Copilot", icon: MessageSquare },
  { to: "/documents", label: "Documents", icon: FileText },
  { to: "/maintenance", label: "Maintenance", icon: Wrench },
  { to: "/compliance", label: "Compliance", icon: ShieldCheck },
  { to: "/reports", label: "Reports", icon: FileBarChart2 },
];

export default function Sidebar() {
  return (
    <aside className="w-60 h-screen bg-slate-900 text-slate-200 flex flex-col fixed left-0 top-0">
      <div className="px-6 py-5 border-b border-slate-800">
        <h1 className="text-lg font-semibold tracking-tight text-white">PlantMind <span className="text-emerald-400">AI</span></h1>
        <p className="text-xs text-slate-500 mt-0.5">Industrial Knowledge Intelligence</p>
      </div>
      <nav className="flex-1 px-3 py-4 space-y-1">
        {navItems.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            end={to === "/"}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors ${
                isActive
                  ? "bg-emerald-500/10 text-emerald-400 font-medium"
                  : "text-slate-400 hover:bg-slate-800 hover:text-slate-200"
              }`
            }
          >
            <Icon size={18} />
            {label}
          </NavLink>
        ))}
      </nav>
      <div className="px-6 py-4 border-t border-slate-800 text-xs text-slate-500">
        v1.0.0 · ET GenAI Hackathon
      </div>
    </aside>
  );
}
EOF

write_file frontend/src/components/Navbar.jsx << 'EOF'
export default function Navbar({ title }) {
  return (
    <header className="h-16 border-b border-slate-200 bg-white flex items-center justify-between px-8 sticky top-0 z-10">
      <h2 className="text-xl font-semibold text-slate-800">{title}</h2>
      <div className="flex items-center gap-3">
        <span className="text-sm text-slate-500">Plant Engineer</span>
        <div className="w-9 h-9 rounded-full bg-emerald-500 text-white flex items-center justify-center text-sm font-medium">
          PE
        </div>
      </div>
    </header>
  );
}
EOF

write_file frontend/src/components/ChatBox.jsx << 'EOF'
import { useState, useRef, useEffect } from "react";
import { Send, FileText, Loader2 } from "lucide-react";
import { askQuestion } from "../services/api";

export default function ChatBox() {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSend = async () => {
    const question = input.trim();
    if (!question || loading) return;

    setMessages((prev) => [...prev, { role: "user", text: question }]);
    setInput("");
    setLoading(true);

    try {
      const { data } = await askQuestion(question);
      setMessages((prev) => [...prev, { role: "assistant", ...data }]);
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", answer: "Something went wrong reaching the AI engine. Please try again.", confidence: 0, sources: [] },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const confidenceColor = (score) => {
    if (score >= 0.75) return "text-emerald-600 bg-emerald-50";
    if (score >= 0.5) return "text-amber-600 bg-amber-50";
    return "text-red-600 bg-red-50";
  };

  return (
    <div className="flex flex-col h-[calc(100vh-4rem)]">
      <div className="flex-1 overflow-y-auto px-8 py-6 space-y-5">
        {messages.length === 0 && (
          <div className="text-center text-slate-400 mt-20">
            <p className="text-lg font-medium text-slate-500">Ask anything about your plant documents</p>
            <p className="text-sm mt-1">e.g. "How often should Pump P-102 be serviced?"</p>
          </div>
        )}

        {messages.map((msg, i) =>
          msg.role === "user" ? (
            <div key={i} className="flex justify-end">
              <div className="bg-emerald-600 text-white px-4 py-2.5 rounded-2xl rounded-br-sm max-w-xl text-sm">
                {msg.text}
              </div>
            </div>
          ) : (
            <div key={i} className="flex justify-start">
              <div className="bg-white border border-slate-200 rounded-2xl rounded-bl-sm max-w-2xl px-5 py-4 shadow-sm">
                <p className="text-slate-800 text-sm leading-relaxed whitespace-pre-wrap">{msg.answer}</p>

                {msg.confidence !== undefined && (
                  <span className={`inline-block mt-3 text-xs px-2 py-1 rounded-full font-medium ${confidenceColor(msg.confidence)}`}>
                    Confidence: {Math.round(msg.confidence * 100)}%
                  </span>
                )}

                {msg.sources?.length > 0 && (
                  <div className="mt-3 pt-3 border-t border-slate-100 space-y-2">
                    <p className="text-xs font-medium text-slate-500">Sources</p>
                    {msg.sources.map((s, j) => (
                      <div key={j} className="flex items-start gap-2 text-xs text-slate-500 bg-slate-50 rounded-lg px-3 py-2">
                        <FileText size={14} className="mt-0.5 shrink-0" />
                        <div>
                          <p className="text-slate-600">Doc #{s.document_id}{s.page_number ? `, page ${s.page_number}` : ""} · similarity {s.similarity}</p>
                          <p className="mt-0.5 italic text-slate-400">"{s.excerpt}..."</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )
        )}

        {loading && (
          <div className="flex items-center gap-2 text-slate-400 text-sm">
            <Loader2 size={16} className="animate-spin" /> PlantMind is thinking...
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <div className="border-t border-slate-200 bg-white px-8 py-4">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleSend()}
            placeholder="Ask about SOPs, equipment, maintenance history..."
            className="flex-1 border border-slate-300 rounded-xl px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500/40 focus:border-emerald-500"
          />
          <button
            onClick={handleSend}
            disabled={loading}
            className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-xl p-3 transition-colors"
          >
            <Send size={18} />
          </button>
        </div>
      </div>
    </div>
  );
}
EOF

write_file frontend/src/components/UploadCard.jsx << 'EOF'
import { useState, useRef } from "react";
import { UploadCloud, Loader2, CheckCircle2 } from "lucide-react";
import { uploadDocument } from "../services/api";

const CATEGORIES = ["SOP", "Manual", "Inspection Report", "Incident Report", "Audit", "Drawing", "Vendor Doc"];

export default function UploadCard({ onUploaded }) {
  const [dragActive, setDragActive] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [category, setCategory] = useState(CATEGORIES[0]);
  const [equipmentTag, setEquipmentTag] = useState("");
  const [success, setSuccess] = useState(false);
  const inputRef = useRef(null);

  const handleFile = async (file) => {
    if (!file) return;
    setUploading(true);
    setSuccess(false);
    try {
      await uploadDocument(file, category, equipmentTag);
      setSuccess(true);
      setEquipmentTag("");
      onUploaded?.();
    } catch (err) {
      alert(err.response?.data?.detail || "Upload failed.");
    } finally {
      setUploading(false);
      setTimeout(() => setSuccess(false), 2500);
    }
  };

  return (
    <div className="bg-white border border-slate-200 rounded-2xl p-6 shadow-sm">
      <h3 className="font-semibold text-slate-800 mb-4">Upload Document</h3>

      <div className="grid grid-cols-2 gap-3 mb-4">
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
        >
          {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <input
          value={equipmentTag}
          onChange={(e) => setEquipmentTag(e.target.value)}
          placeholder="Equipment tag (optional)"
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
        />
      </div>

      <div
        onDragOver={(e) => { e.preventDefault(); setDragActive(true); }}
        onDragLeave={() => setDragActive(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragActive(false);
          handleFile(e.dataTransfer.files[0]);
        }}
        onClick={() => inputRef.current?.click()}
        className={`border-2 border-dashed rounded-xl py-10 flex flex-col items-center justify-center cursor-pointer transition-colors ${
          dragActive ? "border-emerald-500 bg-emerald-50" : "border-slate-300 hover:border-slate-400"
        }`}
      >
        <input
          ref={inputRef}
          type="file"
          hidden
          accept=".pdf,.docx,.txt,.csv,.xlsx,.png,.jpg,.jpeg"
          onChange={(e) => handleFile(e.target.files[0])}
        />
        {uploading ? (
          <Loader2 className="animate-spin text-emerald-600" size={28} />
        ) : success ? (
          <CheckCircle2 className="text-emerald-600" size={28} />
        ) : (
          <UploadCloud className="text-slate-400" size={28} />
        )}
        <p className="text-sm text-slate-500 mt-3">
          {uploading ? "Processing..." : success ? "Uploaded successfully" : "Drag & drop or click to upload"}
        </p>
        <p className="text-xs text-slate-400 mt-1">PDF, DOCX, TXT, CSV, XLSX, PNG, JPG</p>
      </div>
    </div>
  );
}
EOF

write_file frontend/src/components/StatsCard.jsx << 'EOF'
export default function StatsCard({ label, value, icon: Icon, accent = "emerald", suffix = "" }) {
  const accents = {
    emerald: "bg-emerald-50 text-emerald-600",
    amber: "bg-amber-50 text-amber-600",
    red: "bg-red-50 text-red-600",
    slate: "bg-slate-100 text-slate-600",
  };

  return (
    <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm flex items-center justify-between">
      <div>
        <p className="text-xs text-slate-400 font-medium">{label}</p>
        <p className="text-2xl font-semibold text-slate-800 mt-1">
          {value}
          {suffix}
        </p>
      </div>
      <div className={`w-11 h-11 rounded-xl flex items-center justify-center ${accents[accent]}`}>
        <Icon size={20} />
      </div>
    </div>
  );
}
EOF

write_file frontend/src/pages/Chat.jsx << 'EOF'
import Navbar from "../components/Navbar";
import ChatBox from "../components/ChatBox";

export default function Chat() {
  return (
    <div>
      <Navbar title="AI Engineering Copilot" />
      <ChatBox />
    </div>
  );
}
EOF

write_file frontend/src/pages/Documents.jsx << 'EOF'
import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import UploadCard from "../components/UploadCard";
import { listDocuments, deleteDocument } from "../services/api";
import { Trash2, FileText, RefreshCw } from "lucide-react";

const statusStyles = {
  ready: "bg-emerald-50 text-emerald-700",
  processing: "bg-amber-50 text-amber-700",
  failed: "bg-red-50 text-red-700",
};

export default function Documents() {
  const [docs, setDocs] = useState([]);
  const [loading, setLoading] = useState(true);

  const fetchDocs = async () => {
    setLoading(true);
    try {
      const { data } = await listDocuments();
      setDocs(data);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDocs();
    const interval = setInterval(fetchDocs, 5000);
    return () => clearInterval(interval);
  }, []);

  const handleDelete = async (id) => {
    if (!confirm("Delete this document and its indexed chunks?")) return;
    await deleteDocument(id);
    fetchDocs();
  };

  return (
    <div>
      <Navbar title="Document Management" />
      <div className="p-8 grid grid-cols-3 gap-6">
        <div className="col-span-1">
          <UploadCard onUploaded={fetchDocs} />
        </div>

        <div className="col-span-2 bg-white border border-slate-200 rounded-2xl shadow-sm">
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100">
            <h3 className="font-semibold text-slate-800">All Documents ({docs.length})</h3>
            <button onClick={fetchDocs} className="text-slate-400 hover:text-slate-600">
              <RefreshCw size={16} className={loading ? "animate-spin" : ""} />
            </button>
          </div>

          <div className="divide-y divide-slate-100 max-h-[600px] overflow-y-auto">
            {docs.length === 0 && !loading && (
              <p className="text-sm text-slate-400 text-center py-10">No documents uploaded yet.</p>
            )}
            {docs.map((doc) => (
              <div key={doc.id} className="flex items-center justify-between px-6 py-3.5">
                <div className="flex items-center gap-3 min-w-0">
                  <FileText size={18} className="text-slate-400 shrink-0" />
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-slate-800 truncate">{doc.name}</p>
                    <p className="text-xs text-slate-400">
                      {doc.category} {doc.equipment_tag && `· ${doc.equipment_tag}`} · {doc.chunks} chunks
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  <span className={`text-xs px-2 py-1 rounded-full font-medium ${statusStyles[doc.status]}`}>
                    {doc.status}
                  </span>
                  <button onClick={() => handleDelete(doc.id)} className="text-slate-400 hover:text-red-500">
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
EOF

write_file frontend/src/pages/Dashboard.jsx << 'EOF'
import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import StatsCard from "../components/StatsCard";
import { listDocuments, getHealthOverview, getPredictiveAlerts, getComplianceDashboard } from "../services/api";
import { FileText, AlertTriangle, ShieldCheck, Activity } from "lucide-react";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";

export default function Dashboard() {
  const [docs, setDocs] = useState([]);
  const [health, setHealth] = useState([]);
  const [alerts, setAlerts] = useState([]);
  const [compliance, setCompliance] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const [d, h, a, c] = await Promise.all([
          listDocuments(),
          getHealthOverview(),
          getPredictiveAlerts(),
          getComplianceDashboard(),
        ]);
        setDocs(d.data);
        setHealth(h.data);
        setAlerts(a.data);
        setCompliance(c.data);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const readyDocs = docs.filter((d) => d.status === "ready").length;
  const highRiskEquipment = health.filter((h) => h.risk_level === "high").length;
  const chartData = health.slice(0, 8).map((h) => ({ name: h.equipment_tag, breakdowns: h.breakdowns, events: h.total_events }));

  return (
    <div>
      <Navbar title="Analytics Dashboard" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-4 gap-5">
          <StatsCard label="Documents Indexed" value={readyDocs} icon={FileText} accent="slate" />
          <StatsCard label="High-Risk Equipment" value={highRiskEquipment} icon={AlertTriangle} accent="red" />
          <StatsCard label="Predictive Alerts" value={alerts.length} icon={Activity} accent="amber" />
          <StatsCard
            label="Compliance Rate"
            value={compliance?.compliance_rate ?? 0}
            suffix="%"
            icon={ShieldCheck}
            accent="emerald"
          />
        </div>

        <div className="grid grid-cols-3 gap-6">
          <div className="col-span-2 bg-white border border-slate-200 rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-slate-800 mb-4">Equipment Breakdown Frequency</h3>
            {chartData.length === 0 ? (
              <p className="text-sm text-slate-400 py-10 text-center">No maintenance data yet. Upload maintenance logs to populate this chart.</p>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                  <XAxis dataKey="name" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="events" fill="#cbd5e1" name="Total Events" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="breakdowns" fill="#ef4444" name="Breakdowns" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>

          <div className="bg-white border border-slate-200 rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-slate-800 mb-4">Upcoming / Overdue Maintenance</h3>
            <div className="space-y-3 max-h-[280px] overflow-y-auto">
              {alerts.length === 0 && <p className="text-sm text-slate-400 text-center py-10">No predictive alerts.</p>}
              {alerts.map((a, i) => (
                <div key={i} className="flex items-center justify-between bg-slate-50 rounded-lg px-3 py-2.5">
                  <div>
                    <p className="text-sm font-medium text-slate-700">{a.equipment_tag}</p>
                    <p className="text-xs text-slate-400">Avg interval: {a.avg_failure_interval_days}d</p>
                  </div>
                  <span className={`text-xs px-2 py-1 rounded-full font-medium ${
                    a.urgency === "overdue" ? "bg-red-50 text-red-600" : "bg-amber-50 text-amber-600"
                  }`}>
                    {a.urgency === "overdue" ? "Overdue" : `${a.predicted_days_until_next_failure}d`}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
EOF

write_file frontend/src/pages/Maintenance.jsx << 'EOF'
import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import { getHealthOverview, getPredictiveAlerts, runRootCauseAnalysis } from "../services/api";
import { Loader2, Search } from "lucide-react";

const riskColors = {
  high: "bg-red-50 text-red-600",
  medium: "bg-amber-50 text-amber-600",
  low: "bg-emerald-50 text-emerald-600",
  unknown: "bg-slate-100 text-slate-500",
};

export default function Maintenance() {
  const [health, setHealth] = useState([]);
  const [alerts, setAlerts] = useState([]);
  const [incident, setIncident] = useState("");
  const [rcaResult, setRcaResult] = useState(null);
  const [analyzing, setAnalyzing] = useState(false);

  useEffect(() => {
    (async () => {
      const [h, a] = await Promise.all([getHealthOverview(), getPredictiveAlerts()]);
      setHealth(h.data);
      setAlerts(a.data);
    })();
  }, []);

  const handleAnalyze = async () => {
    if (!incident.trim()) return;
    setAnalyzing(true);
    setRcaResult(null);
    try {
      const { data } = await runRootCauseAnalysis(incident);
      setRcaResult(data);
    } catch {
      setRcaResult({ likely_causes: ["Analysis failed - please try again."], corrective_actions: [], preventive_recommendations: [], confidence: 0 });
    } finally {
      setAnalyzing(false);
    }
  };

  return (
    <div>
      <Navbar title="Maintenance Intelligence" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-2 gap-6">
          <div className="bg-white border border-slate-200 rounded-2xl shadow-sm">
            <div className="px-6 py-4 border-b border-slate-100">
              <h3 className="font-semibold text-slate-800">Equipment Health Overview</h3>
            </div>
            <div className="max-h-[380px] overflow-y-auto divide-y divide-slate-100">
              {health.length === 0 && <p className="text-sm text-slate-400 text-center py-10">No equipment data yet.</p>}
              {health.map((h, i) => (
                <div key={i} className="flex items-center justify-between px-6 py-3">
                  <div>
                    <p className="text-sm font-medium text-slate-700">{h.equipment_tag}</p>
                    <p className="text-xs text-slate-400">{h.total_events} events · {h.total_downtime_hours}h downtime</p>
                  </div>
                  <span className={`text-xs px-2.5 py-1 rounded-full font-medium capitalize ${riskColors[h.risk_level]}`}>
                    {h.risk_level}
                  </span>
                </div>
              ))}
            </div>
          </div>

          <div className="bg-white border border-slate-200 rounded-2xl shadow-sm">
            <div className="px-6 py-4 border-b border-slate-100">
              <h3 className="font-semibold text-slate-800">Predictive Maintenance Alerts</h3>
            </div>
            <div className="max-h-[380px] overflow-y-auto divide-y divide-slate-100">
              {alerts.length === 0 && <p className="text-sm text-slate-400 text-center py-10">No alerts. Need 2+ breakdown records per equipment tag.</p>}
              {alerts.map((a, i) => (
                <div key={i} className="px-6 py-3">
                  <div className="flex items-center justify-between">
                    <p className="text-sm font-medium text-slate-700">{a.equipment_tag}</p>
                    <span className={`text-xs px-2 py-1 rounded-full font-medium ${a.urgency === "overdue" ? "bg-red-50 text-red-600" : "bg-amber-50 text-amber-600"}`}>
                      {a.urgency}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400 mt-0.5">
                    Predicted in {a.predicted_days_until_next_failure}d · avg cycle {a.avg_failure_interval_days}d
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
          <h3 className="font-semibold text-slate-800 mb-1">Root Cause Analysis</h3>
          <p className="text-sm text-slate-400 mb-4">Describe an incident and get AI-driven cause analysis grounded in your plant records.</p>
          <div className="flex gap-3">
            <textarea
              value={incident}
              onChange={(e) => setIncident(e.target.value)}
              rows={2}
              placeholder="e.g. Compressor C-204 tripped on high vibration during startup at 03:15..."
              className="flex-1 border border-slate-300 rounded-lg px-4 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-emerald-500/40"
            />
            <button
              onClick={handleAnalyze}
              disabled={analyzing}
              className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-lg px-5 flex items-center gap-2 text-sm font-medium"
            >
              {analyzing ? <Loader2 size={16} className="animate-spin" /> : <Search size={16} />}
              Analyze
            </button>
          </div>

          {rcaResult && (
            <div className="grid grid-cols-3 gap-4 mt-6">
              <div>
                <p className="text-xs font-medium text-slate-500 mb-2">Likely Causes</p>
                <ul className="text-sm text-slate-700 space-y-1 list-disc list-inside">
                  {rcaResult.likely_causes?.map((c, i) => <li key={i}>{c}</li>)}
                </ul>
              </div>
              <div>
                <p className="text-xs font-medium text-slate-500 mb-2">Corrective Actions</p>
                <ul className="text-sm text-slate-700 space-y-1 list-disc list-inside">
                  {rcaResult.corrective_actions?.map((c, i) => <li key={i}>{c}</li>)}
                </ul>
              </div>
              <div>
                <p className="text-xs font-medium text-slate-500 mb-2">Preventive Recommendations</p>
                <ul className="text-sm text-slate-700 space-y-1 list-disc list-inside">
                  {rcaResult.preventive_recommendations?.map((c, i) => <li key={i}>{c}</li>)}
                </ul>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
EOF

write_file frontend/src/pages/Compliance.jsx << 'EOF'
import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import { getComplianceDashboard, getEquipmentCompliance } from "../services/api";
import { Search, CheckCircle2, XCircle, AlertCircle } from "lucide-react";

const statusIcon = {
  met: <CheckCircle2 size={16} className="text-emerald-500" />,
  missing: <XCircle size={16} className="text-red-500" />,
  expired: <AlertCircle size={16} className="text-amber-500" />,
};

export default function Compliance() {
  const [summary, setSummary] = useState(null);
  const [tag, setTag] = useState("");
  const [category, setCategory] = useState("");
  const [result, setResult] = useState(null);
  const [searching, setSearching] = useState(false);

  useEffect(() => {
    getComplianceDashboard().then((r) => setSummary(r.data));
  }, []);

  const handleSearch = async () => {
    if (!tag.trim() || !category.trim()) return;
    setSearching(true);
    try {
      const { data } = await getEquipmentCompliance(tag, category);
      setResult(data);
    } finally {
      setSearching(false);
    }
  };

  return (
    <div>
      <Navbar title="Compliance Intelligence" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-4 gap-5">
          {[
            { label: "Total Requirements", value: summary?.total ?? 0, color: "slate" },
            { label: "Met", value: summary?.met ?? 0, color: "emerald" },
            { label: "Missing", value: summary?.missing ?? 0, color: "red" },
            { label: "Expired", value: summary?.expired ?? 0, color: "amber" },
          ].map((s, i) => (
            <div key={i} className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm">
              <p className="text-xs text-slate-400 font-medium">{s.label}</p>
              <p className={`text-2xl font-semibold mt-1 text-${s.color}-600`}>{s.value}</p>
            </div>
          ))}
        </div>

        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
          <h3 className="font-semibold text-slate-800 mb-4">Check Equipment Compliance</h3>
          <div className="flex gap-3 mb-5">
            <input
              value={tag}
              onChange={(e) => setTag(e.target.value)}
              placeholder="Equipment tag, e.g. P-102"
              className="flex-1 border border-slate-300 rounded-lg px-4 py-2.5 text-sm"
            />
            <input
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              placeholder="Category, e.g. Pressure Vessel"
              className="flex-1 border border-slate-300 rounded-lg px-4 py-2.5 text-sm"
            />
            <button
              onClick={handleSearch}
              disabled={searching}
              className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-lg px-5 flex items-center gap-2 text-sm font-medium"
            >
              <Search size={16} /> Check
            </button>
          </div>

          {result && (
            <div>
              <p className="text-sm text-slate-500 mb-3">
                {result.equipment_tag} · {result.equipment_category} · {result.gaps.length} gap(s) found
              </p>
              <div className="divide-y divide-slate-100 border border-slate-100 rounded-xl">
                {result.all_requirements.map((r, i) => (
                  <div key={i} className="flex items-center justify-between px-4 py-3">
                    <div className="flex items-center gap-2">
                      {statusIcon[r.status] || statusIcon.missing}
                      <span className="text-sm text-slate-700">{r.requirement}</span>
                    </div>
                    <span className="text-xs text-slate-400 capitalize">{r.status}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
EOF

write_file frontend/src/pages/Reports.jsx << 'EOF'
import { useState } from "react";
import Navbar from "../components/Navbar";
import { generateReport } from "../services/api";
import { FileBarChart2, Loader2, Download } from "lucide-react";

const REPORT_TYPES = [
  { value: "maintenance", label: "Maintenance Report" },
  { value: "incident", label: "Incident Report" },
  { value: "audit_summary", label: "Audit Summary" },
  { value: "equipment_summary", label: "Equipment Summary" },
  { value: "executive", label: "Executive Report" },
];

export default function Reports() {
  const [reportType, setReportType] = useState("maintenance");
  const [equipmentTag, setEquipmentTag] = useState("");
  const [incidentDescription, setIncidentDescription] = useState("");
  const [format, setFormat] = useState("pdf");
  const [generating, setGenerating] = useState(false);
  const [result, setResult] = useState(null);

  const apiBase = import.meta.env.VITE_API_URL || "http://localhost:8000";

  const handleGenerate = async () => {
    setGenerating(true);
    setResult(null);
    try {
      const { data } = await generateReport({
        report_type: reportType,
        equipment_tag: reportType === "equipment_summary" ? equipmentTag : undefined,
        incident_description: reportType === "incident" ? incidentDescription : undefined,
        export_format: format,
      });
      setResult(data);
    } catch (err) {
      alert(err.response?.data?.detail || "Report generation failed.");
    } finally {
      setGenerating(false);
    }
  };

  return (
    <div>
      <Navbar title="AI Report Generator" />
      <div className="p-8 max-w-2xl">
        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
          <h3 className="font-semibold text-slate-800 mb-4">Generate Report</h3>

          <label className="text-xs font-medium text-slate-500">Report Type</label>
          <select
            value={reportType}
            onChange={(e) => setReportType(e.target.value)}
            className="w-full border border-slate-300 rounded-lg px-4 py-2.5 text-sm mt-1 mb-4"
          >
            {REPORT_TYPES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
          </select>

          {reportType === "equipment_summary" && (
            <>
              <label className="text-xs font-medium text-slate-500">Equipment Tag</label>
              <input
                value={equipmentTag}
                onChange={(e) => setEquipmentTag(e.target.value)}
                placeholder="e.g. P-102"
                className="w-full border border-slate-300 rounded-lg px-4 py-2.5 text-sm mt-1 mb-4"
              />
            </>
          )}

          {reportType === "incident" && (
            <>
              <label className="text-xs font-medium text-slate-500">Incident Description</label>
              <textarea
                value={incidentDescription}
                onChange={(e) => setIncidentDescription(e.target.value)}
                rows={3}
                placeholder="Describe what happened..."
                className="w-full border border-slate-300 rounded-lg px-4 py-2.5 text-sm mt-1 mb-4 resize-none"
              />
            </>
          )}

          <label className="text-xs font-medium text-slate-500">Export Format</label>
          <div className="flex gap-3 mt-1 mb-5">
            {["pdf", "docx"].map((f) => (
              <button
                key={f}
                onClick={() => setFormat(f)}
                className={`px-4 py-2 rounded-lg text-sm font-medium border ${
                  format === f ? "bg-emerald-600 text-white border-emerald-600" : "border-slate-300 text-slate-600"
                }`}
              >
                {f.toUpperCase()}
              </button>
            ))}
          </div>

          <button
            onClick={handleGenerate}
            disabled={generating}
            className="w-full bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-lg py-3 flex items-center justify-center gap-2 text-sm font-medium"
          >
            {generating ? <Loader2 size={16} className="animate-spin" /> : <FileBarChart2 size={16} />}
            Generate Report
          </button>

          {result && (
            
              href={`${apiBase}${result.download_url}`}
              target="_blank"
              rel="noreferrer"
              className="mt-4 flex items-center justify-between bg-emerald-50 text-emerald-700 rounded-lg px-4 py-3 text-sm font-medium"
            >
              {result.title}
              <Download size={16} />
            </a>
          )}
        </div>
      </div>
    </div>
  );
}
EOF

write_file frontend/src/App.jsx << 'EOF'
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Sidebar from "./components/Sidebar";
import Dashboard from "./pages/Dashboard";
import Chat from "./pages/Chat";
import Documents from "./pages/Documents";
import Maintenance from "./pages/Maintenance";
import Compliance from "./pages/Compliance";
import Reports from "./pages/Reports";

export default function App() {
  return (
    <BrowserRouter>
      <div className="flex bg-slate-50 min-h-screen">
        <Sidebar />
        <main className="ml-60 flex-1">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/chat" element={<Chat />} />
            <Route path="/documents" element={<Documents />} />
            <Route path="/maintenance" element={<Maintenance />} />
            <Route path="/compliance" element={<Compliance />} />
            <Route path="/reports" element={<Reports />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}
EOF

write_file frontend/src/main.jsx << 'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

write_file frontend/src/index.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  font-family: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 3px;
}
::-webkit-scrollbar-track {
  background: transparent;
}
EOF

write_file frontend/index.html << 'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>PlantMind AI</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

write_file frontend/tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,jsx}"],
  theme: {
    extend: {},
  },
  plugins: [],
};
EOF

write_file frontend/postcss.config.js << 'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF

write_file frontend/vite.config.js << 'EOF'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": {
        target: "http://localhost:8000",
        changeOrigin: true,
      },
    },
  },
});
EOF

write_file frontend/.env << 'EOF'
VITE_API_URL=http://localhost:8000
EOF

write_file frontend/package.json << 'EOF'
{
  "name": "plantmind-ai-frontend",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "axios": "^1.7.7",
    "lucide-react": "^0.383.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.26.2",
    "recharts": "^2.12.7"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.1",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.47",
    "tailwindcss": "^3.4.13",
    "vite": "^5.4.8"
  }
}
EOF

# ==================================================
# ROOT FILES
# ==================================================

write_file .gitignore << 'EOF'
# Python
venv/
__pycache__/
*.pyc
.env

# Node
node_modules/
dist/

# Data (regenerated at runtime)
data/uploads/*
data/vectorstore/*
data/reports/*
!data/uploads/.gitkeep
!data/vectorstore/.gitkeep
!data/reports/.gitkeep

# OS
.DS_Store
EOF

write_file README.md << 'EOF'
# PlantMind AI
### AI-Powered Industrial Knowledge Intelligence Platform
ET GenAI Hackathon 2.0

See setup instructions inside backend/ and frontend/ folders.
Run backend: uvicorn app.main:app --reload --port 8000
Run frontend: npm run dev
EOF

echo ""
echo "Done. Project scaffolded at ./$ROOT"
echo "Next steps:"
echo "  cd $ROOT/backend && python -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
echo "  cd $ROOT/frontend && npm install"