# 用户统计口径（与 App Store Connect 对照）

面向服务端的实现规格。目标是**能回答「装了这个 App 的人有没有真的在用」**，不是做完整的分析平台。所有口径以注册接口上报的 `devices` 表为准；下载量与收入以 App Store Connect 为准。

## 1. 数据来源

现有 `devices` 表（`server/app/models.py`）：

| 字段 | 含义 |
|---|---|
| `id` | 客户端 deviceId，大写 UUID 字符串 |
| `secret_hash` | deviceSecret 的哈希；客户端首次登记起一直带 |
| `app_version` | CFBundleShortVersionString，如 `1.0` |
| `build` | CFBundleVersion，如 `8` |
| `platform` | `ios` |
| `created_at` | 首次登记时间，UTC ISO8601 |
| `last_seen_at` | 最后一次登记时间，UTC ISO8601 |

缺口：这张表只有「首次」和「最后」，算不出某一天的首次/最后、也算不出启动次数。所以需要新增一张按天的聚合表。

## 2. 新增表

### 2.1 device_daily（明细聚合）

```sql
CREATE TABLE device_daily (
    device_id      TEXT    NOT NULL,
    stat_date      TEXT    NOT NULL,   -- 按 Asia/Shanghai 切出的日期，YYYY-MM-DD
    first_seen_at  TEXT    NOT NULL,   -- UTC ISO8601，取当天最早
    last_seen_at   TEXT    NOT NULL,   -- UTC ISO8601，取当天最晚
    register_count INTEGER NOT NULL DEFAULT 0,  -- 当天 register 次数
    app_version    TEXT,               -- 当天最后一次上报的版本
    build          TEXT,
    PRIMARY KEY (device_id, stat_date)
);
CREATE INDEX idx_device_daily_date ON device_daily(stat_date);
```

写入时机：每次 `register` 成功后 upsert 一条（与 `devices` 同事务）：

- `first_seen_at` = min(已有值, 本次)
- `last_seen_at` = max(已有值, 本次)
- `register_count` += 1
- `app_version` / `build` = 本次上报值（覆盖）

幂等：重复或乱序上报都不会写坏 —— 取 min/max，而不是直接赋值。

### 2.2 user_stats_daily（每日汇总）

```sql
CREATE TABLE user_stats_daily (
    stat_date       TEXT    NOT NULL,
    build           TEXT    NOT NULL,  -- '*' 表示全部 build，即对账口径
    new_devices     INTEGER NOT NULL,
    active_devices  INTEGER NOT NULL,
    first_seen_at   TEXT,              -- 当天最早的登记时间
    last_seen_at    TEXT,              -- 当天最晚的登记时间
    generated_at    TEXT NOT NULL,
    PRIMARY KEY (stat_date, build)
);
```

每天跑一次（建议 CST 00:10 跑前一天），重跑覆盖。

## 3. 合法设备

统计只算真实客户端上报的记录：

```sql
length(d.id) = 36
AND d.id = upper(d.id)          -- 客户端只生成大写 UUID
AND d.secret_hash <> ''         -- register 必须带 secret，库里不应该是空
```

理由：deviceId 是 `UUID().uuidString`，构造测试数据的人往往用小写或短串；`secret_hash` 非空说明走过完整的登记流程。腾讯云上的 curl 自测、`11111111` 这类会被排除。

不要用 build 白名单判断「合法性」—— build 只决定版本分布，不能决定真假。

## 4. 口径

### 4.1 活跃设备

「当天至少成功 register 过一次」。

```sql
SELECT COUNT(*) FROM device_daily
WHERE stat_date = :day AND device_id IN (合法设备);
```

### 4.2 新增设备

「第一次被看到的日期 = 当天」。

```sql
SELECT COUNT(*) FROM devices d
WHERE 合法设备 AND date_cst(d.created_at) = :day;
```

这是精确值，不依赖 device_daily 是否已经积累历史。

### 4.3 版本分布

```sql
SELECT build, COUNT(*) FROM device_daily
WHERE stat_date = :day AND device_id IN (合法设备)
GROUP BY build;
```

按设备当天最后一次上报的 build 归类。

### 4.4 当天首次 / 最后

```sql
SELECT MIN(first_seen_at), MAX(last_seen_at) FROM device_daily
WHERE stat_date = :day AND device_id IN (合法设备);
```

### 4.5 启动次数

`register_count` 是「启动次数」的近似：客户端每次冷启动都会 register 一次。后台唤醒、静默推送不触发 register，所以它偏低，只用于看相对变化。

## 5. 时区

- **存储一律 UTC**，沿用现有 `YYYY-MM-DDTHH:MM:SSZ` 格式
- **切日一律按 `Asia/Shanghai`**，不要用 UTC 日期，也不要用服务器本地时区

Python 里的标准写法：

```python
from datetime import datetime
from zoneinfo import ZoneInfo

CST = ZoneInfo("Asia/Shanghai")

def date_cst(iso: str) -> str:
    dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return dt.astimezone(CST).date().isoformat()
```

SQL 里临时排查可以用：

```sql
date(datetime(replace(substr(last_seen_at, 1, 19), 'T', ' '), '+8 hours'))
```

但**定时任务请用 Python 计算**：SQLite 的 `datetime()` 对带 `Z` 的字符串在不同版本行为不一致，`substr` 截断的做法也会在格式变化时静默出错。

## 6. 与 App Store Connect 对照

2026-11-27 起 App 改为付费下载，客户端移除了友盟统计，数据的权威来源换成 **App Store Connect**。

| 指标 | ASC | 我们的口径 | 说明 |
|---|---|---|---|
| 下载量 / 销售额 | 权威，按天 | 无法得到 | 财务与获客只看 ASC |
| 日活设备 | 不提供 | 当天成功 register 的设备 | 内部趋势参考 |
| 新增设备 | 不提供 | 当天首次登记成功 | 内部趋势参考 |

唯一有意义的派生指标是 **register / 下载 的比例**：下载了但从不打开、或打开后没走完登记的，会体现为这个比例偏低。它反映首启转化，而不是产品质量。

偏差来源，按影响从大到小：

1. **网络**：register 失败（断网、服务端 5xx）就漏统计
2. **隐私门禁**：用户未同意隐私政策前不上报
3. **重装**：deviceId 存 Keychain，重装不变；**抹机重装**会算成新设备
4. **时区**：按 `Asia/Shanghai` 切日，跨 0 点的请求有几分钟错位

用法：**下载与收入以 ASC 为准**，register 数据只用来观察留存与转化趋势，不和 ASC 做绝对值对账。

## 7. 边界情况

- **同一天多次启动**：只算一次活跃，`register_count` 累加
- **上报时间乱序 / 重放**：`first_seen_at` 取 min、`last_seen_at` 取 max，不受顺序影响
- **时间在未来**：register 时把未来时间夹到当前时间，避免统计到明天
- **缺少 app_version / build**：归到 `unknown`，不参与对账分子，但计入活跃
- **历史回填**：`device_daily` 上线前的日子只能用 `devices.last_seen_at` 近似（只知道最后一次，不知道当天首次和次数）。汇总表从上线当天开始算，历史行留空并在报表里标注
- **deviceId 复用 / 冲突**：`devices.id` 是主键不会重复；同一物理设备抹机重装会产生新 id，被算作新增

## 8. 验收

上线后拿昨天的数据人工核一遍：

1. `user_stats_daily` 里 `build = '*'` 的活跃数，应等于下面这条 SQL 的结果
2. 各 build 的活跃数加起来应等于活跃总数
3. 新增数 ≤ 活跃数（同一天不可能新增多于活跃）
4. 与 ASC 同一天的下载量对比，记录 register / 下载 的比例

```sql
SELECT COUNT(DISTINCT dd.device_id)
FROM device_daily dd JOIN devices d ON d.id = dd.device_id
WHERE dd.stat_date = :day
  AND length(d.id) = 36 AND d.id = upper(d.id) AND d.secret_hash <> '';
```
