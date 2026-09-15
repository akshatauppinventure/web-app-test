"""Visit bookkeeping for the hello endpoint."""

from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.visit import Visit


@dataclass(frozen=True, slots=True)
class VisitResult:
    display_name: str
    previous_visit: datetime | None
    visit_count: int


async def record_visit(session: AsyncSession, *, sub: str, display_name: str) -> VisitResult:
    """Upsert the caller's row and return the previous visit time and new count.

    The session's transaction already carries the RLS context for ``sub``; the explicit
    ``owner_sub == sub`` filter is the service-layer scoping required by ADR-0011 §4.2.
    """
    now = datetime.now(tz=UTC)
    previous = (
        await session.execute(select(Visit.last_visit).where(Visit.owner_sub == sub))
    ).scalar_one_or_none()

    stmt = insert(Visit).values(
        owner_sub=sub, display_name=display_name, last_visit=now, visit_count=1
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[Visit.owner_sub],
        set_={
            "display_name": stmt.excluded.display_name,
            "last_visit": stmt.excluded.last_visit,
            "visit_count": Visit.visit_count + 1,
        },
    ).returning(Visit.visit_count)
    count = (await session.execute(stmt)).scalar_one()
    return VisitResult(display_name=display_name, previous_visit=previous, visit_count=count)
