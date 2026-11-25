import Foundation
import SwiftData

/// 月度预算。category 为 nil 时表示「全部预算」。
@Model
final class Budget {
    var id: UUID = UUID()
    /// 预算月份
    var year: Int = 0
    var month: Int = 0
    var amountCents: Int64 = 0
    /// 是否循环应用到之后的月份
    var isRecurring: Bool = false
    /// 所属账本；v1 固定为默认账本
    var ledgerID: UUID?
    /// 分类的跨设备身份；nil 表示全部预算
    var categoryCode: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// 软删除时间；nil 表示未删除
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        category: Category? = nil,
        ledgerID: UUID? = nil,
        amountCents: Int64,
        year: Int,
        month: Int,
        isRecurring: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.categoryCode = category?.code
        self.amountCents = amountCents
        self.year = year
        self.month = month
        self.isRecurring = isRecurring
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 分类对象：按 code 在本机解析
    @MainActor var category: Category? { EntityLookup.category(code: categoryCode, in: modelContext) }

    var amount: Decimal { Money.yuan(from: amountCents) }
}
