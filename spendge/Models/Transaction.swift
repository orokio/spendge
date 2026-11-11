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
    /// 金额是否为估计值（档位选择产生）。参与求和，但叙事与覆盖率需要区分。
    var isApproximateAmount: Bool = false
    /// 来源：手动 / 补记。
    var sourceRawValue: String = TransactionSource.manual.rawValue
    /// 内部横切标签，用户不可见，由推断填充。
    var dietModeRawValue: String?
    var sceneRawValue: String?
    var natureRawValue: String?

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
        isApproximateAmount: Bool = false,
        source: TransactionSource = .manual,
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
        self.isApproximateAmount = isApproximateAmount
        self.sourceRawValue = source.rawValue
        self.category = category
        self.account = account
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

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

    /// 对账户余额的贡献：收入为 +，支出为 -
    var balanceDeltaCents: Int64 {
        switch kind {
        case .expense: return -amountCents
        case .income: return amountCents
        }
    }
}
