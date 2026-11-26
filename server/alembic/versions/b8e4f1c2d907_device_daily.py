"""device_daily and user_stats_daily

Revision ID: b8e4f1c2d907
Revises: a7b1c9d4e620
Create Date: 2026-11-26 13:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b8e4f1c2d907'
down_revision: Union[str, Sequence[str], None] = 'a7b1c9d4e620'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'device_daily',
        sa.Column('device_id', sa.String(), nullable=False),
        sa.Column('stat_date', sa.String(), nullable=False),
        sa.Column('first_seen_at', sa.String(), nullable=False),
        sa.Column('last_seen_at', sa.String(), nullable=False),
        sa.Column('register_count', sa.Integer(), nullable=False),
        sa.Column('app_version', sa.String(), nullable=True),
        sa.Column('build', sa.String(), nullable=True),
        sa.PrimaryKeyConstraint('device_id', 'stat_date'),
    )
    op.create_index('idx_device_daily_date', 'device_daily', ['stat_date'], unique=False)

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


def downgrade() -> None:
    op.drop_table('user_stats_daily')
    op.drop_index('idx_device_daily_date', table_name='device_daily')
    op.drop_table('device_daily')
