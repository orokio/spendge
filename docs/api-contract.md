# 接口协议（客户端 ↔ 服务端）

> 唯一契约来源。服务端实现、客户端调用、联调与压测都以本文为准。
> 版本：v1 · 2026-11-24 · 变更记录见文末
> 背景与部署见 [server-design.md](server-design.md)、[deploy-plan.md](deploy-plan.md)

## 1. 通用约定

| 项 | 约定 |
|---|---|
| Base URL | 客户端读 `Info.plist` 的 `ServerBaseURL`；为空则不发任何请求。**当前联调环境：`https://www.orokio.com:8443`**（备案通过后切 443） |
| 协议 | 仅 HTTPS，不做 ATS 例外 |
| 编码 | `application/json; charset=utf-8` |
| 时间 | ISO 8601，UTC，例如 `2027-02-24T00:00:00Z` |
| 版本 | 路径前缀 `/v1`；未知字段必须忽略 |
| 幂等 | 所有写接口按业务键幂等，重复请求不产生重复数据 |

## 2. 鉴权

### 设备凭证

| 名称 | 生成方 | 存储 | 说明 |
|---|---|---|---|
| `deviceId` | 客户端（UUID） | Keychain | 设备标识，重装不丢 |
| `deviceSecret` | 客户端（32 字节随机） | Keychain | 设备密钥，服务端只存哈希 |
| `deviceToken` | 服务端签发（opaque） | 客户端 Keychain | 会话凭证，3 个月滑动续期 |

- `register` 是唯一的无 Bearer 接口，但**必须带 deviceSecret**
- 其他接口：`Authorization: Bearer <deviceToken>`
- 仅知道 `deviceId` 不能拿到 token；`deviceSecret` 不匹配返回 401/403
- token 只存哈希，可随时吊销；吊销后客户端下次 register 自动重签

### 客户端行为

1. 用户同意隐私政策前，不发任何请求
2. 每次启动调用一次 `register`；已有 token 时同时带 `Authorization` 用于续期
3. 收到 401 `token_invalid`：带 deviceSecret 重新 register 一次，再重试原请求一次
4. 网络失败静默处理，不打扰用户，下次启动重试

## 3. 错误结构

```json
{ "code": "token_invalid", "message": "凭证已失效" }
```

| HTTP | code | 含义 | 客户端处理 |
|---|---|---|---|
| 400 | `invalid_request` | 参数缺失或格式错误 | 不重试，记录日志 |
| 401 | `token_invalid` | token 缺失、过期或已吊销 | 重注册后重试一次 |
| 403 | `secret_mismatch` | deviceSecret 不匹配 | 不重试（异常设备） |
| 404 | `not_found` | 路径不存在 | 不重试 |
| 429 | `rate_limited` | 触发限流 | 按 `Retry-After` 等待后重试一次 |
| 500 | `server_error` | 服务端异常 | 不立即重试，下次启动再试 |

## 4. 接口（v1 已实现）

### 4.1 GET /health

探活，客户端不调用。

```
200 { "status": "ok", "env": "production" }
```

### 4.2 POST /v1/devices/register

设备登记与 token 签发。

请求：

```json
{
  "deviceId": "uuid",
  "deviceSecret": "base64-32bytes",
  "appVersion": "1.0",
  "build": "2",
  "platform": "ios"
}
```

首次登记响应（仅这一次返回明文 token）：

```json
{ "deviceToken": "opaque-random", "expiresAt": "2027-02-24T00:00:00Z" }
```

之后的续期响应：

```
200 { "expiresAt": "2027-02-24T00:00:00Z" }
```

规则：

- 幂等：同一 deviceId 只更新 `last_seen` 与版本号，不新增行
- 同设备未过期、未吊销时复用同一 token，不重新签发
- 有效期 3 个月，每次 register 滑动续期
- 只存 deviceId、secret 哈希、token 哈希、首次/最后时间、版本号
- 限流：按 IP 10 次/分钟、按 deviceId 5 次/分钟

## 5. 接口（M4 规划，未实现）

### 5.1 POST /v1/parse

截图或文本解析，服务端调模型。

```
Authorization: Bearer <deviceToken>
Content-Type: multipart/form-data
  image: <jpeg/png，≤ 2 MB>  或  text: <≤ 500 字>
```

```json
{
  "category": "takeout",
  "amountCents": 3000,
  "merchant": "美团",
  "confidence": 0.92
}
```

- 先扣额度（Redis 原子），再调模型；失败退额度
- 不在数据库事务里调用模型
- 限流与额度按 deviceId；绑定账号后归到 accountId

### 5.2 POST /v1/diagnostics

客户端诊断日志批量上报，只收动作与错误码。

```json
{
  "deviceId": "uuid",
  "accountId": null,
  "entries": [
    { "at": "2026-11-24T12:00:00Z", "event": "record_saved", "code": null }
  ]
}
```

- 单次最多 200 条，累计 ≤ 100 KB
- 不含金额、备注、商户等财务内容

## 6. 限流与配额

| 接口 | 维度 | 规则 | 超限响应 |
|---|---|---|---|
| register | IP / deviceId | 10 次/分、5 次/分 | 429 + `Retry-After` |
| parse | deviceId | 免费额度 + 滑动窗口 | 429 或 402 |
| diagnostics | deviceId | 10 次/小时 | 429 |

## 7. 变更记录

- **2026-11-24 v1**：register 每次启动上报；引入 deviceSecret；设备 token 改 opaque + 3 个月滑动

