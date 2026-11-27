#if DEBUG
import Foundation

/// 开发者模式的解锁状态与首页连点计数。整段只在 DEBUG 编译。
enum DebugMode {
    private struct TapState {
        static var count = 0
        static var firstTap = Date.distantPast
        static var lastTap = Date.distantPast
    }

    /// 首页是否显示「最近删除」入口：只在 DEBUG 构建存在，由开发者面板开关
    static var showsRecentlyDeleted: Bool {
        UserDefaults.standard.bool(forKey: DebugKeys.recentlyDeletedEntry)
    }

    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: DebugKeys.unlocked)
    }

    static func setUnlocked(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: DebugKeys.unlocked)
    }

    /// 首页情绪句每次点击调用；凑满 10 次返回 true。
    @discardableResult
    static func registerTap(now: Date = .now) -> Bool {
        // 停顿超过 1.5 秒，或整组超过 3 秒，重新开始
        if now.timeIntervalSince(TapState.lastTap) > 1.5
            || now.timeIntervalSince(TapState.firstTap) > 3 {
            TapState.count = 0
            TapState.firstTap = now
        }
        TapState.count += 1
        TapState.lastTap = now

        guard TapState.count >= 10 else { return false }
        TapState.count = 0
        setUnlocked(true)
        return true
    }
}
#endif
