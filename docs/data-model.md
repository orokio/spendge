# 数据模型清单

> 状态：2026-11-25 ｜ 依据当前代码（CloudKit 单 store 全量同步）
> 说明：关系字段已全部移除，跨表身份用 code / ledgerID；所有表都参与 iCloud 同步。

## 账本

| 字段 | 说明 |
|---|---|
| id: UUID | 账本身份，全局唯一 |
| name | 默认「我的账本」，v1 不展示 |
| kindRawValue | personal / shared，v1 固定 personal |
| createdAt / updatedAt / deletedAt | 与其他表一致 |

v1 只有一本账本，由 `StableID.ledger("default")` 生成固定 UUID；没有切换、重命名、邀请成员的界面。

## 用户能看到的表

| 表 | 用户看到的地方 | 核心字段 | 说明 |
|---|---|---|---|
| Transaction | 今天、回看、分类明细 | id、ledgerID、amountCents、kindRawValue、date、note、categoryCode、refundOfID、deletedAt | 一笔账；退款金额为负并指回原单 |
| Goal | 目标页（目标列表 + 预算卡） | id、ledgerID、title、kindRawValue、categoryCodes、periodStart、targetValue、isActive、isRecurring、deletedAt | 每月一份；`kind = budget` 时是预算：分类为空=全部支出，非空=分类金额上限 |
| GoalAchievement | 目标历史 | id、goalID、title、periodStart、achieved、currentValue、targetValue、unitRawValue、deletedAt | 周期结束固化，目标删了记录保留 |
| DayConfirmation | 今天页「没花钱」 | id、ledgerID、day、deletedAt | 一天最多一条 |
| TrophyUnlock | 奖杯墙 | trophyID、unlockedAt、deletedAt | 只记录已解锁，目录是代码常量 |

## 归属规则

- 账单、预算、目标、没花钱确认：带 `ledgerID`，属于某本账
- 目标达成记录：通过 `goalID` 间接归属，不重复存
- 奖杯解锁：属于用户本人，不属于某本账

## 字段层面的内部实现

| 字段 | 归属 | 用户是否感知 |
|---|---|---|
| ledgerID | Transaction / Goal / DayConfirmation | 否；v1 固定默认账本 |
| deletedAt | 同步表 | 否；软删除标记，30 天后物理清理 |
| sortOrder | Goal | 否；固定排序用 |

## 存储与同步

- 单一 CloudKit store，所有表同步
- 分类不建表、不参与 CloudKit 同步；由 `CategoryCatalog` 管理（内置默认 + 注册响应下发）
- 账本 ID 固定，两台设备同一条
- 去重规则：账本/其余表按 id，没花钱按日期；优先级为未删除 > 更新时间新
- 去重执行点：启动、CloudKit 导入后、备份恢复后

## 备份

- 当前版本 **v5**，不再包含分类表，账单直接带 `categoryCode`；旧备份的 budgets 会转成 `Goal(kind: budget)`
- 兼容 v1 / v2：缺账本归入默认账本，未知字段忽略
- 恢复前校验 id 唯一，恢复后统一去重

## 已知的历史设计残留

| 项 | 现状 | 处理建议 |
|---|---|---|

## 字段生命周期规则（改模型前必读）

1. **CloudKit 生产 schema 只增不减**：已部署的字段和记录类型无法删除，删除只是客户端停用
2. **废弃字段名永不复用**：新语义必须用新字段名，否则旧值会被误读
3. **字段类型一次定死**：生产环境不允许改类型，要改只能新建字段 + 迁移
4. **业务代码只走 SwiftData**：不要用原始 CloudKit / SQLite 读旧字段，那会绕过模型的保护
5. **废弃流程**：停止写入 → 确认无读取 → 从模型删除 → 旧值留在云端但不再参与任何逻辑
6. **新增字段前确认语义最终**：可选、带默认值的字段成本低；没想清楚的字段不要加，因为删不掉

## 已定决策

- 2026-11-25：分类改为服务端下发的参考数据，客户端不建表、不同步 CloudKit；code 永久不变，只允许新增/改名/归档
- 2026-11-25：预算并入 Goal（kind = budget），不再有独立 Budget 表
- 2026-11-25：多人账本、Ledger 成员与共享不在 v1 范围，相关字段延后
- 2026-11-25：空 code 只可能来自开发机旧数据，不做迁移，读取时容忍

## 分类目录（非数据表）

分类不再建 SwiftData 表，也不参与 CloudKit 同步。由 `CategoryCatalog` 管理：

- 内置默认 29 条，作为离线与首次启动的兜底
- 注册接口返回 `categoriesVersion` + `categories` 时更新并缓存到本地文件
- 客户端只读：不新增、不改名、不删除；服务端只允许新增/修改展示字段/归档
- 账单只存 `categoryCode`，未知 code 显示为「未分类」，不改写数据
