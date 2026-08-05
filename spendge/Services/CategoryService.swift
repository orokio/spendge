import Foundation
import SwiftData

/// 分类业务逻辑：查询、增改、归档、删除。
@MainActor
final class CategoryService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 分类列表，按类型、排序号、名称排列。
    func categories(kind: TransactionKind? = nil, includeArchived: Bool = false) throws -> [Category] {
        var predicate: Predicate<Category>?
        switch (kind, includeArchived) {
        case let (kind?, false):
            predicate = #Predicate { $0.kindRawValue == kind.rawValue && $0.isArchived == false }
        case let (kind?, true):
            predicate = #Predicate { $0.kindRawValue == kind.rawValue }
        case (nil, false):
            predicate = #Predicate { $0.isArchived == false }
        case (nil, true):
            break
        }

        var descriptor = FetchDescriptor<Category>(predicate: predicate)
        descriptor.sortBy = [
            SortDescriptor(\.kindRawValue),
            SortDescriptor(\.sortOrder),
            SortDescriptor(\.name),
        ]
        return try context.fetch(descriptor)
    }

    @discardableResult
    func create(
        name: String,
        iconName: String = "tag.fill",
        colorHex: String = "#9CA3AF",
        kind: TransactionKind,
        sortOrder: Int = 99
    ) throws -> Category {
        let category = Category(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            kind: kind,
            sortOrder: sortOrder,
            isSystem: false
        )
        context.insert(category)
        try context.save()
        return category
    }

    func update(
        _ category: Category,
        name: String? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        sortOrder: Int? = nil
    ) throws {
        if let name { category.name = name }
        if let iconName { category.iconName = iconName }
        if let colorHex { category.colorHex = colorHex }
        if let sortOrder { category.sortOrder = sortOrder }
        category.updatedAt = .now
        try context.save()
    }

    /// 归档：列表不再展示，历史账单保留。
    func archive(_ category: Category) throws {
        category.isArchived = true
        category.updatedAt = .now
        try context.save()
    }

    /// 删除：系统预置分类不允许删除；删除后历史账单的分类置空。
    func delete(_ category: Category) throws {
        guard !category.isSystem else { throw SpendgeError.cannotDeleteSystemCategory }
        context.delete(category)
        try context.save()
    }
}
