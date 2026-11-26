"""用户统计：按天汇总 device_daily → user_stats_daily（口径见 docs/user-stats-spec.md）。

定时任务用 Python 计算日期（Asia/Shanghai），不依赖 SQLite 的 datetime() 处理带 Z 的字符串。
"""
from __future__ import annotations

import argparse
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import text

from app.db import SessionLocal

CST = ZoneInfo("Asia/Shanghai")

# 合法设备：客户端只生成大写 UUID，且走过完整 register（secret_hash 非空）
VALID_DEVICE = "length(d.id) = 36 AND d.id = upper(d.id) AND d.secret_hash <> ''"

_UPSERT_SQL = text(
    """
    INSERT INTO user_stats_daily
        (stat_date, build, new_devices, active_devices, first_seen_at, last_seen_at, generated_at)
    VALUES (:stat_date, :build, :new_devices, :active_devices, :first_seen_at, :last_seen_at, :generated_at)
    ON CONFLICT(stat_date, build) DO UPDATE SET
        new_devices = excluded.new_devices,
        active_devices = excluded.active_devices,
        first_seen_at = excluded.first_seen_at,
        last_seen_at = excluded.last_seen_at,
        generated_at = excluded.generated_at
    """
)

_ACTIVE_SQL = text(
    f"""
    SELECT COALESCE(dd.build, 'unknown') AS build,
           COUNT(*) AS active_devices,
           MIN(dd.first_seen_at) AS first_seen_at,
           MAX(dd.last_seen_at) AS last_seen_at
    FROM device_daily dd
    JOIN devices d ON d.id = dd.device_id
    WHERE dd.stat_date = :day AND {VALID_DEVICE}
    GROUP BY 1
    """
)

_NEW_BY_BUILD_SQL = text(
    f"""
    SELECT COALESCE(dd.build, 'unknown') AS build, COUNT(*) AS new_devices
    FROM devices d
    JOIN device_daily dd ON dd.device_id = d.id AND dd.stat_date = :day
    WHERE d.created_at >= :start AND d.created_at < :end AND {VALID_DEVICE}
    GROUP BY 1
    """
)

_NEW_TOTAL_SQL = text(
    f"""
    SELECT COUNT(*) FROM devices d
    WHERE d.created_at >= :start AND d.created_at < :end AND {VALID_DEVICE}
    """
)


_APPROX_SQL = text(
    f"""
    INSERT INTO device_daily
        (device_id, stat_date, first_seen_at, last_seen_at, register_count, app_version, build)
    SELECT d.id, :day, d.last_seen_at, d.last_seen_at, 1, d.app_version, d.build
    FROM devices d
    WHERE d.last_seen_at >= :start AND d.last_seen_at < :end AND {VALID_DEVICE}
    ON CONFLICT(device_id, stat_date) DO NOTHING
    """
)


def approx_backfill(day: str) -> int:
    """上线前的历史只能近似：用 devices.last_seen_at 补一行（次数记 1）。

    只补当天没有行的设备，不会覆盖真实数据；返回新增行数。
    """
    start, end = day_window(day)
    db = SessionLocal()
    try:
        result = db.execute(_APPROX_SQL, {"day": day, "start": start, "end": end})
        db.commit()
        return result.rowcount or 0
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def date_cst(iso: str) -> str:
    """UTC ISO8601（带 Z）→ Asia/Shanghai 的 YYYY-MM-DD。"""
    dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return dt.astimezone(CST).date().isoformat()


def day_window(day: str) -> tuple[str, str]:
    """返回该 CST 日期的 [start, end) UTC ISO8601 边界。"""
    d = date.fromisoformat(day)
    start = datetime(d.year, d.month, d.day, tzinfo=CST).astimezone(timezone.utc)
    end = datetime(d.year, d.month, d.day, tzinfo=CST) + timedelta(days=1)
    end = end.astimezone(timezone.utc)
    fmt = "%Y-%m-%dT%H:%M:%SZ"
    return start.strftime(fmt), end.strftime(fmt)


def generate(day: str, session=None) -> list[dict]:
    """重算某天汇总并覆盖写入；返回写入的行。session 仅用于测试隔离。"""
    start, end = day_window(day)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    db = session or SessionLocal()
    try:
        active_rows = db.execute(_ACTIVE_SQL, {"day": day}).mappings().all()
        new_rows = {
            r["build"]: r["new_devices"]
            for r in db.execute(_NEW_BY_BUILD_SQL, {"day": day, "start": start, "end": end}).mappings()
        }
        new_total = db.execute(_NEW_TOTAL_SQL, {"start": start, "end": end}).scalar_one()

        rows: list[dict] = []
        builds: set[str] = {r["build"] for r in active_rows} | set(new_rows)
        for build in sorted(builds):
            act = next((r for r in active_rows if r["build"] == build), None)
            rows.append(
                {
                    "stat_date": day,
                    "build": build,
                    "new_devices": int(new_rows.get(build, 0)),
                    "active_devices": int(act["active_devices"]) if act else 0,
                    "first_seen_at": act["first_seen_at"] if act else None,
                    "last_seen_at": act["last_seen_at"] if act else None,
                    "generated_at": now_iso,
                }
            )

        firsts = [r["first_seen_at"] for r in active_rows if r["first_seen_at"]]
        lasts = [r["last_seen_at"] for r in active_rows if r["last_seen_at"]]
        rows.append(
            {
                "stat_date": day,
                "build": "*",
                "new_devices": int(new_total),
                "active_devices": sum(r["active_devices"] for r in rows),
                "first_seen_at": min(firsts) if firsts else None,
                "last_seen_at": max(lasts) if lasts else None,
                "generated_at": now_iso,
            }
        )

        for row in rows:
            db.execute(_UPSERT_SQL, row)
        db.commit()
        return rows
    except Exception:
        db.rollback()
        raise
    finally:
        if session is None:
            db.close()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="生成每日用户统计（默认昨天，CST）")
    parser.add_argument("day", nargs="?", help="YYYY-MM-DD，默认昨天")
    parser.add_argument("--date", dest="day_opt", help="同上")
    parser.add_argument("--days", type=int, default=1, help="从指定日期起往前算 N 天（默认 1）")
    parser.add_argument(
        "--approx-backfill",
        action="store_true",
        help="先用 devices.last_seen_at 近似补历史（仅缺行的设备，次数记 1）",
    )
    args = parser.parse_args(argv)

    target = args.day_opt or args.day
    if target:
        base = date.fromisoformat(target)
    else:
        base = (datetime.now(CST).date() - timedelta(days=1))

    days = [base - timedelta(days=i) for i in range(max(args.days, 1))]
    for d in reversed(days):
        if args.approx_backfill:
            added = approx_backfill(d.isoformat())
            if added:
                print(f"{d} approx-backfill rows={added}")
        rows = generate(d.isoformat())
        total = next(r for r in rows if r["build"] == "*")
        print(
            f"{d} active={total['active_devices']} new={total['new_devices']} "
            f"builds={len(rows) - 1} first={total['first_seen_at']} last={total['last_seen_at']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
