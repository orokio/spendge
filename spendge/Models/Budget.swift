import Foundation
import SwiftData

/// 月度预算。category 为 nil 时表示「全部预算」。
@Model
final class Budget {
    @Attribute(.unique) var id: UUID
    /// 预算月份
    var year: Int
    var month: Int
    var amountCents: Int64
    var category: Category?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        category: Category? = nil,
        amountCents: Int64,
        year: Int,
        month: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.category = category
        self.amountCents = amountCents
        self.year = year
        self.month = month
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var amount: Decimal { Money.yuan(from: amountCents) }
}
