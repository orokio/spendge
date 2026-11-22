# 服务端设计

> 状态：v0.2 草案（2026-11-22）· 模型方案待定
> 部署：腾讯云 2C2G 单机 · nginx + gunicorn + Flask + SQLite + Redis
> 原则：客户端本地优先，服务端只做客户端做不了的事

## 1. 定位与边界

服务端负责四件事：

1. **账号**：匿名可用，会员功能前完成注册
2. **权益**：StoreKit 订阅校验与额度计数
3. **解析代理**：模型密钥只在服务端，客户端不接触（方案待定）
4. **运营支撑**：业务事件、诊断包接收（崩溃与埋点主要靠 SDK）

不做：

- 不存账单与账单内容。账本在本地 SwiftData，同步走 CloudKit
- 不存解析原文、图片；只留 request id、耗时、token 数、结果状态
- 不做通用 AI 对话
- 不做自建崩溃/埋点平台

## 2. 账号

### 状态机

```
匿名（anonymous） --绑定 Apple ID--> 已注册（registered）
     |                                  |
     +----------- 删除账号 <------------+
```

- 首次启动：`POST /v1/accounts/anonymous` 发放 `account_id` + 长期 token，客户端存 **Keychain**
- 匿名账号可改昵称（默认「海绵用户 8f3a」），可正常使用全部免费功能
- 注册不是新建账号，而是给同一个 `account_id` 绑定登录方式，额度与权益不迁移
- 换机或 Keychain 丢失：用 Sign in with Apple 登录，恢复到已绑定的账号；本地匿名账号作废，由清理任务回收

### 登录方式（方案 A：无密码）

- 主登录：**Sign in with Apple**，客户端传 `identityToken`，服务端校验 Apple 公钥与 nonce
- 不设密码，因此没有「忘记密码 / 验证码」流程
- 邮箱只作为可选联系方式（收据、通知），不做登录凭据
- 不做短信验证码：成本与到达率都不划算
- 不做实名认证；生成式 AI 若触发额外要求，等模型方案确定后单独评估

### Token

- 访问 token：随机 256 位，服务端只存哈希，有效期 7 天
- 刷新 token：有效期 90 天，刷新时轮换，旧 token 立即作废
- 设备绑定：token 与 `device_id`（App Attest key 哈希）关联，换设备需重新登录
- 所有接口用 `Authorization: Bearer <token>`

### 账号删除（上架硬要求）

- App 内提供入口，二次确认，写清三件事：会员剩余时长如何处理、iCloud 数据不受影响、App Store 订阅需另行取消
- 服务端：撤销全部 token、软删账号、清除身份绑定；财务流水保留去标识化的交易记录
- 删除后本地数据仍在本机，由用户决定是否清空

## 3. 会员与 StoreKit

- 权益唯一来源：**App Store**，服务端不处理支付
- 购买时客户端设置 `appAccountToken = account_id`
- 服务端接 App Store Server API 与 **Server Notifications V2**，写入 `entitlements`
- 恢复购买：按 `original_transaction_id` 找回并重新绑定账号
- 权益判断只看 `expires_at`，不看客户端上报
- 账号删除不退还已购时长；订阅由用户在 App Store 管理

## 4. 与 iCloud 的分工

| | 归属 | 说明 |
|---|---|---|
| 账单、目标、预算 | iCloud（CloudKit） | 跟 Apple ID 走，换设备自动同步 |
| 账号、昵称、会员、额度 | 自有服务端 | 跟 App 账号走 |

设置页分成「账号」与「iCloud」两张卡，文案明确：登录账号不会同步账单。避免用户误以为登录即同步。

## 5. 接口（v1）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/accounts/anonymous` | 发放匿名账号与 token |
| PATCH | `/v1/accounts/me` | 改昵称 |
| POST | `/v1/accounts/bind/apple` | 绑定 Apple ID，完成注册 |
| POST | `/v1/accounts/signin/apple` | 已有账号登录（换机恢复） |
| DELETE | `/v1/accounts/me` | 删除账号 |
| POST | `/v1/sessions/refresh` | 轮换 token |
| GET | `/v1/me` | 账号状态、权益、剩余额度 |
| POST | `/v1/parse` | 解析代理（模型待定） |
| POST | `/v1/appstore/notifications` | App Store 服务端通知 |
| POST | `/v1/events` | 业务事件批量上报（可选） |
| GET | `/health` | 健康检查 |

### /v1/parse 契约（不随模型变）

```json
POST /v1/parse        multipart：text 或 image（二选一）+ clientRequestId
200 {
  "draft": {
    "amountCents": 2800, "kind": "expense", "categoryCode": "dineout",
    "date": "2026-11-22", "note": "楼下面馆", "confidence": 0.86
  },
  "quota": { "remaining": 17, "limit": 20 },
  "modelVersion": "2026-11-22.1"
}
```

- `clientRequestId` 必填，用于幂等：重试不重复扣额度
- 图片走 multipart，客户端先压到长边 1024 / JPEG 0.7，服务端硬限 2MB
- 上游模型与 prompt 版本都写进响应，便于回溯
- 错误返回稳定错误码与中文文案，不透传上游报错

### 错误码

| HTTP | code | 含义 |
|---|---|---|
| 401 | `unauthenticated` | token 缺失、过期或设备不匹配 |
| 403 | `attest_failed` | App Attest 校验失败 |
| 409 | `already_bound` | 该 Apple ID 已绑定其他账号 |
| 429 | `quota_exhausted` | 额度用尽（带 `retryAfter`） |
| 429 | `rate_limited` | 请求过频 |
| 503 | `upstream_unavailable` | 模型暂不可用，可回退本地规则 |

## 6. 数据模型（SQLite）

单文件数据库，路径 `/var/lib/spendge/spendge.db`，WAL 模式。选它的理由只有一个：2C2G 的机器上，省下的 200–400M 常驻内存比并发写能力更值钱。

```sql
accounts            id TEXT PK, display_name TEXT, status TEXT,
                    registered_at TEXT, created_at TEXT
account_identities  id TEXT PK, account_id TEXT, provider TEXT,
                    identifier_hash TEXT, created_at TEXT,
                    UNIQUE(provider, identifier_hash)
devices             id TEXT PK, account_id TEXT, attest_key_hash TEXT,
                    last_seen_at TEXT
sessions            token_hash TEXT PK, account_id TEXT, device_id TEXT,
                    expires_at TEXT, created_at TEXT
entitlements        id TEXT PK, account_id TEXT,
                    original_transaction_id TEXT UNIQUE, product_id TEXT,
                    expires_at TEXT, status TEXT, updated_at TEXT
usage               id INTEGER PK AUTOINCREMENT, account_id TEXT, device_id TEXT,
                    idempotency_key TEXT UNIQUE, kind TEXT, tokens INTEGER,
                    result TEXT, created_at TEXT
events              id INTEGER PK AUTOINCREMENT, account_id TEXT,
                    name TEXT, props TEXT, created_at TEXT
```

类型约定：

- UUID 存 TEXT（小写带连字符），不用 BLOB，排查时直接能读
- 时间统一 UTC ISO-8601 TEXT（`2026-11-22T09:30:00.000Z`），字典序即时间序
- 布尔用 INTEGER 0/1；JSON 用 TEXT 存 `json.dumps(ensure_ascii=False)` 的结果
- 不写 SQLite 特有语法（不用 `INSERT OR IGNORE`，用标准 upsert 或先查后写），为以后迁移留路

### 连接与写入纪律

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;
PRAGMA cache_size = -8192;
```

- 每进程一条连接，`check_same_thread=False`；SQLAlchemy 用 `NullPool` 或很小的池
- **写事务必须短，事务里不能包模型调用**：解析走「预占额度（短事务）→ 提交 → 调模型 → 写结果（短事务）」
- 写路径用 `BEGIN IMMEDIATE`，避免 WAL 下读事务升级为写事务时死锁
- 单写者是 SQLite 的硬约束，宁可排队也不放宽

### 索引

- `usage(account_id, created_at)`：额度统计
- `sessions(account_id)`：踢出全部设备
- `events(created_at)`：按天归档与清理
- `entitlements(account_id, expires_at)`：权益查询

### 备份

- 每天 `sqlite3 <db> ".backup <目标>"` 压缩后上传 COS，保留 30 天
- **禁止直接 `cp` 数据库文件**：写入过程中复制会拿到不一致的页
- 每季度恢复演练一次，核对账号数与权益截止时间

### 约定

- 不存账单、备注原文、图片
- `usage` 的唯一键是幂等的最终保障，Redis 只是前置
- 保留周期：events 180 天、usage 24 个月；删除账号后身份绑定立即清除
- 数据访问统一走 SQLAlchemy + Repository，业务层不写裸 SQL；迁移用 Alembic

## 7. 架构与防护分层

**Redis 不是盾牌。** 防攻击靠分层，Redis 只承担计数与缓存，让重复请求不落到数据库。

```
用户
  │
  ├─ nginx       TLS、limit_req / limit_conn、请求体上限、超时、WAF
  │
  ├─ gunicorn    2–4 worker × 4 threads
  │     │
  │     ├─ 应用层：App Attest、token 鉴权、按账号限流、幂等
  │     ├─ Redis：滑动窗口计数、幂等键、热点缓存（内网、带密码、不暴露公网）
  │     └─ SQLite：单文件、WAL、单写者；写事务必须短
```

四道闸门：

1. **边缘**（nginx / 腾讯云 WAF）：按 IP 限速与并发，挡脚本和重放；L4 靠腾讯云基础防护
2. **身份**（App Attest + token）：未通过校验的请求不进业务逻辑，DB 完全不接触
3. **限流与幂等**（Redis）：按 device / account 的窗口计数、`SETNX` 幂等键；Redis 不可用时**非付费路径降级为放行**，付费与额度路径**失败即拒绝**
4. **数据库**（SQLite）：WAL 下读不阻塞写，写串行；`busy_timeout` 5 秒，写事务不跨模型调用；所有查询走索引，禁止无界 `SELECT`

参数起步值：

- nginx：`10r/s` per IP，burst 30；`limit_conn` 20
- 应用：匿名 20 次/分/设备；已注册 60 次/分/账号
- 解析：免费额度按设备计，付费按账号计，额度检查在 Redis，落库以 `usage` 唯一键兜底

选型说明：SQLite 适合单机、低并发写；迁移触发条件见 §11。以后需要独立数据库服务时，目标是 MariaDB（比 MySQL 8 轻 100–150M、协议兼容），不是 MySQL 8。表不建外键约束，关系与唯一性由应用层和唯一索引保证，迁移时不碍事；连接时仍保留 `PRAGMA foreign_keys=ON`，以后补约束时行为一致。

## 8. 可观测性

- **崩溃**：Bugly（免费、国内可用），符号表在构建期上传
- **埋点**：友盟+（或腾讯云移动分析）；事件名与属性在客户端统一定义，服务端只收汇总
- **客户端日志**：本地环形缓冲，用户主动反馈时上传诊断包
- **服务端日志**：结构化 JSON，字段含 request_id、account_id（哈希）、路径、状态码、耗时、token 数；不打印请求原文
- **业务事件**（`/v1/events`）：解析成功率、额度耗尽、订阅转化；批量、采样、无 PII
- **告警**：解析错误率、P95 延迟、上游失败率、日成本超阈值

## 9. 合规与上架

- App 内账号删除（Apple 5.1.1(v)）
- 隐私政策写明：数据去向、保留周期、第三方 SDK 清单与用途
- 中国区：域名 ICP 备案、App 备案
- 生成式 AI 功能是否要求真实身份认证，待模型方案确定后与合规确认；数据不落库是降低风险的关键
- 模型若涉及境外调用，需评估数据出境；当前方向为境内模型

## 10. 实施顺序

1. 账号：匿名发放、token、改名、绑定 Apple、删除
2. SQLite 表与 Alembic 迁移；Redis 计数与幂等
3. StoreKit 通知与权益
4. 解析代理（模型确定后）：mock provider → 真实 provider → 金句集评估
5. 业务事件与告警
6. 压测与限流调参

## 11. 部署形态（2C2G 单机）

所有组件同机，不买托管数据库：

```
nginx → gunicorn（2 worker × 4 线程）→ Flask
                         ├─ SQLite 文件 /var/lib/spendge/spendge.db
                         └─ Redis（127.0.0.1:6379）
```

内存预算：

| 组件 | 预计常驻 |
|---|---|
| 系统（Ubuntu 24.04） | 250–350M |
| nginx | 15M |
| gunicorn 2×4 | 180–220M |
| SQLite | 进程内，页缓存几十 MB |
| Redis（maxmemory 128M） | 60M |
| 合计 | 约 0.6–0.7G |

前提是已用的约 1G 能查清并释放；否则先升 4G 再上。

### Redis

```conf
bind 127.0.0.1
protected-mode yes
requirepass <随机长密码>
maxmemory 128mb
maxmemory-policy volatile-lru
save ""
appendonly no
```

只存限流计数与幂等键，重启丢失不影响正确性（`usage` 唯一键兜底）；所有键必须带 TTL。禁用 `FLUSHALL` / `CONFIG` / `KEYS`。

### gunicorn

```bash
gunicorn -w 2 --threads 4 -b 127.0.0.1:8010 \
  --timeout 90 --max-requests 800 --max-requests-jitter 100 \
  app.main:app
```

### 系统

- `vm.swappiness=10`
- journald `SystemMaxUse=200M`
- gunicorn 的 systemd 单元加 `MemoryMax=700M`
- 安全组只开 22 / 80 / 443；Redis 与 SQLite 都不对外

### 监控与升级触发

- 监控：内存 >85%、swap 占用 >300M、磁盘 >80%、gunicorn 5xx、解析 P95
- 升到 4G：swap 持续占用、出现 OOM kill、部署时接口明显抖动
- 迁到 MariaDB：需要多实例部署、写事务排队明显、需要慢查询日志或主从

## 12. 未决

- 模型供应商（境内，具体待定）与金句集
- 埋点最终选型（友盟+ / 腾讯云移动分析）
- 免费额度具体数值与试用策略
- 是否需要在注册后强制填写邮箱
