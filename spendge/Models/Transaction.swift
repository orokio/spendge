import Foundation
import SwiftData

/// 账单（一笔收支记录）。普通账单金额为正，方向由 kind 决定；退款记录金额为负。
@Model
final class Transaction {
    var id: UUID = UUID()
    /// 金额（分）
    var amountCents: Int64 = 0
    var kindRawValue: String = TransactionKind.expense.rawValue
    var date: Date = Date.now
    var note: String?

    /// 所属账本；v1 固定为默认账本
    var ledgerID: UUID?
    /// 分类的跨设备身份：一律按 code 匹配，关系只在本机解析
    var categoryCode: String?

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// 退款记录指回原单；普通账单为 nil
    var refundOfID: UUID?
    /// 软删除时间；nil 表示未删除
    var deletedAt: Date?


    init(
        id: UUID = UUID(),
        amountCents: Int64,
        kind: TransactionKind,
        date: Date = .now,
        note: String? = nil,
        category: CategoryInfo? = nil,
        categoryCode: String? = nil,
        ledgerID: UUID? = nil,
        refundOfID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.amountCents = amountCents
        self.kindRawValue = kind.rawValue
        self.date = date
        self.note = note
        self.ledgerID = ledgerID
        self.categoryCode = categoryCode ?? category?.code
        self.refundOfID = refundOfID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 分类对象：按 code 在本机解析
    @MainActor var category: CategoryInfo? { CategoryCatalog.shared.category(code: categoryCode) }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }

    /// 金额（元）
    var amount: Decimal { Money.yuan(from: amountCents) }

    /// 列表顺序：新的在上。时间相同的（同一天连续记多笔）按创建时间倒序
    static func newestFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.createdAt > rhs.createdAt
    }

    /// 对总额的贡献：收入为 +，支出为 -
    var balanceDeltaCents: Int64 {
        switch kind {
        case .expense: return -amountCents
        case .income: return amountCents
        }
    }
}
