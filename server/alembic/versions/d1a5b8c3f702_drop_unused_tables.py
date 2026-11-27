"""drop unused account/entitlement/usage/diagnostic/event tables

Revision ID: d1a5b8c3f702
Revises: c9f2a7d1e803
Create Date: 2026-11-27 13:05:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = 'd1a5b8c3f702'
down_revision: Union[str, Sequence[str], None] = 'c9f2a7d1e803'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_DROPPED = ('events', 'diagnostics', 'usage', 'entitlements', 'accounts')


def upgrade() -> None:
    for table in _DROPPED:
        op.drop_table(table)


def downgrade() -> None:
    op.create_table(
        'accounts',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('apple_subject', sa.String(), nullable=True),
        sa.Column('created_at', sa.String(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('apple_subject'),
    )
    op.create_table(
        'entitlements',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('account_id', sa.String(), nullable=False),
        sa.Column('original_transaction_id', sa.String(), nullable=False),
        sa.Column('product_id', sa.String(), nullable=False),
        sa.Column('expires_at', sa.String(), nullable=True),
        sa.Column('status', sa.String(), nullable=False),
        sa.Column('updated_at', sa.String(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('original_transaction_id'),
    )
    op.create_index('ix_entitlements_account_expires', 'entitlements', ['account_id', 'expires_at'])
    op.create_table(
        'usage',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('account_id', sa.String(), nullable=True),
        sa.Column('device_id', sa.String(), nullable=False),
        sa.Column('idempotency_key', sa.String(), nullable=False),
        sa.Column('kind', sa.String(), nullable=False),
        sa.Column('tokens', sa.Integer(), nullable=False),
        sa.Column('result', sa.Text(), nullable=True),
        sa.Column('created_at', sa.String(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('idempotency_key'),
    )
    op.create_index('ix_usage_account_created', 'usage', ['account_id', 'created_at'])
    op.create_table(
        'diagnostics',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('device_id', sa.String(), nullable=False),
        sa.Column('account_id', sa.String(), nullable=True),
        sa.Column('app_version', sa.String(), nullable=True),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('result', sa.String(), nullable=True),
        sa.Column('code', sa.String(), nullable=True),
        sa.Column('at', sa.String(), nullable=False),
        sa.Column('created_at', sa.String(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_table(
        'events',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('account_id', sa.String(), nullable=True),
        sa.Column('device_id', sa.String(), nullable=True),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('props', sa.Text(), nullable=True),
        sa.Column('created_at', sa.String(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_events_created', 'events', ['created_at'])
