import Foundation
import SwiftData

/// 首次启动写入的预置数据：默认分类 + 默认「现金」账户。
enum DefaultData {
    struct CategorySeed {
        let name: String
        let iconName: String
        let colorHex: String
        let kind: TransactionKind
        let sortOrder: Int
    }

    static let expenseCategorySeeds: [CategorySeed] = [
        .init(name: "餐饮", iconName: "fork.knife", colorHex: "#FF7A45", kind: .expense, sortOrder: 1),
        .init(name: "交通", iconName: "car.fill", colorHex: "#3B82F6", kind: .expense, sortOrder: 2),
        .init(name: "购物", iconName: "bag.fill", colorHex: "#EC4899", kind: .expense, sortOrder: 3),
        .init(name: "居住", iconName: "house.fill", colorHex: "#14B8A6", kind: .expense, sortOrder: 4),
        .init(name: "娱乐", iconName: "gamecontroller.fill", colorHex: "#8B5CF6", kind: .expense, sortOrder: 5),
        .init(name: "医疗", iconName: "cross.case.fill", colorHex: "#EF4444", kind: .expense, sortOrder: 6),
        .init(name: "教育", iconName: "book.fill", colorHex: "#6366F1", kind: .expense, sortOrder: 7),
        .init(name: "旅行", iconName: "airplane", colorHex: "#06B6D4", kind: .expense, sortOrder: 8),
        .init(name: "人情", iconName: "gift.fill", colorHex: "#F59E0B", kind: .expense, sortOrder: 9),
        .init(name: "其他", iconName: "ellipsis.circle", colorHex: "#9CA3AF", kind: .expense, sortOrder: 99),
    ]

    static let incomeCategorySeeds: [CategorySeed] = [
        .init(name: "工资", iconName: "banknote.fill", colorHex: "#10B981", kind: .income, sortOrder: 1),
        .init(name: "奖金", iconName: "party.popper.fill", colorHex: "#FACC15", kind: .income, sortOrder: 2),
        .init(name: "理财", iconName: "chart.line.uptrend.xyaxis", colorHex: "#22C55E", kind: .income, sortOrder: 3),
        .init(name: "其他收入", iconName: "plus.circle", colorHex: "#6B7280", kind: .income, sortOrder: 99),
    ]

    /// 幂等：已有数据时不重复写入。
    static func seedIfNeeded(context: ModelContext) {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        if categoryCount == 0 {
            for seed in expenseCategorySeeds + incomeCategorySeeds {
                let order = seed.sortOrder + (seed.kind == .income ? 100 : 0)
                context.insert(Category(
                    name: seed.name,
                    iconName: seed.iconName,
                    colorHex: seed.colorHex,
                    kind: seed.kind,
                    sortOrder: order,
                    isSystem: true
                ))
            }
        }

        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        if accountCount == 0 {
            context.insert(Account(
                name: "现金",
                iconName: "banknote",
                colorHex: "#10B981",
                kind: .cash,
                sortOrder: 1
            ))
        }

        try? context.save()
    }
}
