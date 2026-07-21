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
