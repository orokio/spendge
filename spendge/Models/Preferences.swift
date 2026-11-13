import Foundation

/// 用户偏好的存储键。视图里用 @AppStorage 读写，键集中在这里避免拼错。
enum PreferenceKey {
    /// 记下后是否留在记录页
    static let stayAfterSave = "pref.stayAfterSave"
}
