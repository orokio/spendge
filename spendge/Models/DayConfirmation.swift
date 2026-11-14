import Foundation
import SwiftData

/// 某一天的「今天没花钱」确认。
/// 存在即表示用户主动声明当天无支出 —— 这是「零花费日」目标与数据覆盖率的数据源。
@Model
final class DayConfirmation {
    @Attribute(.unique) var id: UUID
    /// 当天零点（本地时区）
    var day: Date
    var createdAt: Date

    init(id: UUID = UUID(), day: Date, createdAt: Date = .now) {
        self.id = id
        self.day = day
        self.createdAt = createdAt
    }
}
