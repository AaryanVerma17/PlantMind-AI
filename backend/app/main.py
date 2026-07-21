from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database.db import init_db
from app.api import upload, chat, maintenance, compliance, reports

app = FastAPI(title="PlantMind AI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://plantmind-ai-1.onrender.com",
        "http://localhost:3000",
        "http://localhost:5173",   # Vite dev server
        "http://127.0.0.1:5173",
        "http://127.0.0.1:3000",
    ],
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
