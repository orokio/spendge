# Spendge · 海绵记账

一个 iOS 记账应用（个人项目）。当前处于早期验证阶段：**核心交互已实现，正在试用验证留存假设**。

产品方向：不做功能堆叠的账簿工具，而是让「记账这个动作」有意义——记录靠选择，选择靠积累，回看讲生活不讲报表。

## 技术栈

- SwiftUI + SwiftData
- 本地优先（无网络依赖），后续接 CloudKit
- 部署目标 iOS 17.0

## 目录结构

```
spendge/
├── Models/
│   ├── Account / Category / Transaction / Budget
│   ├── DayConfirmation.swift   # 「今天没花钱」的确认记录
│   ├── Money.swift             # 分/元转换
│   ├── SpendgeEnums.swift      # 收支类型 / 账户类型 / 分类 code 与领域 / 内部标签
│   └── DefaultData.swift       # 种子：11 个动作分类 + 4 个收入分类 + 现金账户
├── Services/
│   ├── TransactionService.swift     # 记账/查询/月度汇总/覆盖率/金额建议
│   ├── InsightService.swift         # 首屏那句话（确定性模板）
│   ├── DayConfirmationService.swift # 每日确认，幂等
│   ├── CategoryService / AccountService / BudgetService
│   ├── SelfCheck.swift              # DEBUG 只读自检，结果写 Documents/selfcheck.log
│   ├── ModelContainerProvider.swift
│   └── SpendgeError.swift
├── Views/
│   ├── RootView.swift      # 无 Tab：今天 ←→ 回看，横向拖动切换
│   ├── TodayView.swift     # hero 一句话 + 今日流水 + FAB
│   ├── RecordSheet.swift   # 半屏记录面板：日期轴 + 金额 + 分类胶囊
│   ├── ReviewView.swift    # 回看：覆盖率 / 笔数柱状图 / 吃的结构 / 领域分布
│   └── Components.swift
└── spendgeApp.swift
```

## 当前能力

- **今天**：一句话（如「这周点了 2 次外卖，比上周少 4 次」）+ 今日流水 + 「今天没花钱」
- **记一笔**：点分类 → 金额已预填（或给档位）→ 记下；14 天日期轴；账户/备注/冲动折叠在「···」
- **回看**：覆盖率（按已过天数算）、记录密度柱状图、吃的结构、领域分布、预算
- **业务层**：记账 / 查询 / 月度汇总 / 余额 / 预算进度 / 数据覆盖率 / 自适应金额建议

## 开发

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project spendge.xcodeproj -scheme spendge \
  -destination 'generic/platform=iOS Simulator' build
```

- DEBUG 启动会跑 SelfCheck（11 项只读不变量），结果同时写到 App 沙盒 `Documents/selfcheck.log`
- 种子版本（`spendge.seedVersion`）变化时，**创建容器前删除 store 文件**，不做迁移
- 结构变更相关坑见 [docs/architecture.md](docs/architecture.md) 的「已知坑」

## 文档

- 产品方向：[docs/product-plan.md](docs/product-plan.md)
- 开发计划：[docs/dev-plan.md](docs/dev-plan.md)
- 技术设计：[docs/architecture.md](docs/architecture.md)
