import Foundation
import SwiftData

/// 首次启动写入的预置数据：11 个动作分类 + 4 个收入分类 + 默认「现金」账户。
///
/// 分类是用户可见的**动作**（我做了什么），内部领域（domain）用户不可见。
/// 代码里一律按 code 匹配，不按 name —— 改名不应影响任何逻辑。
enum DefaultData {
    struct CategorySeed {
        let code: CategoryCode
        let name: String
        let iconName: String
        let colorHex: String
        let kind: TransactionKind
        let domain: CategoryDomain
        let sortOrder: Int
    }

    static let expenseCategorySeeds: [CategorySeed] = [
        .init(code: .grocery, name: "买菜做饭", iconName: "cart.fill",
              colorHex: "#F97316", kind: .expense, domain: .food, sortOrder: 1),
        .init(code: .takeout, name: "点外卖", iconName: "takeoutbag.and.cup.and.straw.fill",
              colorHex: "#FB923C", kind: .expense, domain: .food, sortOrder: 2),
        .init(code: .dineout, name: "下馆子", iconName: "fork.knife",
              colorHex: "#F59E0B", kind: .expense, domain: .food, sortOrder: 3),
        .init(code: .drink, name: "咖啡奶茶", iconName: "cup.and.saucer.fill",
              colorHex: "#B45309", kind: .expense, domain: .food, sortOrder: 4),
        .init(code: .transport, name: "出行", iconName: "car.fill",
              colorHex: "#3B82F6", kind: .expense, domain: .transport, sortOrder: 5),
        .init(code: .housing, name: "住", iconName: "house.fill",
              colorHex: "#14B8A6", kind: .expense, domain: .housing, sortOrder: 6),
        .init(code: .shopping, name: "买东西", iconName: "bag.fill",
              colorHex: "#EC4899", kind: .expense, domain: .goods, sortOrder: 7),
        .init(code: .fun, name: "玩", iconName: "gamecontroller.fill",
              colorHex: "#8B5CF6", kind: .expense, domain: .play, sortOrder: 8),
        .init(code: .social, name: "人情", iconName: "gift.fill",
              colorHex: "#EF4444", kind: .expense, domain: .social, sortOrder: 9),
        .init(code: .health, name: "健康", iconName: "cross.case.fill",
              colorHex: "#10B981", kind: .expense, domain: .health, sortOrder: 10),
        .init(code: .otherExpense, name: "其他", iconName: "ellipsis.circle",
              colorHex: "#9CA3AF", kind: .expense, domain: .other, sortOrder: 99),
    ]

    static let incomeCategorySeeds: [CategorySeed] = [
        .init(code: .salary, name: "工资", iconName: "banknote.fill",
              colorHex: "#10B981", kind: .income, domain: .other, sortOrder: 101),
        .init(code: .sideJob, name: "兼职", iconName: "briefcase.fill",
              colorHex: "#22C55E", kind: .income, domain: .other, sortOrder: 102),
        .init(code: .invest, name: "理财", iconName: "chart.line.uptrend.xyaxis",
              colorHex: "#84CC16", kind: .income, domain: .other, sortOrder: 103),
        .init(code: .otherIncome, name: "其他收入", iconName: "plus.circle",
              colorHex: "#6B7280", kind: .income, domain: .other, sortOrder: 199),
    ]

    /// 幂等：已有数据时不重复写入。
    static func seedIfNeeded(context: ModelContext) {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        if categoryCount == 0 {
            for seed in expenseCategorySeeds + incomeCategorySeeds {
                context.insert(Category(
                    name: seed.name,
                    code: seed.code.rawValue,
                    iconName: seed.iconName,
                    colorHex: seed.colorHex,
                    kind: seed.kind,
                    domain: seed.domain,
                    sortOrder: seed.sortOrder,
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
