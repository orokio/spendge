"""用户统计（CST，T-1）：输出一个覆盖写的文本文件。

口径见 docs/user-stats-spec.md。只统计昨天：新增（created_at 落在当天）、
活跃（当天有 register 记录，来自 device_daily）、以及按 build 的分布。
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import text

from app.db import SessionLocal

CST = ZoneInfo("Asia/Shanghai")
REPORT_PATH = os.getenv("STATS_REPORT", "/home/ubuntu/stats/latest.txt")

VALID_DEVICE = "length(d.id) = 36 AND d.id = upper(d.id) AND d.secret_hash <> ''"

# 活跃 = 当天有 register 记录（device_daily）∪ 当天首次登记（created_at），
# 保证「新增」一定是「活跃」的子集；后者也覆盖历史缺 device_daily 的日子。
_ACTIVE_SQL = text(
    f"""
    SELECT COALESCE(dd.build, d.build, 'unknown') AS build, COUNT(*) AS n
    FROM devices d
    LEFT JOIN device_daily dd ON dd.device_id = d.id AND dd.stat_date = :day
    WHERE (dd.device_id IS NOT NULL
           OR (d.created_at >= :start AND d.created_at < :end))
      AND {VALID_DEVICE}
    GROUP BY 1
    """
)

_NEW_SQL = text(
    f"""
    SELECT COUNT(*) FROM devices d
    WHERE d.created_at >= :start AND d.created_at < :end AND {VALID_DEVICE}
    """
)

_NEW_BY_BUILD_SQL = text(
    f"""
    SELECT COALESCE(dd.build, d.build, 'unknown') AS build, COUNT(*) AS n
    FROM devices d
    LEFT JOIN device_daily dd ON dd.device_id = d.id AND dd.stat_date = :day
    WHERE d.created_at >= :start AND d.created_at < :end AND {VALID_DEVICE}
    GROUP BY 1
    """
)


def date_cst(iso: str) -> str:
    """UTC ISO8601（带 Z）→ 东八区日期 YYYY-MM-DD。"""
    dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return dt.astimezone(CST).date().isoformat()


def yesterday_cst() -> str:
    return (datetime.now(CST).date() - timedelta(days=1)).isoformat()


def day_window(day: str) -> tuple[str, str]:
    """CST 日期 → [start, end) 的 UTC ISO8601 边界。"""
    d = date.fromisoformat(day)
    start = datetime(d.year, d.month, d.day, tzinfo=CST)
    end = start + timedelta(days=1)
    fmt = "%Y-%m-%dT%H:%M:%SZ"
    return (
        start.astimezone(ZoneInfo("UTC")).strftime(fmt),
        end.astimezone(ZoneInfo("UTC")).strftime(fmt),
    )


def compute(day: str, session=None) -> dict:
    """返回 {day, new, active, builds:[{build,new,active}]}。"""
    start, end = day_window(day)
    db = session or SessionLocal()
    try:
        active = {
            r["build"]: int(r["n"])
            for r in db.execute(_ACTIVE_SQL, {"day": day, "start": start, "end": end}).mappings()
        }
        new_by_build = {
            r["build"]: int(r["n"])
            for r in db.execute(_NEW_BY_BUILD_SQL, {"day": day, "start": start, "end": end}).mappings()
        }
        new_total = int(db.execute(_NEW_SQL, {"start": start, "end": end}).scalar_one())

        builds = sorted(
            set(active) | set(new_by_build),
            key=lambda b: (b == "unknown", b),
        )
        return {
            "day": day,
            "new": new_total,
            "active": sum(active.values()),
            "builds": [
                {"build": b, "new": new_by_build.get(b, 0), "active": active.get(b, 0)}
                for b in builds
            ],
        }
    finally:
        if session is None:
            db.close()


def render(result: dict) -> str:
    now = datetime.now(CST).strftime("%Y-%m-%d %H:%M")
    lines = [
        f"统计日期: {result['day']}（东八区）",
        f"生成时间: {now}（东八区）",
        "",
        f"新增: {result['new']}",
        f"活跃: {result['active']}",
        "",
        "build    新增   活跃",
    ]
    for b in result["builds"]:
        lines.append(f"{b['build']:<8} {b['new']:>4}   {b['active']:>4}")
    return "\n".join(lines) + "\n"


def write_report(day: str | None = None, session=None) -> tuple[str, dict]:
    """计算 T-1（或指定日）并覆盖写同一个文件。"""
    day = day or yesterday_cst()
    result = compute(day, session)
    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
    with open(REPORT_PATH, "w", encoding="utf-8") as fh:
        fh.write(render(result))
    return REPORT_PATH, result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="生成 T-1 用户统计（默认昨天，东八区）")
    parser.add_argument("--date", help="YYYY-MM-DD，默认昨天（东八区）")
    args = parser.parse_args(argv)

    path, result = write_report(args.date)
    print(f"{result['day']} new={result['new']} active={result['active']} -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
