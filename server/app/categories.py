"""分类参考数据：读取（直接读 DB）与导入（运维 CLI）。

接口线程只读，不写库；变更由运维命令导入并递增 categoriesVersion。
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone

from sqlalchemy import select

from app.db import SessionLocal
from app.models import AppConfig, Category, CategoryVersion

logger = logging.getLogger(__name__)

VERSION_KEY = "categories_version"

KINDS = ("expense", "income")
GOAL_KINDS = ("countLimit", "budget", "shareCap")  # 契约 §4.2.1，封闭值域


def _row_to_item(row: Category) -> dict:
    return {
        "code": row.code,
        "name": row.name,
        "iconName": row.icon_name,
        "colorHex": row.color_hex,
        "kindRawValue": row.kind_raw_value,
        "domainRawValue": row.domain_raw_value,
        "scope": row.scope,
        "sortOrder": row.sort_order,
        "isArchived": bool(row.is_archived),
        "goalKinds": [v for v in (row.goal_kinds or "").split(",") if v],
    }


def _load_from_db() -> dict:
    db = SessionLocal()
    try:
        cfg = db.get(AppConfig, VERSION_KEY)
        version = int(cfg.value) if cfg is not None else 0
        rows = db.execute(
            select(Category).order_by(Category.sort_order, Category.code)
        ).scalars().all()
        return {"version": version, "items": [_row_to_item(r) for r in rows]}
    finally:
        db.close()


def load_snapshot() -> dict:
    """返回 {version, items}；直接读 DB（register 只在版本变化时才带分类，查询频率很低）。"""
    return _load_from_db()


def _normalize_goal_kinds(code: str, raw) -> str:
    """解析并校验 goalKinds（数组或逗号串都接受），返回规范化逗号串。"""
    if raw is None:
        return ""
    if isinstance(raw, str):
        values = [v.strip() for v in raw.split(",")]
    elif isinstance(raw, (list, tuple, set)):
        values = [str(v).strip() for v in raw]
    else:
        raise ValueError(f"分类 {code} 的 goalKinds 类型非法: {type(raw).__name__}")

    values = [v for v in values if v]
    invalid = [v for v in values if v not in GOAL_KINDS]
    if invalid:
        raise ValueError(f"分类 {code} 的 goalKinds 含非法值: {', '.join(invalid)}")
    # 去重并按固定顺序输出，避免仅顺序变化被误判为实质变更
    present = set(values)
    return ",".join(v for v in GOAL_KINDS if v in present)


def _normalize(item: dict) -> dict:
    code = str(item.get("code") or "").strip()
    kind = str(item.get("kindRawValue") or "").strip()
    if not code:
        raise ValueError("分类缺少 code")
    if kind not in KINDS:
        raise ValueError(f"分类 {code} 的 kindRawValue 非法: {kind!r}")
    return {
        "code": code,
        "name": str(item.get("name") or "").strip(),
        "icon_name": item.get("iconName"),
        "color_hex": item.get("colorHex"),
        "kind_raw_value": kind,
        "domain_raw_value": item.get("domainRawValue"),
        "scope": item.get("scope"),
        "sort_order": int(item.get("sortOrder") or 0),
        "is_archived": 1 if item.get("isArchived") else 0,
        "goal_kinds": _normalize_goal_kinds(code, item.get("goalKinds")),
    }


def _snapshot_payload(db) -> str:
    rows = db.execute(
        select(Category).order_by(Category.sort_order, Category.code)
    ).scalars().all()
    return json.dumps([_row_to_item(r) for r in rows], ensure_ascii=False)


def _load_seed_items(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as fh:
        raw_items = json.load(fh)
    if not isinstance(raw_items, list):
        raise ValueError("种子文件必须是 JSON 数组")
    items = [_normalize(it) for it in raw_items]
    codes = [it["code"] for it in items]
    if len(codes) != len(set(codes)):
        raise ValueError("种子文件存在重复 code")
    return items


def _apply_items(items: list[dict], note: str) -> tuple[bool, int]:
    """按给定全量列表同步库；有实质变更才 +1，并在同一事务写快照。"""
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    codes = [it["code"] for it in items]
    db = SessionLocal()
    try:
        cfg = db.get(AppConfig, VERSION_KEY)
        version = int(cfg.value) if cfg is not None else 0
        existing = {row.code: row for row in db.execute(select(Category)).scalars()}

        changed = False
        for item in items:
            row = existing.get(item["code"])
            fields = {k: v for k, v in item.items() if k != "code"}
            if row is None:
                db.add(Category(**item))
                changed = True
                continue
            if any(getattr(row, k) != v for k, v in fields.items()):
                for k, v in fields.items():
                    setattr(row, k, v)
                changed = True

        missing = sorted(set(existing) - set(codes))
        if missing:
            # code 永不删除：库里多出来的只在日志提示，不自动移除
            logger.warning("categories: seed 未包含已有 code（保留）: %s", ", ".join(missing))

        if changed:
            version += 1
            if cfg is None:
                db.add(AppConfig(key=VERSION_KEY, value=str(version), updated_at=now_iso))
            else:
                cfg.value = str(version)
                cfg.updated_at = now_iso
            db.flush()
            db.add(
                CategoryVersion(
                    version=version,
                    payload=_snapshot_payload(db),
                    created_at=now_iso,
                    note=note,
                )
            )
        elif version > 0 and db.get(CategoryVersion, version) is None:
            # 老数据没有快照：补一条当前版本的，后续回放才完整
            db.add(
                CategoryVersion(
                    version=version,
                    payload=_snapshot_payload(db),
                    created_at=now_iso,
                    note="backfill",
                )
            )
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

    return changed, version


def apply_seed(path: str) -> tuple[bool, int]:
    """把种子文件同步进库；有实质变更才把 categoriesVersion +1（单调递增）。"""
    return _apply_items(_load_seed_items(path), note=f"import {path.split('/')[-1]}")


def get_version(version: int) -> dict | None:
    """读取某个版本快照；不存在返回 None。"""
    db = SessionLocal()
    try:
        row = db.get(CategoryVersion, version)
        if row is None:
            return None
        return {
            "version": row.version,
            "created_at": row.created_at,
            "note": row.note,
            "payload": json.loads(row.payload),
        }
    finally:
        db.close()


def _fmt(value) -> str:
    if isinstance(value, (list, tuple)):
        return json.dumps(list(value), ensure_ascii=False)
    return "null" if value is None else str(value)


_FIELD_LABELS = {
    "name": "name",
    "icon_name": "iconName",
    "color_hex": "colorHex",
    "kind_raw_value": "kindRawValue",
    "domain_raw_value": "domainRawValue",
    "scope": "scope",
    "sort_order": "sortOrder",
    "is_archived": "isArchived",
    "goal_kinds": "goalKinds",
}


def _fmt_field(field: str, value) -> str:
    if field == "goal_kinds":
        return _fmt([v for v in (value or "").split(",") if v])
    if field == "is_archived":
        return "true" if value else "false"
    return _fmt(value)


def diff_seed(path: str) -> dict:
    """只读对比种子与当前库：不写库、不升版本。"""
    items = _load_seed_items(path)
    db = SessionLocal()
    try:
        cfg = db.get(AppConfig, VERSION_KEY)
        version = int(cfg.value) if cfg is not None else 0
        rows = db.execute(
            select(Category).order_by(Category.sort_order, Category.code)
        ).scalars().all()
    finally:
        db.close()

    # 与种子同样规范化后再比，避免字段命名（camel/snake）差异造成误报
    existing = {row.code: _normalize(_row_to_item(row)) for row in rows}
    codes = {item["code"] for item in items}

    added: list[str] = []
    changed: dict[str, dict[str, tuple]] = {}
    for item in items:
        current = existing.get(item["code"])
        if current is None:
            added.append(item["code"])
            continue
        fields = {k: v for k, v in item.items() if k != "code"}
        delta = {k: (current[k], v) for k, v in fields.items() if current[k] != v}
        if delta:
            changed[item["code"]] = delta

    kept = sorted(set(existing) - codes)
    will_bump = bool(added or changed)
    return {
        "version": version,
        "new_version": version + 1 if will_bump else version,
        "will_bump": will_bump,
        "seed_count": len(items),
        "db_count": len(existing),
        "added": added,
        "changed": changed,
        "kept": kept,
    }


def format_diff(path: str, result: dict) -> str:
    lines = [
        f"种子: {path}（{result['seed_count']} 条）",
        f"库内: v{result['version']}（{result['db_count']} 条）",
        "",
    ]
    if result["added"]:
        lines.append(f"新增 ({len(result['added'])}):")
        lines += [f"  + {code}" for code in result["added"]]
    if result["changed"]:
        lines.append(f"修改 ({len(result['changed'])}):")
        for code, delta in result["changed"].items():
            lines.append(f"  ~ {code}")
            for field, (old, new) in delta.items():
                label = _FIELD_LABELS.get(field, field)
                lines.append(f"      {label}: {_fmt_field(field, old)} -> {_fmt_field(field, new)}")
    if result["kept"]:
        lines.append(f"库内多出（不会删除，{len(result['kept'])}）:")
        lines += [f"  ! {code}" for code in result["kept"]]
    if not (result["added"] or result["changed"] or result["kept"]):
        lines.append("无差异")
    lines.append("")
    if result["will_bump"]:
        lines.append(f"结论: 有实质变更，导入后 categoriesVersion {result['version']} -> {result['new_version']}")
    else:
        lines.append(f"结论: 无实质变更，导入不会升版本（保持 v{result['version']}）")
    return "\n".join(lines)


def list_versions(limit: int = 50) -> list[dict]:
    db = SessionLocal()
    try:
        rows = db.execute(
            select(CategoryVersion)
            .order_by(CategoryVersion.version.desc())
            .limit(limit)
        ).scalars().all()
        return [
            {"version": r.version, "created_at": r.created_at, "note": r.note}
            for r in rows
        ]
    finally:
        db.close()


def restore(version: int) -> tuple[bool, int]:
    """以某个历史版本为准回放；版本号仍然只增不减（回放也会 +1）。"""
    snapshot = get_version(version)
    if snapshot is None:
        raise ValueError(f"版本 {version} 不存在")
    items = [_normalize(it) for it in snapshot["payload"]]
    return _apply_items(items, note=f"restore from v{version}")


def main(argv: list[str]) -> int:
    args = argv[1:]
    if len(args) == 1 and not args[0].startswith("--"):
        changed, version = apply_seed(args[0])
        print(f"changed={changed} categoriesVersion={version}")
        return 0

    if args[:1] == ["--versions"]:
        for row in list_versions():
            print(f"v{row['version']}\t{row['created_at']}\t{row['note'] or ''}")
        return 0

    if args[:1] == ["--show"] and len(args) == 2:
        snapshot = get_version(int(args[1]))
        if snapshot is None:
            print(f"版本 {args[1]} 不存在")
            return 1
        print(json.dumps(snapshot, ensure_ascii=False, indent=2))
        return 0

    if args[:1] == ["--diff"] and len(args) == 2:
        print(format_diff(args[1], diff_seed(args[1])))
        return 0

    if args[:1] == ["--restore"] and len(args) == 2:
        changed, version = restore(int(args[1]))
        print(f"changed={changed} categoriesVersion={version}")
        return 0

    print(
        "用法:\n"
        "  python -m app.categories <seed.json>   # 导入/更新\n"
        "  python -m app.categories --versions    # 列出历史版本\n"
        "  python -m app.categories --diff <seed.json>  # 只对比，不写库\n"
        "  python -m app.categories --show N      # 查看第 N 版\n"
        "  python -m app.categories --restore N   # 回放到第 N 版（版本仍 +1）"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
