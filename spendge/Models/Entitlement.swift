import Foundation

/// 能力层：视图只问“能不能用”，不直接问“买没买”。
/// v1 只有一次性解锁；以后接订阅时只换这里的判定。
enum Capability {
    /// 目标数量不限（免费版最多 2 个）
    case unlimitedGoals
    /// 完整历史回看（免费版只看近 3 个月）
    case fullHistory
    /// iCloud 多设备同步
    case iCloudSync
}

enum Entitlements {
    private static let key = "entitlement.unlocked"

    /// 免费版的目标上限
    static let freeGoalLimit = 2
    /// 免费版可回看的月数
    static let freeHistoryMonths = 3

    static var isUnlocked: Bool {
        get {
            #if DEBUG
            // 开发期默认全功能；调试面板可以模拟免费版
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            #endif
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func can(_ capability: Capability) -> Bool {
        if isUnlocked { return true }
        switch capability {
        case .unlimitedGoals, .fullHistory, .iCloudSync:
            return false
        }
    }
}
