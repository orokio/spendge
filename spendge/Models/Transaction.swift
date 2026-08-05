import Foundation
import SwiftData

/// 账单（一笔收支记录）。金额恒为非负数，方向由 kind 决定。
@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    /// 金额（分）
    var amountCents: Int64
    var kindRawValue: String
    var date: Date
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    var category: Category?
    var account: Account

    init(
        id: UUID = UUID(),
        amountCents: Int64,
        kind: TransactionKind,
        date: Date = .now,
        note: String? = nil,
        category: Category? = nil,
        account: Account,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.amountCents = amountCents
        self.kindRawValue = kind.rawValue
        self.date = date
        self.note = note
        self.category = category
        self.account = account
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }

    /// 金额（元）
    var amount: Decimal { Money.yuan(from: amountCents) }

    /// 对账户余额的贡献：收入为 +，支出为 -
    var balanceDeltaCents: Int64 {
        switch kind {
        case .expense: return -amountCents
        case .income: return amountCents
        }
    }
}
