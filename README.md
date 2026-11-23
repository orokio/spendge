# Spendge · 海绵记账

一个 iOS 记账应用（个人项目）。**M3 已完成**：四个 tab 的核心体验、目标与奖杯、首启引导都已落地；下一步是观测与 iCloud。服务端开发暂停，后续在云端环境继续。

产品方向：不做功能堆叠的账簿工具，而是让「记账这个动作」有意义——记录靠选择，选择靠积累，回看讲生活不讲报表。

## 技术栈

- SwiftUI + SwiftData，本地优先；账本同步走 CloudKit（未开始）
- 仅中文，目标 iOS 17.0
- 服务端骨架：Flask（`server/`），尚未接入客户端

## 目录结构

```
spendge/
├── Models/       # Transaction / Category / Budget / Goal / TrophyUnlock 等
├── Services/     # 记账、统计、目标、奖杯判定、备份、语音解析
├── Views/        # 四个 tab + 记录页 + 目标抽屉 + 奖杯墙
├── Assets.xcassets
└── spendgeApp.swift

server/           # 服务端骨架（Flask + health + serve.sh），暂停
docs/             # 产品、计划、架构、界面规范、服务端设计
```

## 当前能力

- **记账**：一句话情绪句 + 固定柱图 + 连续日期流水；二级记录页（金额、分类、备注、语音）
- **首启引导**：聚光灯模式。首页三步（情绪句 / 没花钱 / 记一笔），首次进目标页再高亮预算；点任意处下一步，可跳过且不再展示
- **统计**：储蓄卡、支出 / 收入切换；支出结构与分类饼图（可下钻明细）；收入来源与近 6 个月结余
- **目标**：本月预算、目标进度环与状态、暂停 / 恢复、顶部抽屉表单
- **奖杯墙**：30 枚三态网格（已解锁 / 进行中 / 未解锁）、系列卡片与「下一档」提示、详情与分享、记账后的解锁庆祝
- **设置**：导出 CSV / JSON 备份、从备份恢复、清空数据

## 开发

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project spendge.xcodeproj -scheme spendge \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

- 带 `-selfcheck` 启动才跑 SelfCheck（49 项只读不变量），结果写到沙盒 `Documents/selfcheck.log`
- 覆盖安装：先尝试迁移，迁移失败才清库；不再按种子版本无条件删库
- 结构变更与踩坑记录见 [docs/architecture.md](docs/architecture.md)

## 崩溃上报（Bugly）

- 把 `Bugly.xcframework` 放到仓库根目录的 `Frameworks/`（二进制不入库，clone 后需要手动放一次）
- 在 `spendge/Info.plist` 的 `BuglyAppId` 填入 Bugly 控制台的 App ID；App Key 按官方说明留空即可
- 首次启动展示隐私页，同意后才初始化；App ID 为空时 SDK 不启动
- 设置 → 隐私与数据 可查看隐私政策

## 服务端

代码在 `server/`，目前只有 Flask 健康检查与本地起停脚本，**开发暂停，后续在云端继续**。设计与部署见：

- [docs/server-design.md](docs/server-design.md)
- [docs/deploy-plan.md](docs/deploy-plan.md)

## 文档

- 产品方向：[docs/product-plan.md](docs/product-plan.md)
- 开发计划：[docs/dev-plan.md](docs/dev-plan.md)
- 技术设计：[docs/architecture.md](docs/architecture.md)
- UI 规范：[docs/ui-spec.md](docs/ui-spec.md) / [docs/visual-language.md](docs/visual-language.md)
- 成就体系：[docs/achievements.md](docs/achievements.md)
- 调试工具：[docs/debug-tools.md](docs/debug-tools.md)
- 上架清单：[docs/release-checklist.md](docs/release-checklist.md)
- iCloud 同步设计：[docs/icloud-sync-design.md](docs/icloud-sync-design.md)
- 试用反馈：[docs/feedback.md](docs/feedback.md)
