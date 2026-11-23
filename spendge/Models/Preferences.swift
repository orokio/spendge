import Foundation

/// 用户偏好的存储键。视图里用 @AppStorage 读写，键集中在这里避免拼错。
enum PreferenceKey {
    /// 记下后是否留在记录页
    static let stayAfterSave = "pref.stayAfterSave"
    /// 首启引导：首页三步是否看过
    static let onboardingHomeSeen = "pref.onboardingHomeSeen"
    /// 首启引导：目标页预算这一步是否看过
    static let onboardingBudgetSeen = "pref.onboardingBudgetSeen"
}
