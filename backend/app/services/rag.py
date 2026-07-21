import json

from google import genai

from app.config import GEMINI_API_KEY, LLM_MODEL, TOP_K
from app.services.embeddings import EmbeddingService
from app.services.vectorstore import VectorStore

client = genai.Client(api_key=GEMINI_API_KEY)

SYSTEM_PROMPT = """
You are PlantMind AI, an AI assistant for industrial maintenance and engineering.

Use ONLY the supplied context to answer.

Rules:
- Never hallucinate.
- If the answer is not present in the context, reply:
  "I could not find this information in the uploaded documents."
- Be concise and technical.
- Mention the relevant source document(s).
- Return ONLY valid JSON.

{
  "answer": "...",
  "confidence": 0.0,
  "reasoning": "..."
}
"""


class RAGEngine:

    def __init__(self):
        self.embedder = EmbeddingService()
        # Use auto-detected dimension to match what the ingestion pipeline uses
        actual_dim = EmbeddingService.get_actual_embedding_dimension()
        self.embedder.dimension = actual_dim
        self.store = VectorStore(dimension=actual_dim)

    def query(self, question: str, top_k: int = TOP_K) -> dict:

        # -----------------------------
        # Embed query
        # -----------------------------
        try:
            query_vec = self.embedder.embed([question])[0]
        except Exception as e:
            return {
                "answer": f"Failed to generate embedding for the query: {str(e)}. Please try again or check your API key.",
                "confidence": 0.0,
                "reasoning": f"Embedding error: {str(e)}",
                "sources": [],
            }

        # -----------------------------
        # Retrieve similar chunks
        # -----------------------------
        try:
            retrieved = self.store.search(query_vec, k=top_k)
        except Exception as e:
            return {
                "answer": f"Vector search failed: {str(e)}",
                "confidence": 0.0,
                "reasoning": f"Search error: {str(e)}",
                "sources": [],
            }

        if not retrieved:
            return {
                "answer": "No documents have been indexed yet, or nothing relevant was found.",
                "confidence": 0.0,
                "reasoning": "",
                "sources": [],
            }

        # -----------------------------
        # Build context
        # -----------------------------
        context_blocks = []

        for chunk in retrieved:
            tag = f"[Doc {chunk.get('document_id')} | Chunk {chunk.get('chunk_id')}]"
            context_blocks.append(
                f"{tag}\n{chunk['text']}"
            )

        context = "\n\n------------------\n\n".join(context_blocks)

        prompt = f"""
{SYSTEM_PROMPT}

Context:
{context}

Question:
{question}
"""

        # -----------------------------
        # Gemini Call
        # -----------------------------
        try:
            response = client.models.generate_content(
                model=LLM_MODEL,
                contents=prompt,
            )
        except Exception as e:
            return {
                "answer": f"Gemini API Error: {str(e)}",
                "confidence": 0.0,
                "reasoning": "",
                "sources": [],
            }

        # -----------------------------
        # Extract response text
        # -----------------------------
        text = ""

        if hasattr(response, "text") and response.text:
            text = response.text.strip()
        else:
            return {
                "answer": "Gemini returned an empty response.",
                "confidence": 0.0,
                "reasoning": "",
                "sources": [],
            }

        # -----------------------------
        # Remove markdown formatting
        # -----------------------------
        if text.startswith("```"):
            text = (
                text.replace("```json", "")
                .replace("```", "")
                .strip()
            )

        # -----------------------------
        # Parse JSON
        # -----------------------------
        try:
            parsed = json.loads(text)
        except Exception:
            parsed = {
                "answer": text,
                "confidence": 0.5,
                "reasoning": "Model returned non-JSON output."
            }

        # -----------------------------
        # Calculate confidence
        # -----------------------------
        avg_similarity = (
            sum(c["score"] for c in retrieved) / len(retrieved)
        )

        final_confidence = round(
            (
                parsed.get("confidence", 0.5)
                + avg_similarity
            ) / 2,
            2,
        )

        # -----------------------------
        # Return result
        # -----------------------------
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