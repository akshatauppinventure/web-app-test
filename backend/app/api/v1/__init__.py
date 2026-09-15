"""Versioned API (ADR-0008 §5)."""

from fastapi import APIRouter

from app.api.v1 import hello, me

router = APIRouter(prefix="/v1")
router.include_router(me.router)
router.include_router(hello.router)
