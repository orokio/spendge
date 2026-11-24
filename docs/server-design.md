# 服务端设计

> 状态：v0.3（2026-11-24 复核）· 模型方案待定 · **服务端尚未开工；v1 上架不依赖服务端**，M4 解析上线前再启动，开发在云机器上进行
> 部署：见 [deploy-plan.md](deploy-plan.md)
> 原则：客户端本地优先，服务端只做客户端做不了的事；服务端可随时退场而不影响本地使用（见 §12）

## 0. 与当前产品状态的对齐（2026-11-24）

v1 上架线是「本地记账 + iCloud + Bugly + 最小埋点」，以下设计暂时用不上，开工时要先按现状调整：

| 章节 | 现状 | 开工前要做的调整 |
|---|---|---|
| §1 定位 | 账号、会员、解析、运营四件事，v1 一件都不做 | 把服务端定位收敛为「M4 解析 + 诊断接收」，账号与权益降为可选 |
| §2 身份与账号 | Sign in with Apple、deviceId/accountId 绑定 | **v1 只做 deviceId**：客户端生成并保存，accountId 字段预留但为空、不上传、不显示绑定入口；M4 有云端功能后，老用户升级 App 即可用现有 deviceId 回填关联 |
| §3 会员与 StoreKit | 按**订阅**设计（Server Notifications、expires_at 校验） | v1 是 **¥18 一次性买断**，客户端用 StoreKit 2 的 currentEntitlements 判定，服务端不参与；将来做订阅时再启用本节，届时 accountId 与 originalTransactionId 都要记 |
| §5 接口 | accounts / sessions / appstore 通知 | v1 只需要 `/health` 与 `/v1/devices/register`；解析上线时再加 `/v1/parse`、`/v1/diagnostics` |
| §9 合规 | 域名 ICP、App 备案 | App 备案已在办；域名 ICP 与 HTTPS 证书要等域名确定 |
| §11 未决 | 埋点选型、免费额度 | 已定：埋点用友盟、免费版 2 个目标 + 近 3 个月回看，这两条可关闭 |

仍未变的约定：不存账单与账单内容、不存解析原文与图片、服务端可随时退场不影响本地（§12），这几条继续有效。

### 身份与账号（沿用 2026-11-22 定稿）

- **deviceId**：客户端首次启动生成 UUID，存 Keychain，重装不丢；**v1 就做这一项**，纯本地使用只需要它
- **accountId**：我们自己的内部 ID，**服务端生成**；只有用户主动绑定账号（Sign in with Apple）时才创建。**iCloud 同步不需要登录**，同步用的是系统 iCloud 身份
- **表**：`accounts(accountId, appleSubject)`、`devices(deviceId, accountId?, firstSeen)`；一个 accountId 下可以关联多台设备
- **顺序（方案 B）**：先开 CloudKit 同步，账号关联稍后补；服务端不可用不阻塞同步，期间的日志只有 deviceId，恢复后按 deviceId 回填
- **日志**：上传时带 deviceId，已绑定账号再带 accountId；只存动作、结果、错误码、版本号
- **上架要求**：一旦存在账号，App 内必须能删除账号；v1 只做 CloudKit 同步、不提供绑定入口，所以没有账号，这条不适用；绑定入口随 M4 服务端上线，届时补删除入口

CloudKit 的 userRecordID 只在 Apple 容器内可见，服务端拿不到，所以**不用它做账号标识**；它最多作为设备侧日志的临时归组依据。

### v1 的实现范围与 M4 的接入方式

- v1 只生成并保存 deviceId；任何接口里的 accountId 字段都预留为空，不绑定、不显示入口
- M4 的云端功能上线后，老用户升级 App：服务端按 deviceId 回填，把历史数据与日志归到新建的 accountId 下，客户端不需要迁移
- 因此**客户端协议从一开始就带 accountId 字段（可空）**，避免 M4 改协议

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

## 2. 账号与标识

### 两层身份

| 标识 | 生成方 | 存储 | 用途 |
|---|---|---|---|
| deviceId | 客户端 UUID | Keychain | 本地使用、日志、设备级限流 |
| accountId | 服务端 UUID | 服务端数据库 | 跨设备账号、权益、日志归并 |

- 首次启动只生成 deviceId，不访问服务端
- 纯本地用户永远只有 deviceId，没有账号
- accountId 只在用户**主动绑定账号**（Sign in with Apple）时创建；iCloud 同步本身不需要登录，用系统 iCloud 身份即可

### 绑定流程（方案 B：同步优先，关联可补）

**开启 iCloud 同步时的交互**

```
用户点「开启 iCloud 同步」
   ├─ 立即开启 CloudKit 同步（不等任何登录，不访问我们）
   └─ 同一张卡片下方出现引导：
      「绑定账号，换手机也能找回额度」 [绑定] [以后再说]
```

- 绑定是可选项，**不是同步的前置条件**；不绑也能同步
- v1 没有服务端，不显示这个入口；服务端上线后再出现

**绑定时发生什么**

1. 用户点「绑定」→ Sign in with Apple → 服务端校验 identityToken，按 `apple_subject` 查找或创建 accountId，绑定当前 deviceId，返回账号 token
2. 第二台设备同样绑定 → 服务端认出同一 accountId，追加绑定它的 deviceId
3. 服务端不可用：不弹错误、不阻塞同步；记一个「待绑定」标记，服务端恢复后（下次启动或回前台）再发起一次 Sign in with Apple

**为什么不能先存凭证、稍后上传**：identityToken 有效期约 10 分钟，authorizationCode 一次性且更短，离线缓存到服务恢复时已经失效。所以缓存的是“想绑定”的意图，恢复后需要用户再点一次系统弹窗。

### 登录方式

- 只用 Sign in with Apple；不设密码、不做短信验证码
- 只保存 Apple 的稳定用户标识（`apple_subject`），不主动申请邮箱与姓名
- 不做实名认证

### Token

- 访问 token：随机 256 位，服务端只存哈希，有效期 7 天
- 刷新 token：有效期 90 天，刷新时轮换
- token 绑定 deviceId；换设备重新 Sign in with Apple

### 账号删除（上架硬要求）

- App 内提供入口，二次确认
- 服务端：撤销 token、解绑全部 deviceId、删除账号；保留去标识化的日志统计
- iCloud 账本由 Apple 保管，删除账号不影响 iCloud 数据，需在文案里写清
- 纯本地用户没有账号，不需要删除入口

## 3. 会员与 StoreKit（v1 不适用，保留设计）

> **2026-11-24 更新**：v1 是 ¥18 **一次性买断**，客户端用 StoreKit 2 的 `currentEntitlements` 判定（本人购买、家人共享、换机恢复都覆盖），**不需要服务端参与**。下面是“将来做订阅”时的设计，开工前先确认是否还需要。

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
| 账号、权益、额度、诊断日志 | 自有服务端 | 跟 accountId 走 |

同步本身由 CloudKit 完成，**不需要登录**；账号是在 iCloud 卡片下方通过可选引导绑定的（见 §2），不绑也能同步。设置页把「iCloud 同步」和「绑定账号」分开写，避免用户误以为登录才能同步账单。

## 5. 接口（v1）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/accounts/apple` | Sign in with Apple：创建/找回 accountId，绑定 deviceId，返回 token |
| POST | `/v1/devices/register` | **v1 就要实现**：登记 deviceId，用于 M4 回填账号与限流 |
| DELETE | `/v1/accounts/me` | 删除账号，解绑全部 deviceId |
| POST | `/v1/sessions/refresh` | 轮换 token |
| GET | `/v1/me` | 账号、已绑定设备、权益、额度 |
| POST | `/v1/diagnostics` | 诊断日志批量上报（无财务内容） |
| POST | `/v1/parse` | 解析代理（模型待定） |
| POST | `/v1/appstore/notifications` | App Store 服务端通知 |
| POST | `/v1/events` | 业务事件批量上报（可选） |
| GET | `/health` | 健康检查 |

### /v1/devices/register 契约（v1）

客户端在隐私同意后、启动时上报一次；成功打本地标记，失败下次启动重试，不打扰用户。

```json
POST /v1/devices/register
{
  "deviceId": "uuid",
  "appVersion": "1.0",
  "build": "2",
  "platform": "ios"
}
```

- 幂等：同一 deviceId 重复上报只更新 `last_seen`，不产生新行
- 只存 deviceId、首次/最后时间、App 版本；不存任何账单或内容
- 响应 200 即可，客户端不解析返回体
- 客户端未配置 ServerBaseURL 时不会发起请求

### /v1/diagnostics 契约

```json
POST /v1/diagnostics
{
  "deviceId": "uuid",
  "accountId": "uuid 或省略",
  "appVersion": "1.0 (12)",
  "events": [
    { "at": "2026-11-23T18:20:00Z", "name": "record_save", "result": "failed", "code": "amountTooLarge" }
  ]
}
200 { "accepted": 1 }
```

- 一次最多 200 条，单条只保留动作、结果、错误码、时间
- 不接收金额、备注、商户、图片或任何账本内容
- 保留 30 天，按 deviceId / accountId 归并，不用于广告
- 服务端不可用时客户端本地排队，下次启动重试

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

单文件数据库，WAL 模式；路径与权限由部署决定（见 [deploy-plan.md](deploy-plan.md)）。选它的理由只有一个：2C2G 的机器上，省下的 200–400M 常驻内存比并发写能力更值钱。

```sql
accounts            id TEXT PK,              -- server accountId
                    apple_subject TEXT UNIQUE,
                    created_at TEXT
devices             id TEXT PK,              -- client deviceId
                    account_id TEXT NULL,
                    created_at TEXT, last_seen_at TEXT
sessions            token_hash TEXT PK, account_id TEXT, device_id TEXT,
                    expires_at TEXT, created_at TEXT
entitlements        id TEXT PK, account_id TEXT,
                    original_transaction_id TEXT UNIQUE, product_id TEXT,
                    expires_at TEXT, status TEXT, updated_at TEXT
usage               id INTEGER PK AUTOINCREMENT, account_id TEXT NULL,
                    device_id TEXT, idempotency_key TEXT UNIQUE,
                    kind TEXT, tokens INTEGER, result TEXT, created_at TEXT
diagnostics         id INTEGER PK AUTOINCREMENT, device_id TEXT,
                    account_id TEXT NULL, app_version TEXT,
                    name TEXT, result TEXT, code TEXT, at TEXT, created_at TEXT
events              id INTEGER PK AUTOINCREMENT, account_id TEXT NULL,
                    device_id TEXT, name TEXT, props TEXT, created_at TEXT
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

具体命令、频率与恢复演练见 [deploy-plan.md](deploy-plan.md)。设计上只约束一条：**禁止直接 `cp` 正在使用的库文件**，必须走 SQLite 的备份接口。

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
  ├─ gunicorn    WSGI 应用服务器
  │     │
  │     ├─ 应用层：App Attest、token 鉴权、按账号限流、幂等
  │     ├─ Redis：滑动窗口计数、幂等键、热点缓存
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

选型说明：SQLite 适合单机、低并发写；迁移触发条件见 [deploy-plan.md](deploy-plan.md) 的「运行与升级触发」。以后需要独立数据库服务时，目标是 MariaDB（比 MySQL 8 轻 100–150M、协议兼容），不是 MySQL 8。表不建外键约束，关系与唯一性由应用层和唯一索引保证，迁移时不碍事；连接时仍保留 `PRAGMA foreign_keys=ON`，以后补约束时行为一致。

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

> **2026-11-24**：暂不排期。恢复时的顺序改为：解析代理 → 诊断接收 →（仅当做订阅）账号与权益；下面列表按旧的订阅方案保留。

1. 账号：匿名发放、token、改名、绑定 Apple、删除
2. SQLite 表与 Alembic 迁移；Redis 计数与幂等
3. StoreKit 通知与权益
4. 解析代理（模型确定后）：mock provider → 真实 provider → 金句集评估
5. 业务事件与告警
6. 压测与限流调参

## 11. 未决

- 模型供应商（境内，具体待定）与金句集
- ~~埋点最终选型~~ 已定：客户端友盟（2026-11-24）
- ~~免费额度~~ 已定：2 个目标 + 近 3 个月回看（2026-11-24）
- ~~注册后强制填写邮箱~~ v1 无账号，取消
- 主动退场的公告窗口、退款与导出话术，待法务/客服确认（机制见 §12）

## 12. 服务可用性与退场设计（离线优先 / Graceful Sunset）

> 本节是服务端契约与退场流程；客户端落地要求见 [architecture.md](architecture.md) 的「离线优先与鲁棒性」。

### 12.1 目标
- 服务端在任何时候不可用（事故或主动关停），App 的本地核心功能——记账、查看、统计、iCloud 同步——完全不受影响。
- 已购会员在服务停服后，仍按 App Store 记录享受剩余权益；主动关停时提供退出与退款指引。
- 服务端永远只是增强项，不是记账的前提。

### 12.2 依赖分级

| 功能 | 是否依赖服务端 | 服务端不可用时 |
|---|---|---|
| 本地记账 / 账单 / 目标 / 预算 | 否（本地 SwiftData） | 完全可用 |
| iCloud 多设备同步 | 否（CloudKit） | 完全可用 |
| 匿名账号与 token | 一次性 | 不新建；纯本地使用无需账号 |
| 登录 / 绑定 / 刷新 token | 软依赖 | 降级游客态，不影响本地 |
| 会员权益校验 | 软依赖（App Store 为准） | 用本地缓存 + StoreKit 本地校验 |
| 解析代理 /v1/parse | 硬依赖 | 降级本地规则 / 手动录入 |
| StoreKit 通知与权益同步 | 是 | 客户端直接读 StoreKit 本地交易 |
| 业务事件 / 埋点 | 否 | 静默失败，不阻塞 |

### 12.3 客户端降级原则
- 所有服务端调用异步、带超时、可失败，绝不阻塞 UI 与记账主流程。
- 解析不可用：自动降级到本地规则或手动录入，提示「暂用本地识别」，不报错阻断。
- 鉴权失败（401 / 超时）：按离线处理，游客态继续；恢复后补同步。
- 权益：本地缓存 entitlements（含 expires_at），离线以缓存 + StoreKit 本地为准，恢复后校正。
- 重试与幂等：解析与事件入本地队列，恢复后重放，靠 usage.idempotency_key 不重复扣额度。

### 12.4 会员权益保障（重点）
- 权益唯一来源是 App Store：已购记录在 Apple 侧，不依赖我们服务端存续。
- 客户端订阅 StoreKit2 交易更新，本地即可判权；服务端仅做跨设备与防作弊的辅助校验。
- 事故停服：已购用户按 expires_at 继续可用，恢复后同步，不因故障损失时长。
- 主动关停：至少提前 90 天公告；期间停止新订阅入口，对未到期用户给出退款指引（订阅退款由用户向 Apple 申请，我们提供说明与协助），并提供一次性数据导出。
- 明确不把「服务在线」作为会员功能可用的前提。

### 12.5 主动退场流程（Sunset Plan）
1. 公告期（≥90 天）：App 内公告、商店页面说明、停止新订阅、推送/邮件通知。
2. 只读期：保留鉴权、权益查询与数据导出，停掉解析与写接口。
3. 导出期：开放导出与账号删除。
4. 下线：关闭服务；客户端自动进入纯本地模式，无需更新即可继续记账。
- 每阶段配套客服与退款话术。

### 12.6 事故场景（被动不可用）
- 目标用户无感：解析降级，其余本地照常。
- 状态页与监控告警；恢复后自动补同步；本地数据不因事故丢失（数据本就在本地）。
- 客户端对 5xx / 超时统一降级，不弹阻断式错误。

### 12.7 契约与实现约束
- 记账主流程不得出现「必须联网」或「必须登录」。
- 每个服务端接口都要在契约里写明降级分支，客户端必须实现。
- API 版本化（/v1），服务下线或变更时老客户端不得崩溃。
- 服务端不存账单正文与解析原文（见 §1、§6），从根上降低停服影响。
- 权益与额度在线以服务端为准、离线以本地 + StoreKit 为准；冲突时优先不损害已购权益。

### 12.8 验收清单
- [ ] 断网 / 服务端全挂时，App 可正常记账、查看、统计、iCloud 同步
- [ ] 解析不可用时降级本地/手动，不阻塞
- [ ] 服务端不可达时已购会员仍可用（本地权益缓存 / StoreKit）
- [ ] token 过期或 401 进入游客态，不阻断本地
- [ ] 主动关停演练：公告 → 只读 → 导出 → 下线，客户端纯本地可用
- [ ] 服务恢复后自动补同步且幂等，不重复扣额度

