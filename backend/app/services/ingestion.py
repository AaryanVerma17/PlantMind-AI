from pathlib import Path
import time

from app.database.db import SessionLocal
from app.database.models import Document, Chunk
from app.services.parser import DocumentParser
from app.services.embeddings import EmbeddingService
from app.services.vectorstore import VectorStore
from app.services.maintenance import MaintenanceIntelligence
from app.services.compliance import ComplianceEngine


class IngestionPipeline:

    def __init__(self):
        self.parser = DocumentParser()
        self.embedder = EmbeddingService()
        # Auto-detect the actual embedding dimension from the API
        # so we never get dimension mismatch with the vector store
        actual_dim = EmbeddingService.get_actual_embedding_dimension()
        self.store = VectorStore(
            dimension=actual_dim
        )
        # Also update the embedder dimension to match
        self.embedder.dimension = actual_dim

    def process(
        self,
        document_id: int,
        filepath: Path,
    ):

        db = SessionLocal()

        overall_start = time.time()

        try:

            document = (
                db.query(Document)
                .filter(Document.id == document_id)
                .first()
            )

            if document is None:
                print(f"Document {document_id} not found.")
                return

            print(f"\n========== Processing Document {document.id} ==========")

            # --------------------------------------------------
            # STEP 1 : Parse document
            # --------------------------------------------------

            start = time.time()

            pages = self.parser.parse(filepath)

            print(f"Pages extracted : {len(pages)}")
            print(f"Parsing finished in {time.time()-start:.2f}s")

            if not pages:
                raise Exception("Parser returned zero pages.")

            document.page_count = len(pages)
            document.status = "processing"

            db.commit()

            # --------------------------------------------------
            # STEP 2 : Chunk text
            # --------------------------------------------------

            start = time.time()

            chunks = self.embedder.chunk_text(pages)

            print(f"Chunks created : {len(chunks)}")
            print(f"Chunking finished in {time.time()-start:.2f}s")

            if len(chunks) == 0:
                raise Exception("No chunks were generated.")

            # --------------------------------------------------
            # STEP 3 : Generate embeddings
            # --------------------------------------------------

            start = time.time()

            texts = [c["text"] for c in chunks]

            print("Generating Gemini embeddings...")

            vectors = self.embedder.embed(texts)

            print(f"Embedding shape : {vectors.shape}")
            print(f"Embedding finished in {time.time()-start:.2f}s")

            # --------------------------------------------------
            # STEP 4 : Save chunk metadata
            # --------------------------------------------------

            chunk_rows = []

            for index, chunk in enumerate(chunks):

                row = Chunk(
                    document_id=document.id,
                    chunk_index=index,
                    text=chunk["text"],
                    vector_id=-1,
                    page_number=chunk.get("page_number"),
                )

                db.add(row)
                chunk_rows.append(row)

            db.flush()

            print(f"Saved {len(chunk_rows)} chunk rows.")

            # --------------------------------------------------
            # STEP 5 : Store vectors in FAISS
            # --------------------------------------------------

            meta = [
                {
                    "document_id": document.id,
                    "chunk_id": row.id,
                    "text": row.text,
                    "page_number": row.page_number,
                }
                for row in chunk_rows
            ]

            start = time.time()

            vector_ids = self.store.add(
                vectors,
                meta
            )

            for row, vid in zip(chunk_rows, vector_ids):
                row.vector_id = vid

            print(f"Stored vectors in {time.time()-start:.2f}s")

            # --------------------------------------------------
            # STEP 6 : Finalize
            # --------------------------------------------------

            document.chunk_count = len(chunks)
            document.status = "ready"

            db.add(document)
            db.commit()
            db.refresh(document)

            print("Document marked READY.")

            # --------------------------------------------------
            # STEP 7 : Maintenance extraction
            # --------------------------------------------------

            try:
                MaintenanceIntelligence().extract_from_document(
                    db,
                    document.id,
                )

                print("Maintenance extraction complete.")

            except Exception as maintenance_error:

                print(
                    "Maintenance extraction failed:",
                    maintenance_error,
                )

            # --------------------------------------------------
            # STEP 8 : Compliance auto-population
            # --------------------------------------------------

            try:
                created = ComplianceEngine().auto_populate_from_maintenance(
                    db,
                )

                print(f"Compliance records created/updated: {created}")

            except Exception as compliance_error:

                print(
                    "Compliance auto-population failed:",
                    compliance_error,
                )

            print(
                f"Finished in {time.time()-overall_start:.2f}s"
            )

            print("=========================================\n")

        except Exception as e:

            print("\n========= INGESTION FAILED =========")
            print(e)
            print("====================================")

            db.rollback()

            try:
                document = (
                    db.query(Document)
                    .filter(Document.id == document_id)
                    .first()
                )

                if document:
                    document.status = "failed"
                    db.commit()

            except Exception:
                db.rollback()

        finally:
            db.close()

