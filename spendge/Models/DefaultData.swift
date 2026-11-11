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
        .init(code: .takeout, name: "点外卖", iconName: "takeoutbag.and.cup.and.straw.fill",
              colorHex: "#FB923C", kind: .expense, domain: .food, sortOrder: 1),
        .init(code: .grocery, name: "买菜食材", iconName: "cart.fill",
              colorHex: "#F97316", kind: .expense, domain: .food, sortOrder: 2),
        .init(code: .drink, name: "奶咖茶饮", iconName: "cup.and.saucer.fill",
              colorHex: "#B45309", kind: .expense, domain: .food, sortOrder: 3),
        .init(code: .snack, name: "零食水果", iconName: "carrot.fill",
              colorHex: "#FBBF24", kind: .expense, domain: .food, sortOrder: 4),
        .init(code: .outing, name: "出行游玩", iconName: "figure.walk",
              colorHex: "#3B82F6", kind: .expense, domain: .transport, sortOrder: 5),
        .init(code: .dineout, name: "下馆子", iconName: "fork.knife",
              colorHex: "#F59E0B", kind: .expense, domain: .food, sortOrder: 6),
        .init(code: .daily, name: "生活日用", iconName: "shippingbox.fill",
              colorHex: "#A855F7", kind: .expense, domain: .goods, sortOrder: 7),
        .init(code: .housing, name: "房租水电", iconName: "house.fill",
              colorHex: "#14B8A6", kind: .expense, domain: .housing, sortOrder: 8),
        .init(code: .wear, name: "衣帽鞋袜", iconName: "tshirt.fill",
              colorHex: "#EC4899", kind: .expense, domain: .goods, sortOrder: 9),
        .init(code: .subscription, name: "订阅话费", iconName: "creditcard.fill",
              colorHex: "#0EA5E9", kind: .expense, domain: .other, sortOrder: 10),
        .init(code: .social, name: "人情往来", iconName: "gift.fill",
              colorHex: "#EF4444", kind: .expense, domain: .social, sortOrder: 11),
        .init(code: .health, name: "医疗保健", iconName: "cross.case.fill",
              colorHex: "#10B981", kind: .expense, domain: .health, sortOrder: 12),
        .init(code: .gear, name: "装备器材", iconName: "wrench.and.screwdriver.fill",
              colorHex: "#DB2777", kind: .expense, domain: .goods, sortOrder: 13),
        .init(code: .appliance, name: "家具家电", iconName: "sofa.fill",
              colorHex: "#C026D3", kind: .expense, domain: .housing, sortOrder: 14),
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

    /// 分类体系改版：把旧分类迁到新分类上，**保留已有账单**。
    /// 与结构变更不同，这里不删库——账单归属是用户数据。
    static func migrateCategoriesIfNeeded(context: ModelContext) {
        let key = "spendge.categoryMigration"
        guard UserDefaults.standard.integer(forKey: key) < 8 else { return }

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        guard !categories.isEmpty else {
            UserDefaults.standard.set(8, forKey: key)
            return
        }

        func category(_ code: String) -> Category? {
            categories.first { $0.code == code }
        }

        // 旧的「买东西」并入「用的」
        category("shopping")?.code = CategoryCode.gear.rawValue

        // 交通 + 娱乐 → 出行游玩
        if let outing = category("outing") ?? category("transport") {
            outing.code = CategoryCode.outing.rawValue
            outing.name = "出行游玩"
            outing.domain = .transport
            outing.sortOrder = 6
            if let fun = category("fun") {
                for txn in fun.transactions {
                    txn.category = outing
                }
                context.delete(fun)
            }
        }

        // 按种子校正名称、图标、领域与排序（当前还不支持用户改名，所以直接覆盖）
        for seed in expenseCategorySeeds + incomeCategorySeeds {
            guard let existing = category(seed.code.rawValue) else { continue }
            existing.name = seed.name
            existing.iconName = seed.iconName
            existing.colorHex = seed.colorHex
            existing.domain = seed.domain
            existing.sortOrder = seed.sortOrder
        }

        // 补充新增分类
        let existingCodes = Set(categories.compactMap(\.code))
        for seed in expenseCategorySeeds + incomeCategorySeeds where !existingCodes.contains(seed.code.rawValue) {
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

        try? context.save()
        UserDefaults.standard.set(8, forKey: key)
    }

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