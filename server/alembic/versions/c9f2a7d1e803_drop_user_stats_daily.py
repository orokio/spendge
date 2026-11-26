"""drop user_stats_daily

Revision ID: c9f2a7d1e803
Revises: b8e4f1c2d907
Create Date: 2026-11-26 13:50:00.000000

"""
from typing import Sequence, Union

from alembic import op


revision: str = 'c9f2a7d1e803'
down_revision: Union[str, Sequence[str], None] = 'b8e4f1c2d907'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_table('user_stats_daily')


def downgrade() -> None:
    import sqlalchemy as sa
    op.create_table(
        'user_stats_daily',
        sa.Column('stat_date', sa.String(), nullable=False),
        sa.Column('build', sa.String(), nullable=False),
        sa.Column('new_devices', sa.Integer(), nullable=False),
        sa.Column('active_devices', sa.Integer(), nullable=False),
        sa.Column('first_seen_at', sa.String(), nullable=True),
        sa.Column('last_seen_at', sa.String(), nullable=True),
        sa.Column('generated_at', sa.String(), nullable=False),
        sa.PrimaryKeyConstraint('stat_date', 'build'),
    )
