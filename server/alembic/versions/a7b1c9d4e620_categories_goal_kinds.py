"""categories.goal_kinds

Revision ID: a7b1c9d4e620
Revises: c4d7e2a91b08
Create Date: 2026-11-26 02:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a7b1c9d4e620'
down_revision: Union[str, Sequence[str], None] = 'c4d7e2a91b08'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('categories', sa.Column('goal_kinds', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('categories', 'goal_kinds')
