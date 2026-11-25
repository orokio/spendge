import Foundation
import SwiftData

/// 某一天的「今天没花钱」确认。
/// 存在即表示用户主动声明当天无支出 —— 这是「零花费日」目标与数据覆盖率的数据源。
@Model
final class DayConfirmation {
    var id: UUID = UUID()
    /// 所属账本；v1 固定为默认账本
    var ledgerID: UUID?
    /// 当天零点（本地时区）
    var day: Date = Date.now
    var createdAt: Date = Date.now
    /// 软删除时间；nil 表示未删除
    var deletedAt: Date?

    init(id: UUID = UUID(), day: Date, ledgerID: UUID? = nil, createdAt: Date = .now) {
        self.id = id
        self.day = day
        self.ledgerID = ledgerID
        self.createdAt = createdAt
    }
}
