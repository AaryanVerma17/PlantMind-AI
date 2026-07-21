from google import genai
from app.config import GEMINI_API_KEY, CHUNK_SIZE, CHUNK_OVERLAP
from typing import List, Dict
import numpy as np
import time

client = genai.Client(api_key=GEMINI_API_KEY)

# gemini-embedding-001 outputs 3072-dimensional vectors (confirmed via API)
# DO NOT change this to 768 — it must match the actual Gemini output
EMBEDDING_DIMENSION = 3072
MAX_RETRIES = 3
RETRY_DELAY = 2  # seconds


class EmbeddingService:

    def __init__(self):
        self.dimension = EMBEDDING_DIMENSION

    @staticmethod
    def get_actual_embedding_dimension() -> int:
        """
        Auto-detect the actual embedding dimension by sending a small test query.
        This ensures the dimension always matches what the API outputs,
        even if the model is changed or updated.
        """
        try:
            test_response = client.models.embed_content(
                model="gemini-embedding-001",
                contents="test",
            )
            actual_dim = len(test_response.embeddings[0].values)
            if actual_dim != EMBEDDING_DIMENSION:
                print(
                    f"WARNING: Detected embedding dimension {actual_dim} "
                    f"but configured dimension is {EMBEDDING_DIMENSION}. "
                    f"Using detected dimension {actual_dim}."
                )
            return actual_dim
        except Exception as e:
            print(f"Could not detect embedding dimension: {e}. Falling back to {EMBEDDING_DIMENSION}.")
            return EMBEDDING_DIMENSION

    def chunk_text(self, pages: List[Dict]) -> List[Dict]:

        chunks = []

        for page in pages:

            text = page["text"]
            page_num = page.get("page_number")

            start = 0

            while start < len(text):

                end = start + CHUNK_SIZE

                chunk = text[start:end].strip()

                if chunk:
                    chunks.append({
                        "text": chunk,
                        "page_number": page_num
                    })

                start += CHUNK_SIZE - CHUNK_OVERLAP

        print(f"Created {len(chunks)} chunks")

        return chunks

    def embed(self, texts: List[str]) -> np.ndarray:

        print(f"Generating embeddings for {len(texts)} chunks...")

        embeddings = []

        start = time.time()

        for i, text in enumerate(texts):
            # Retry loop for transient API failures
            for attempt in range(MAX_RETRIES):
                try:
                    response = client.models.embed_content(
                        model="gemini-embedding-001",
                        contents=text,
                    )
                    embeddings.append(response.embeddings[0].values)
                    break
                except Exception as e:
                    print(f"Embedding attempt {attempt+1}/{MAX_RETRIES} failed for chunk {i+1}: {e}")
                    if attempt < MAX_RETRIES - 1:
                        time.sleep(RETRY_DELAY)
                    else:
                        # If all retries exhausted, raise so the caller knows
                        raise

            print(f"Embedded {i+1}/{len(texts)}")

        print(f"Embedding completed in {time.time()-start:.2f}s")

        return np.array(embeddings, dtype=np.float32)
