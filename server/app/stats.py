"""用户统计：按天汇总 device_daily → user_stats_daily（口径见 docs/user-stats-spec.md）。

定时任务用 Python 计算日期（Asia/Shanghai），不依赖 SQLite 的 datetime() 处理带 Z 的字符串。
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import text

from app.db import SessionLocal

CST = ZoneInfo("Asia/Shanghai")
REPORT_DIR = os.getenv("STATS_REPORT_DIR", "/home/ubuntu/stats")

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


_LAUNCH_SQL = text(
    f"""
    SELECT COALESCE(dd.build, 'unknown') AS build, SUM(dd.register_count) AS launches
    FROM device_daily dd
    JOIN devices d ON d.id = dd.device_id
    WHERE dd.stat_date = :day AND {VALID_DEVICE}
    GROUP BY 1
    """
)


def _launches(day: str, session=None) -> dict[str, int]:
    db = session or SessionLocal()
    try:
        return {
            r["build"]: int(r["launches"] or 0)
            for r in db.execute(_LAUNCH_SQL, {"day": day}).mappings()
        }
    finally:
        if session is None:
            db.close()


def render_report(day: str, session=None) -> str:
    """生成一天的可读报告（含当日明细 + 近 7 天趋势）。"""
    db = session or SessionLocal()
    try:
        rows = db.execute(
            text(
                "SELECT build, new_devices, active_devices, first_seen_at, last_seen_at "
                "FROM user_stats_daily WHERE stat_date = :day "
                "ORDER BY CASE WHEN build = '*' THEN 0 ELSE 1 END, build"
            ),
            {"day": day},
        ).mappings().all()
        trend = db.execute(
            text(
                "SELECT stat_date, active_devices, new_devices FROM user_stats_daily "
                "WHERE build = '*' AND stat_date <= :day ORDER BY stat_date DESC LIMIT 7"
            ),
            {"day": day},
        ).mappings().all()
        total = next((r for r in rows if r["build"] == "*"), None)
        builds = [r for r in rows if r["build"] != "*"]
        launches = _launches(day, session)
        launches_total = sum(launches.values())
        gen = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        lines = [
            "spendge 用户统计",
            f"统计日期: {day}（Asia/Shanghai）",
            f"生成时间: {gen}",
            "",
            f"活跃设备: {total['active_devices'] if total else 0}",
            f"新增设备: {total['new_devices'] if total else 0}",
            f"启动次数: {launches_total}   # register 次数近似，偏低",
        ]
        if total and total["first_seen_at"]:
            lines.append(f"当天首次: {total['first_seen_at']}")
            lines.append(f"当天最后: {total['last_seen_at']}")
        lines += ["", "版本分布:", "  build      活跃   新增   启动"]
        for b in sorted(builds, key=lambda x: (x["build"] == "unknown", x["build"])):
            lines.append(
                f"  {b['build']:<10} {b['active_devices']:>4}   {b['new_devices']:>4}   "
                f"{launches.get(b['build'], 0):>4}"
            )
        lines += ["", "近 7 天:", "  日期          活跃   新增"]
        for t in trend:
            lines.append(f"  {t['stat_date']}   {t['active_devices']:>4}   {t['new_devices']:>4}")
        lines.append("")
        return "\n".join(lines)
    finally:
        if session is None:
            db.close()


def write_report(day: str, session=None) -> tuple[str, str]:
    """写 report-YYYY-MM-DD.txt + latest.txt + daily.csv（按日期覆盖行）。"""
    os.makedirs(REPORT_DIR, exist_ok=True)
    report = render_report(day, session)

    path = os.path.join(REPORT_DIR, f"report-{day}.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(report)
    with open(os.path.join(REPORT_DIR, "latest.txt"), "w", encoding="utf-8") as fh:
        fh.write(report)

    db = session or SessionLocal()
    try:
        total = db.execute(
            text("SELECT new_devices, active_devices FROM user_stats_daily WHERE stat_date=:d AND build='*'"),
            {"d": day},
        ).mappings().first()
        launches = sum(_launches(day, session).values())
        row = [day, total["active_devices"] if total else 0, total["new_devices"] if total else 0, launches]
    finally:
        if session is None:
            db.close()

    csv_path = os.path.join(REPORT_DIR, "daily.csv")
    existing: dict[str, list[str]] = {}
    if os.path.exists(csv_path):
        with open(csv_path, encoding="utf-8") as fh:
            for r in csv.reader(fh):
                if r and r[0] != "date":
                    existing[r[0]] = r
    existing[day] = [str(v) for v in row]
    with open(csv_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["date", "active_devices", "new_devices", "launches"])
        for d in sorted(existing):
            w.writerow(existing[d])
    return path, report


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="生成每日用户统计（默认昨天，CST）")
    parser.add_argument("day", nargs="?", help="YYYY-MM-DD，默认昨天")
    parser.add_argument("--date", dest="day_opt", help="同上")
    parser.add_argument("--days", type=int, default=1, help="从指定日期起往前算 N 天（默认 1）")
    parser.add_argument("--no-report", action="store_true", help="只算库，不生成文本报告")
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
        if not args.no_report:
            path, _ = write_report(d.isoformat())
            print(f"  report -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
