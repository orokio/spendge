import Foundation
import SwiftData

/// 账本类型：v1 只有个人账本，多人为后续版本预留。
enum LedgerKind: String, CaseIterable {
    case personal
    case shared
}

/// 账本：用户数据的归属单位。v1 只有一本，不在界面上展示。
@Model
final class Ledger {
    var id: UUID = UUID()
    var name: String = "我的账本"
    var kindRawValue: String = LedgerKind.personal.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// 软删除时间；nil 表示未删除
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String = "我的账本",
        kind: LedgerKind = .personal,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: LedgerKind {
        get { LedgerKind(rawValue: kindRawValue) ?? .personal }
        set { kindRawValue = newValue.rawValue }
    }
}
