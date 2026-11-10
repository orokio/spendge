# Spendge · 海绵记账

一个 iOS 记账应用（个人项目）。当前处于开发早期：**数据模型与业务骨架已完成，UI/UE 待讨论后设计**。

## 技术栈

- SwiftUI + SwiftData
- 本地优先存储（无网络依赖），后续可接 CloudKit 同步
- 部署目标 iOS 17.0

## 目录结构

```
spendge/
├── Models/          # SwiftData 数据模型与预置数据
│   ├── Account.swift        # 账户
│   ├── Category.swift       # 分类
│   ├── Transaction.swift    # 账单
│   ├── Budget.swift         # 预算
│   ├── Money.swift          # 金额工具（分/元转换）
│   ├── SpendgeEnums.swift   # 收支类型 / 账户类型
│   └── DefaultData.swift    # 首次启动种子数据
├── Services/        # 业务逻辑层
│   ├── TransactionService.swift  # 记账/查询/月度统计/余额
│   ├── CategoryService.swift     # 分类管理
│   ├── AccountService.swift      # 账户管理与总资产
│   ├── BudgetService.swift       # 预算与进度
│   ├── ModelContainerProvider.swift
│   ├── DemoData.swift            # DEBUG 模拟账单（仅 Debug 构建）
│   └── SpendgeError.swift
├── Views/            # UI 层（初版 demo）
│   ├── MainTabView.swift         # 底部三 Tab：流水 / 记一笔 / 统计
│   ├── TransactionListView.swift # 流水：月度汇总 + 按日分组列表
│   ├── RecordView.swift          # 记一笔：金额键盘 + 分类网格
│   ├── StatisticsView.swift      # 统计：收支汇总 + 预算进度 + 分类占比
│   └── Components.swift          # 通用组件（品牌色/金额/分类图标/月份切换）
├── spendgeApp.swift   # App 入口（已挂载 ModelContainer）
```

## 当前能力（业务层）

- 记一笔 / 改一笔 / 删一笔
- 按时间区间、账户、分类、关键词查询
- 月度汇总（收支总额 + 分类分布）
- 账户余额与总资产
- 预算设置与进度
- 首次启动自动写入 14 个默认分类 + 「现金」账户

## UI 初版 demo

- 底部三 Tab：流水 / 记一笔 / 统计
- 流水：月度切换、本月收支卡片、按日分组账单列表、左滑删除
- 记一笔：自定义金额键盘、支出/收入切换、分类网格、账户与日期选择、备注
- 统计：收支汇总卡片、整体预算进度、支出分类占比条
- DEBUG 构建首次启动自动生成 3 个月模拟账单（Release 无此行为）

## 验证情况

- 已通过 `xcodebuild` 编译验证（Xcode 26.6）
- 冒烟测试覆盖：种子数据、记账、月度汇总、余额联动、搜索、预算进度、删除保护（临时脚本，验证后已清理）
- UI demo 需在 Xcode 中运行模拟器人工验证

## 待决策

- UI/UE 方案
- 记账页交互细节（键盘布局、分类配色）
- 是否需要转账、周期记账、多账本等扩展能力

文档入口：产品方向见 [docs/product-plan.md](docs/product-plan.md)，开发计划见 [docs/dev-plan.md](docs/dev-plan.md)，技术设计见 [docs/architecture.md](docs/architecture.md)。
