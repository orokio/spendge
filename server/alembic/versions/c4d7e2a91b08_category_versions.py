"""category_versions snapshot

Revision ID: c4d7e2a91b08
Revises: 9f3c1a70b2d1
Create Date: 2026-11-26 01:05:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c4d7e2a91b08'
down_revision: Union[str, Sequence[str], None] = '9f3c1a70b2d1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'category_versions',
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('payload', sa.Text(), nullable=False),
        sa.Column('created_at', sa.String(), nullable=False),
        sa.Column('note', sa.String(), nullable=True),
        sa.PrimaryKeyConstraint('version'),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('category_versions')
