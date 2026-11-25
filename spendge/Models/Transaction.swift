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
    /// 来源：手动 / 补记。
    var sourceRawValue: String = TransactionSource.manual.rawValue
    /// 内部横切标签，用户不可见，由推断填充。
    var dietModeRawValue: String?
    var sceneRawValue: String?
    var natureRawValue: String?

    /// 分类 / 账户的跨设备身份：一律按 code 匹配，关系只在本机解析
    var categoryCode: String?
    var accountCode: String?

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
        source: TransactionSource = .manual,
        category: Category? = nil,
        account: Account? = nil,
        refundOfID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.amountCents = amountCents
        self.kindRawValue = kind.rawValue
        self.date = date
        self.note = note
        self.sourceRawValue = source.rawValue
        self.categoryCode = category?.code
        self.accountCode = account?.code
        self.refundOfID = refundOfID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 分类 / 账户对象：按 code 在本机解析
    @MainActor var category: Category? { EntityLookup.category(code: categoryCode, in: modelContext) }
    @MainActor var account: Account? { EntityLookup.account(code: accountCode, in: modelContext) }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRawValue) ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }

    var dietMode: DietMode? {
        get { dietModeRawValue.flatMap(DietMode.init(rawValue:)) }
        set { dietModeRawValue = newValue?.rawValue }
    }

    var spendScene: SpendScene? {
        get { sceneRawValue.flatMap(SpendScene.init(rawValue:)) }
        set { sceneRawValue = newValue?.rawValue }
    }

    var spendNature: SpendNature? {
        get { natureRawValue.flatMap(SpendNature.init(rawValue:)) }
        set { natureRawValue = newValue?.rawValue }
    }

    /// 金额（元）
    var amount: Decimal { Money.yuan(from: amountCents) }

    /// 列表顺序：新的在上。时间相同的（同一天连续记多笔）按创建时间倒序
    static func newestFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.createdAt > rhs.createdAt
    }

    /// 对账户余额的贡献：收入为 +，支出为 -
    var balanceDeltaCents: Int64 {
        switch kind {
        case .expense: return -amountCents
        case .income: return amountCents
        }
    }
}
