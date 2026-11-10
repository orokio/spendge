import Foundation
import SwiftData

/// 分类：支出 / 收入。删除分类不会删除账单，账单的分类会被置空。
@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    /// 稳定标识（CategoryCode 的 rawValue）。代码里一律按 code 匹配，不按 name。
    var code: String?
    var iconName: String
    var colorHex: String
    var kindRawValue: String
    /// 内部聚合领域，用户不可见。
    var domainRawValue: String = CategoryDomain.other.rawValue
    var sortOrder: Int
    /// 系统预置分类不允许删除（可改名、可归档）
    var isSystem: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget] = []

    init(
        id: UUID = UUID(),
        name: String,
        code: String? = nil,
        iconName: String = "tag.fill",
        colorHex: String = "#9CA3AF",
        kind: TransactionKind,
        domain: CategoryDomain = .other,
        sortOrder: Int = 99,
        isSystem: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.iconName = iconName
        self.colorHex = colorHex
        self.kindRawValue = kind.rawValue
        self.domainRawValue = domain.rawValue
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }

    var domain: CategoryDomain {
        get { CategoryDomain(rawValue: domainRawValue) ?? .other }
        set { domainRawValue = newValue.rawValue }
    }

    var categoryCode: CategoryCode? {
        code.flatMap(CategoryCode.init(rawValue:))
    }
}
