"""Nexus — FastAPI Application Entry Point"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.models.database import init_db
from app.routers import auth_router, music_router, search_router, monitoring_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup / shutdown lifecycle."""
    await init_db()
    yield


app = FastAPI(
    title="Nexus Music API",
    description="YouTube-based music streaming backend with quota-safe search",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS — allow Flutter client (dev & prod)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Tighter in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(auth_router.router)
app.include_router(music_router.router)
app.include_router(search_router.router)
app.include_router(monitoring_router.router)


@app.get("/health")
async def health():
    """Simple health check."""
    return {"status": "ok", "version": "1.0.0"}