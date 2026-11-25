# iCloud 同步设计（实施中）

> 目标：本地记账数据通过 CloudKit 在用户自己的设备间同步，不引入自有账号与服务端。
> 状态：2026-11-25 模型已按本稿改造，真机启用 CloudKit。

## 1. 范围

- 同步：账单、预算、目标、达成记录、没花钱确认、奖杯解锁、分类、账户
- 不同步：App 偏好设置、调试与诊断数据
- iCloud 未登录或不可用 → 纯本地，不阻塞任何记账动作
- 不做自有账号；身份就是用户的 Apple ID

## 2. 身份用 code，种子 ID 由 code 推导

先厘清两个东西：

- **UUID**：SwiftData 的行 ID。随机生成的 UUID 在两台设备上不一样，CloudKit 就会把同一个「点外卖」当成两条记录。
- **code**：分类/账户的业务身份，例如 `takeout`、`dineout`、`cash`。跟显示名无关，改名不影响，所有匹配、目标、统计都靠它。

SwiftData 不允许把 `code` 设成主键，CloudKit 也不支持唯一约束，所以做法是：**用 code 算出一个固定的 UUID 当行 ID**（SHA-256 前 16 字节，见 `StableID`）。每台设备独立算出来的「点外卖」是同一个 ID，CloudKit 合并成同一条记录，不需要运行时扫表去重。

- Transaction 存 `categoryCode`、`accountCode`，Budget 存 `categoryCode`
- 分类与账户**参与同步**；种子用 `StableID.category(code)` / `StableID.account(code)`
- 账单/预算与 Category/Account 的关系字段已移除，显示时按 code 解析（`EntityLookup`，按 context 缓存）
- 分类与账户目前不支持自定义，code 是封闭集合；启动时会把旧记录的 ID 归一化，并按 code 归并重复项

### 影响

- 所有用 `transaction.category`、`transaction.account`、`budget.category` 的视图与统计，改为按 code 查
- 迁移：旧关系已通过备份恢复完成 code 回填，关系字段已删除
- 这是模型层的一次大改

## 3. 冲突与删除

- **编辑冲突**：最后写入优先（比较 `updatedAt`），不做字段级合并
- **删除**：软删除，增加 `deletedAt`；所有查询过滤已删除；30 天后物理清理
  - 避免「一台设备删除、另一台旧副本把它复活」
- **重复记录**：合并时按 id 去重；同 id 取 updatedAt 较新的
- 首次开启同步：以本机数据为基准上传，之后双向合并

## 4. 同步状态与设置

设置页新增一张 iCloud 卡：

- 开关：关闭后仅本机，提示其他设备不再更新
- 状态：可用 / 未登录 / 容量不足 / 同步中 / 上次成功时间
- 失败原因可读，可点重试
- 首次开启时说明：数据会上传到用户自己的 iCloud，不经过我们

默认建议：**首次启动不主动开启**，在设置里由用户打开；开启前说明数据去向。

开启同步时发起 **Sign in with Apple**：

- 服务端按 Apple 用户标识创建/找回 accountId，并绑定当前 deviceId
- 服务端不可用**不阻塞** CloudKit 同步；账号关联稍后重试，期间日志只带 deviceId
- 第二台设备登录同一 Apple ID → 绑定到同一 accountId
- 只要存在账号，就必须提供 App 内删除账号入口（上架硬要求）

## 5. 迁移与兼容

- 模型变更一次到位：去 unique、关系可选、加 deletedAt、加 categoryCode/accountCode
- 旧库迁移：按现有关系回填 code；失败不删库，提示用户导出备份
- 同步开关关闭时，CloudKit 不参与任何读写
- 版本兼容：旧版本客户端不参与同步，不与新版本混用同一库

## 6. 双设备测试清单

两台真机都已连接本机，可直接跑：

- [ ] 设备 A 新建 → 设备 B 收到；编辑、删除同理
- [ ] 两台同时改同一笔：以较新的 updatedAt 为准，不产生两条
- [ ] 一台离线记录多笔 → 恢复网络后合并，无重复
- [ ] 一台删除、另一台编辑：删除优先，不复活
- [ ] 关闭 iCloud → 只写本地；重新开启 → 合并
- [ ] 退出 iCloud 账号 → 自动纯本地，不报阻断错误
- [ ] 重装 App → 从 iCloud 拉回完整数据
- [ ] 大数据量（1000+ 笔）首次同步时长与内存可接受

## 7. 风险

- 关系可选化会牵动大量视图代码，属于本轮最大改动
- 软删除要求所有查询过滤 deletedAt，容易漏
- CloudKit 在中国区由云上贵州承载，需真机验证可用性与延迟
- 同步问题难以复现，必须先有本地诊断日志

## 8. 已确认 / 待确认

已确认：

- 删除用软删除 + 30 天清理
- iCloud 默认关闭，由用户在设置开启
- 分类/账户以 code 为身份，且参与同步；种子 ID 由 code 推导为固定 UUID
- 账单存 `categoryCode` / `accountCode`，预算存 `categoryCode`；关系字段已移除
- 同步范围：账单、预算、目标、达成记录、没花钱确认、奖杯解锁、分类、账户
- 分类与账户不支持自定义（至少当前版本）

待确认：

- 日志的账户标识是否用 CloudKit 的 `userRecordID`（同一 Apple ID 跨设备一致），iCloud 不可用时退回 Keychain UUID

