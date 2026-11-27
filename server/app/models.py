"""ORM 模型，对应数据模型（见 docs/server-design.md §6）。"""
from __future__ import annotations

from sqlalchemy import Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(String, primary_key=True)  # client deviceId
    secret_hash: Mapped[str] = mapped_column(String, nullable=False)
    app_version: Mapped[str | None] = mapped_column(String, nullable=True)
    build: Mapped[str | None] = mapped_column(String, nullable=True)
    platform: Mapped[str | None] = mapped_column(String, nullable=True)
    account_id: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[str] = mapped_column(String, nullable=False)
    last_seen_at: Mapped[str] = mapped_column(String, nullable=False)


class Session(Base):
    __tablename__ = "sessions"

    token_hash: Mapped[str] = mapped_column(String, primary_key=True)
    account_id: Mapped[str | None] = mapped_column(String, nullable=True)
    device_id: Mapped[str] = mapped_column(String, nullable=False)
    expires_at: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[str] = mapped_column(String, nullable=False)


class Category(Base):
    """服务端下发的分类参考数据（见 docs/api-contract.md §4.2）。"""

    __tablename__ = "categories"

    code: Mapped[str] = mapped_column(String, primary_key=True)  # 唯一、永久、不可复用
    name: Mapped[str] = mapped_column(String, nullable=False)
    icon_name: Mapped[str | None] = mapped_column(String, nullable=True)  # SF Symbol
    color_hex: Mapped[str | None] = mapped_column(String, nullable=True)  # #RRGGBB
    kind_raw_value: Mapped[str] = mapped_column(String, nullable=False)  # expense / income
    domain_raw_value: Mapped[str | None] = mapped_column(String, nullable=True)
    scope: Mapped[str | None] = mapped_column(String, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_archived: Mapped[int] = mapped_column(Integer, nullable=False, default=0)  # 0/1，删除即归档
    goal_kinds: Mapped[str | None] = mapped_column(String, nullable=True)  # 逗号分隔：countLimit,budget,shareCap


class DeviceDaily(Base):
    """按天聚合的设备活跃明细（write-behind 写入，min/max 幂等）。"""

    __tablename__ = "device_daily"

    device_id: Mapped[str] = mapped_column(String, primary_key=True)
    stat_date: Mapped[str] = mapped_column(String, primary_key=True)  # Asia/Shanghai 的 YYYY-MM-DD
    first_seen_at: Mapped[str] = mapped_column(String, nullable=False)  # UTC ISO8601
    last_seen_at: Mapped[str] = mapped_column(String, nullable=False)
    register_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    app_version: Mapped[str | None] = mapped_column(String, nullable=True)
    build: Mapped[str | None] = mapped_column(String, nullable=True)


class CategoryVersion(Base):
    """分类的版本快照（追加写，不更新不删除），用于审计与回放。"""

    __tablename__ = "category_versions"

    version: Mapped[int] = mapped_column(Integer, primary_key=True)
    payload: Mapped[str] = mapped_column(Text, nullable=False)  # 该版本全量分类 JSON
    created_at: Mapped[str] = mapped_column(String, nullable=False)
    note: Mapped[str | None] = mapped_column(String, nullable=True)


class AppConfig(Base):
    """单行配置（key/value），用于 categories_version 等。"""

    __tablename__ = "app_config"

    key: Mapped[str] = mapped_column(String, primary_key=True)
    value: Mapped[str] = mapped_column(String, nullable=False)
    updated_at: Mapped[str] = mapped_column(String, nullable=False)


Index("ix_devices_account_id", Device.account_id)
Index("ix_sessions_device_id", Session.device_id)
Index("ix_sessions_account_id", Session.account_id)
Index("ix_categories_sort", Category.sort_order)
Index("idx_device_daily_date", DeviceDaily.stat_date)