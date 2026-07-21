from google import genai
import json

from app.config import GEMINI_API_KEY, LLM_MODEL
from app.services.rag import RAGEngine

client = genai.Client(api_key=GEMINI_API_KEY)

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


def _extract_json_from_response(text: str) -> dict:
    """Extract JSON from Gemini response, stripping markdown code fences if present."""
    if not text:
        return {}
    cleaned = text.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n", 1)
        cleaned = lines[1] if len(lines) > 1 else cleaned
        if "```" in cleaned:
            cleaned = cleaned.rsplit("```", 1)[0]
    cleaned = cleaned.strip()
    return json.loads(cleaned)


class RootCauseAnalyzer:
    def __init__(self):
        self.rag = RAGEngine()

    def analyze(self, incident_description: str) -> dict:
        retrieval = self.rag.query(incident_description, top_k=6)
        context = "\n\n".join(s["excerpt"] for s in retrieval.get("sources", []))

        prompt = f"{RCA_PROMPT}\n\nIncident: {incident_description}\n\nHistorical context:\n{context}"
        response = client.models.generate_content(
            model=LLM_MODEL,
            contents=prompt,
        )
        text = response.text if hasattr(response, "text") and response.text else ""
        result = _extract_json_from_response(text)
        result["sources"] = retrieval.get("sources", [])
        return result

