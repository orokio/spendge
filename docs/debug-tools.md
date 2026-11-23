# 调试工具（DEBUG only）

> 状态：设计定稿（2026-11-23）· 只存在于 DEBUG 构建
> 相关：[architecture.md](architecture.md) 的失败态约定、[dev-plan.md](dev-plan.md) §5.7

## 目标与边界

调试工具解决三件事：

1. **故障注入**：手动让写操作失败，验证失败提示与数据不丢
2. **数据模拟**：一键生成特定形态的账本，复现截图与边界
3. **后门**：重置引导、查看自检结果、导出日志等

边界：

- 只在 DEBUG 编译。Release / TestFlight 里连入口的计数器都不存在
- 不做常驻浮窗，所有工具收在设置页的「开发者」面板
- 不把调试开关写进业务逻辑：业务层只看到「这一步可能抛错」，不知道调试的存在
- 调试工具不得改变正式数据结构；模拟数据都走正常模型

## 入口

首页情绪句连点 **10 次**解锁，规则：

- 3 秒内完成，单次停顿超过 1.5 秒清零
- 解锁时一次轻触反馈 + toast「开发者模式已开启」
- 解锁状态存 `UserDefaults`，重启仍有效
- 设置页最下面出现「开发者」入口，点开是从右侧进入的**二级页面**，保留底部导航
- 左上角返回按钮，支持右滑返回；与其它全屏页同一套返回手势
- 面板内提供「关闭开发者模式」，关闭后入口消失，开关不重置

放在设置页而不是首页，是因为这些操作会改数据；彩蛋只负责解锁，不负责执行。

## 结构

```
spendge/Debug/
├── DebugMode.swift          # 解锁状态与连点计数
├── DebugSettings.swift      # 持久化的故障开关与场景选择
├── FaultInjector.swift      # 故障点协议、默认空实现、DEBUG 实现
├── DebugDataSeeder.swift    # 数据模拟场景
└── DebugPanelView.swift     # 开发者面板
```

除 `FaultInjector` 的协议与空实现外，其余文件整体包在 `#if DEBUG` 里。

## 故障注入

### 故障点

```swift
enum FaultPoint: String, CaseIterable {
    case transactionWrite      // 记账新增 / 编辑 / 删除
    case goalWrite             // 目标新建 / 修改 / 删除 / 暂停
    case budgetWrite           // 预算设置 / 清除
    case dayConfirmationWrite  // 没花钱确认 / 取消
    case shareExport           // 分享图片生成与写入
    case cloudSync             // iCloud 同步（未接入，先留位）
    case parseRequest          // 云端解析（未接入，先留位）
}
```

### 协议

```swift
protocol FaultInjector {
    func check(_ point: FaultPoint) throws
}

struct NoFaultInjector: FaultInjector {
    func check(_ point: FaultPoint) throws {}
}
```

- 服务层方法默认注入 `NoFaultInjector`，调用 `try injector.check(.transactionWrite)`
- DEBUG 实现读取 `DebugSettings`：对应故障点打开就抛 `SpendgeError.injectedFailure(point)`
- 错误文案带故障点名，例如「模拟失败：账单写入」，验证时一眼知道断在哪一层
- Release 使用空实现，编译期没有分支，也不增加运行时判断

### 开关

面板按故障点分组，另提供两个批量开关：

- 全部写入失败（账单 / 目标 / 预算 / 没花钱）
- 全部分享失败

开关状态存 `UserDefaults`，key 统一为 `debug.fault.<point>`。

失败提示复用顶部 toast（红色胶囊，3 秒自动收起），不再弹阻断式 alert；只有二次确认（清空数据、生成场景）才用弹窗。

## 数据模拟

### 场景

```swift
enum DebugScenario: String, CaseIterable {
    case empty              // 清空全部用户数据
    case firstWeek          // 首周：7 天、每日 1–2 笔、一条备注
    case oneMonth           // 一个月：覆盖主要分类与收入
    case nearTrophyUnlock   // 差一笔解锁「一百笔」，验证 celebrate
    case overBudget         // 本月预算超支
    case incomeHeavy        // 收入为主，验证统计页收入侧
}
```

### 约定

- 固定随机种子与日期偏移，同一场景每次结果一致，截图可复现
- 执行前二次确认，明确「会清空当前账本」
- 执行时临时旁路故障注入，避免模拟过程自己被拦住
- 场景通过模型与 `ModelContext` 直接写入，不依赖 UI 流程
- 不生成奖杯解锁记录：让 `AchievementService` 在下次刷新时自然补写，顺便验证判定

## 面板

```
开发者
├── 故障注入
│   ├── 账单写入
│   ├── 目标写入
│   ├── 预算写入
│   ├── 没花钱
│   ├── 分享图片
│   └── 全部写入失败
├── 数据模拟
│   ├── 首周
│   ├── 一个月
│   ├── 近解锁
│   ├── 超预算
│   ├── 收入为主
│   └── 清空数据
├── 诊断
│   ├── 运行 SelfCheck
│   ├── 自检日志（导出 / 分享 selfcheck.log）
│   └── 重置首启引导（待引导上线后接入）
└── 关闭开发者模式
```

## 验证清单

- [ ] DEBUG 包连点 10 次解锁；Release 包无入口
- [ ] 打开单个故障点，对应路径弹「操作没有完成」，页面不关闭
- [ ] 全部写入失败后，记账 / 目标 / 预算 / 没花钱均被拦截
- [ ] 分享图片失败有提示
- [ ] 开发者页保留底部导航，返回按钮与右滑都能回到设置
- [ ] 自检日志可以导出并分享
- [ ] 数据场景可复现：同一场景两次结果一致
- [ ] 关闭开发者模式后入口消失，故障开关不生效
- [ ] Release 构建中 `Debug/` 目录之外无调试判断

## 未来扩展

- 云端解析返回模拟（低置信度 / 超时 / 限流）
- iCloud 同步冲突与不可用模拟
- 首启引导重置
- 本地日志导出（用户反馈用）
- 崩溃 / 卡顿注入（仅 DEBUG）
