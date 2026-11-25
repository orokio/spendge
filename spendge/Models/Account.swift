import Foundation
import SwiftData

/// 账户：现金、银行卡、电子钱包等。删除账户会级联删除其下所有账单。
@Model
final class Account {
    var id: UUID = UUID()
    /// 跨设备身份：账单只存 code，不依赖行 ID
    var code: String = ""
    var name: String = ""
    var iconName: String = "wallet.pass.fill"
    var colorHex: String = "#3B82F6"
    var kindRawValue: String = AccountKind.other.rawValue
    /// 期初余额（分）
    var initialBalanceCents: Int64 = 0
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now


    init(
        id: UUID = UUID(),
        code: String = "",
        name: String,
        iconName: String = "wallet.pass.fill",
        colorHex: String = "#3B82F6",
        kind: AccountKind = .other,
        initialBalanceCents: Int64 = 0,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.kindRawValue = kind.rawValue
        self.initialBalanceCents = initialBalanceCents
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    /// 期初余额（元），展示用
    var initialBalance: Decimal { Money.yuan(from: initialBalanceCents) }
}
