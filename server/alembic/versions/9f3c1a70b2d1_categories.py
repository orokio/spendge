"""categories and app_config

Revision ID: 9f3c1a70b2d1
Revises: 20f108f0a1fc
Create Date: 2026-11-26 00:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9f3c1a70b2d1'
down_revision: Union[str, Sequence[str], None] = '20f108f0a1fc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'categories',
        sa.Column('code', sa.String(), nullable=False),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('icon_name', sa.String(), nullable=True),
        sa.Column('color_hex', sa.String(), nullable=True),
        sa.Column('kind_raw_value', sa.String(), nullable=False),
        sa.Column('domain_raw_value', sa.String(), nullable=True),
        sa.Column('scope', sa.String(), nullable=True),
        sa.Column('sort_order', sa.Integer(), nullable=False),
        sa.Column('is_archived', sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint('code'),
    )
    op.create_index('ix_categories_sort', 'categories', ['sort_order'], unique=False)

    op.create_table(
        'app_config',
        sa.Column('key', sa.String(), nullable=False),
        sa.Column('value', sa.String(), nullable=False),
        sa.Column('updated_at', sa.String(), nullable=False),
        sa.PrimaryKeyConstraint('key'),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('app_config')
    op.drop_index('ix_categories_sort', table_name='categories')
    op.drop_table('categories')
