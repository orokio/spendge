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
│   └── SpendgeError.swift
├── spendgeApp.swift   # App 入口（已挂载 ModelContainer）
└── ContentView.swift  # 占位视图（UI 阶段再动）
```

## 当前能力（业务层）

- 记一笔 / 改一笔 / 删一笔
- 按时间区间、账户、分类、关键词查询
- 月度汇总（收支总额 + 分类分布）
- 账户余额与总资产
- 预算设置与进度
- 首次启动自动写入 14 个默认分类 + 「现金」账户

## 验证情况

- 已通过 `xcodebuild` 编译验证（Xcode 26.6）
- 冒烟测试覆盖：种子数据、记账、月度汇总、余额联动、搜索、预算进度、删除保护（临时脚本，验证后已清理）

## 待决策

- UI/UE 方案
- 是否需要转账、周期记账、多账本等扩展能力

详细设计见 [docs/architecture.md](docs/architecture.md)。
