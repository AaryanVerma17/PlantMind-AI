# Shared helper utilities for the backend (extend as needed).
def truncate(text: str, length: int = 200) -> str:
    return text if len(text) <= length else text[:length] + "..."
