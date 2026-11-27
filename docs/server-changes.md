# 服务端改动清单

按时间倒序。每次客户端契约或商业模型变化时追加一节。

## 2026-11-27 · 商业模式改为付费买断

**背景**：App 改为 ¥18 付费下载，无内购、无免费版、无订阅。客户端删除了 StoreKit、Entitlement 能力层与友盟统计 SDK。

### 1. 必须改的代码

**没有。** 注册接口契约不变：

```
POST /v1/devices/register
deviceId, deviceSecret, appVersion, build, platform, categoriesVersion
```

分类下发逻辑、版本比对、goalKinds 全部沿用现状。客户端仍会在每次冷启动时上报一次。

### 2. 需要同步的认知

1. **不再有会员/权益概念**。`account`、`session`、`entitlement`、`usage`、`diagnostic`、`event` 六张表为将来的账号体系保留，当前全部不启用。**不要再往里加业务逻辑**，也不要把「有表」当成「有功能」。
2. **统计口径变了**。客户端移除友盟，`docs/user-stats-spec.md` 的对账对象已从友盟改为 App Store Connect：下载量与收入以 ASC 为准，`device_daily` 只用于看首启转化与留存趋势。`app/stats.py` 不需要改代码，确认注释里的文档路径仍有效即可。
3. **版本号**：客户端 appVersion 仍是 `1.0`，build 从 10 开始；分类版本（当前 v6）不变。
4. **未来扩展**：若以后支持「每个账本自定义分类」，需要新增分类服务（按账本覆盖 + 与全局目录合并的策略），届时单开一节说明。现在不做。

### 3. 可删的代码（清理）

这些是早期规划留下、目前零引用的部分，建议直接删掉，避免以后被误用。

**五张没有引用的表**（`app/models.py` 里对应的类一并删）：

| 表 | 原计划用途 |
|---|---|
| `account` | 账号体系（不做） |
| `entitlement` | 权益判定（改为买断，服务端不参与） |
| `usage` | 解析配额（不做） |
| `diagnostic` | 诊断上报（不做） |
| `event` | 埋点汇总（不接第三方统计） |

配套需要一个新的 alembic revision 执行 `op.drop_table`，并在生产库跑一次 `alembic upgrade head`。

**必须保留的**：`devices`、`sessions`（register 签发 token）、`categories`、`app_config`、`device_daily`、`category_versions`。

**模块层没有可删的**：`cache` / `categories` / `config` / `db` / `devices` / `main` / `models` / `rate_limit` / `stats` / `writer` 全部有引用；`deploy/` 下的 `stats.sh`、`serve.sh` 与三个 service 文件都在用。

### 4. 检查项

- [ ] `register` 返回的 `goalKinds` 与 `docs/categories-seed.json` 一致（当前 v6，29 条，19 条非空）
- [ ] `docs/api-contract.md` 里 /v1/parse 那一行仍写着「免费额度」，措辞待 `/v1/parse` 真正排期时改为「按设备限流」
- [ ] 生产库中 `categories` 的 `goal_kinds` 列已部署（2026-11-26 已完成）

## 2026-11-26 · 分类下发带 goalKinds

已完成并上线（v6）：`categories` 加 `goal_kinds` 列，register 响应每条分类带 `goalKinds` 数组，导入校验只接受 `countLimit` / `budget` / `shareCap`。客户端据此过滤目标可选分类。
