import faiss
import numpy as np
import pickle
import logging
from app.config import VECTORSTORE_DIR

logger = logging.getLogger(__name__)

INDEX_PATH = VECTORSTORE_DIR / "index.faiss"
META_PATH = VECTORSTORE_DIR / "meta.pkl"

class VectorStore:
    def __init__(self, dimension: int):
        self.dimension = dimension
        self.metadata = {}
        if INDEX_PATH.exists() and META_PATH.exists():
            try:
                loaded_index = faiss.read_index(str(INDEX_PATH))
                # Validate loaded index dimension matches expected dimension
                if loaded_index.d == dimension:
                    self.index = loaded_index
                    with open(META_PATH, "rb") as f:
                        self.metadata = pickle.load(f)
                    logger.info(f"Loaded existing FAISS index with {self.index.ntotal} vectors (dim={dimension})")
                else:
                    logger.warning(
                        f"Saved index dimension ({loaded_index.d}) does not match expected ({dimension}). "
                        "Rebuilding index."
                    )
                    self.index = faiss.IndexFlatIP(dimension)
                    self.metadata = {}
            except Exception as e:
                logger.error(f"Failed to load FAISS index: {e}. Creating new index.")
                self.index = faiss.IndexFlatIP(dimension)
                self.metadata = {}
        else:
            self.index = faiss.IndexFlatIP(dimension)
            logger.info(f"Created new FAISS index (dim={dimension})")

    def rebuild(self, dimension: int) -> None:
        """
        Rebuild the FAISS index with a new dimension, discarding any existing data.
        Call this when a dimension mismatch is detected.
        """
        logger.warning(
            f"Rebuilding FAISS index: old dimension={self.dimension}, new dimension={dimension}"
        )
        self.dimension = dimension
        self.index = faiss.IndexFlatIP(dimension)
        self.metadata = {}
        self._persist()
        logger.info(f"FAISS index rebuilt with dimension={dimension}")

    def add(self, vectors: np.ndarray, meta_entries: list) -> list:
        if vectors.shape[0] == 0:
            return []
        if vectors.shape[1] != self.dimension:
            logger.error(
                f"Dimension mismatch: vectors have dimension {vectors.shape[1]}, "
                f"but store dimension is {self.dimension}. "
                "Auto-rebuilding index with correct dimension."
            )
            # Auto-rebuild the index with the correct dimension
            self.rebuild(vectors.shape[1])
        start_id = self.index.ntotal
        faiss.normalize_L2(vectors)
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
        query = query_vector.reshape(1, -1).astype(np.float32)
        if query.shape[1] != self.dimension:
            raise ValueError(
                f"Query dimension {query.shape[1]} does not match "
                f"store dimension {self.dimension}"
            )
        faiss.normalize_L2(query)
        scores, indices = self.index.search(
            query,
            min(k, self.index.ntotal)
            )
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
        VECTORSTORE_DIR.mkdir(parents=True, exist_ok=True)
        faiss.write_index(self.index, str(INDEX_PATH))
        with open(META_PATH, "wb") as f:
            pickle.dump(self.metadata, f)
