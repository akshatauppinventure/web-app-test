"""visits table with forced row-level security

Revision ID: 0001
Revises:
Create Date: 2026-09-15
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "visits",
        sa.Column("owner_sub", sa.Text(), primary_key=True),
        sa.Column("display_name", sa.Text(), nullable=False),
        sa.Column("last_visit", sa.DateTime(timezone=True), nullable=False),
        sa.Column("visit_count", sa.Integer(), nullable=False, server_default="0"),
        sa.CheckConstraint("visit_count >= 0", name="visits_visit_count_nonnegative"),
        sa.CheckConstraint("length(owner_sub) BETWEEN 1 AND 255", name="visits_owner_sub_len"),
        sa.CheckConstraint("length(display_name) <= 255", name="visits_display_name_len"),
    )
    # RLS: enabled AND forced so even the table owner is subject to the policy (ADR-0011 §4.3).
    op.execute("ALTER TABLE visits ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE visits FORCE ROW LEVEL SECURITY")
    # current_setting(..., true) returns NULL when unset -> no row matches -> fail closed.
    op.execute(
        """
        CREATE POLICY visits_owner_only ON visits
            FOR ALL
            USING (owner_sub = current_setting('app.user_id', true))
            WITH CHECK (owner_sub = current_setting('app.user_id', true))
        """
    )
    # Explicit grants (default privileges from initdb also cover this; belt and braces).
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON visits TO app_rw")


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS visits_owner_only ON visits")
    op.drop_table("visits")
