import Foundation
import SwiftData

/// 导出范围
enum BackupScope {
    case all
    case currentMonth
}

/// 导出与恢复：CSV 给人看，JSON 给机器搬。
@MainActor
final class BackupService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - CSV

    /// 账单 CSV：UTF-8 BOM，Excel 直接打开不乱码
    func csv(scope: BackupScope, monthOf date: Date = .now) throws -> String {
        let all = try context.fetch(
            FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )
        let rows: [Transaction]
        if case .currentMonth = scope {
            rows = all.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
        } else {
            rows = all
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var text = "\u{FEFF}日期,类型,分类,金额,备注\n"
        for txn in rows {
            let kind = txn.kind == .expense ? "支出" : "收入"
            let category = txn.category?.name ?? "未分类"
            let amount = String(format: "%.2f", Double(txn.amountCents) / 100)
            let note = txn.note ?? ""
            text += [
                formatter.string(from: txn.date),
                kind,
                category,
                amount,
                note,
            ].map(Self.csvField).joined(separator: ",") + "\n"
        }
        return text
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - JSON 备份

    func backupData() throws -> Data {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let confirmations = try context.fetch(FetchDescriptor<DayConfirmation>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let achievements = try context.fetch(FetchDescriptor<GoalAchievement>())
        let trophies = try context.fetch(FetchDescriptor<TrophyUnlock>())

        let file = BackupFile(
            version: BackupFile.currentVersion,
            exportedAt: .now,
            accounts: accounts.map(AccountDTO.init),
            categories: categories.map(CategoryDTO.init),
            transactions: transactions.map(TransactionDTO.init),
            budgets: budgets.map(BudgetDTO.init),
            dayConfirmations: confirmations.map(DayConfirmationDTO.init),
            goals: goals.map(GoalDTO.init),
            achievements: achievements.map(GoalAchievementDTO.init),
            trophies: trophies.map(TrophyUnlockDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    func decodeBackup(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// 覆盖恢复：先清空，再按备份重建；返回恢复的账单数
    @discardableResult
    func restore(from data: Data) throws -> Int {
        let file = try decodeBackup(data)

        // 清空（先删有引用的，再删被引用的）
        for item in try context.fetch(FetchDescriptor<GoalAchievement>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TrophyUnlock>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Goal>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Budget>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DayConfirmation>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Category>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Account>()) { context.delete(item) }
        try context.save()

        var accountMap: [UUID: Account] = [:]
        for dto in file.accounts {
            let account = Account(
                id: dto.id,
                name: dto.name,
                iconName: dto.iconName,
                colorHex: dto.colorHex,
                kind: AccountKind(rawValue: dto.kindRawValue) ?? .other,
                initialBalanceCents: dto.initialBalanceCents,
                sortOrder: dto.sortOrder,
                isArchived: dto.isArchived,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
            context.insert(account)
            accountMap[dto.id] = account
        }

        // 没有账户的旧备份：补一个默认账户
        if accountMap.isEmpty {
            let account = Account(name: "默认账户", sortOrder: 0)
            context.insert(account)
            accountMap[account.id] = account
        }
        let fallbackAccount = accountMap.values.first!

        var categoryMap: [UUID: Category] = [:]
        for dto in file.categories {
            let category = Category(
                id: dto.id,
                name: dto.name,
                code: dto.code,
                iconName: dto.iconName,
                colorHex: dto.colorHex,
                kind: TransactionKind(rawValue: dto.kindRawValue) ?? .expense,
                domain: CategoryDomain(rawValue: dto.domainRawValue) ?? .other,
                scope: dto.scope ?? "",
                sortOrder: dto.sortOrder,
                isSystem: dto.isSystem,
                isArchived: dto.isArchived,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
            context.insert(category)
            categoryMap[dto.id] = category
        }

        for dto in file.transactions {
            let txn = Transaction(
                id: dto.id,
                amountCents: dto.amountCents,
                kind: TransactionKind(rawValue: dto.kindRawValue) ?? .expense,
                date: dto.date,
                note: dto.note,
                source: TransactionSource(rawValue: dto.sourceRawValue) ?? .manual,
                category: dto.categoryID.flatMap { categoryMap[$0] },
                account: accountMap[dto.accountID] ?? fallbackAccount,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
            context.insert(txn)
        }

        for dto in file.budgets {
            let budget = Budget(
                id: dto.id,
                category: dto.categoryID.flatMap { categoryMap[$0] },
                amountCents: dto.amountCents,
                year: dto.year,
                month: dto.month,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
            context.insert(budget)
        }

        for dto in file.dayConfirmations {
            context.insert(DayConfirmation(id: dto.id, day: dto.day, createdAt: dto.createdAt))
        }

        for dto in file.goals ?? [] {
            context.insert(Goal(
                id: dto.id,
                title: dto.title,
                kind: GoalKind(rawValue: dto.kindRawValue) ?? .countLimit,
                categoryCodes: dto.categoryCodes,
                period: GoalPeriod(rawValue: dto.periodRawValue) ?? .month,
                targetValue: dto.targetValue,
                basis: GoalBasis(rawValue: dto.basisRawValue) ?? .fixed,
                isActive: dto.isActive,
                sortOrder: dto.sortOrder,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            ))
        }

        for dto in file.achievements ?? [] {
            let unit: GoalProgress.Unit
            switch dto.unitRawValue {
            case "cents": unit = .cents
            case "percent": unit = .percent
            default: unit = .count
            }
            context.insert(GoalAchievement(
                id: dto.id,
                goalID: dto.goalID,
                title: dto.title,
                period: GoalPeriod(rawValue: dto.periodRawValue) ?? .month,
                periodStart: dto.periodStart,
                achieved: dto.achieved,
                currentValue: dto.currentValue,
                targetValue: dto.targetValue,
                unit: unit,
                createdAt: dto.createdAt
            ))
        }

        for dto in file.trophies ?? [] {
            guard let id = TrophyID(rawValue: dto.trophyID) else { continue }
            context.insert(TrophyUnlock(trophyID: id, unlockedAt: dto.unlockedAt))
        }

        try context.save()
        return file.transactions.count
    }
}

// MARK: - 备份格式

struct BackupFile: Codable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var accounts: [AccountDTO]
    var categories: [CategoryDTO]
    var transactions: [TransactionDTO]
    var budgets: [BudgetDTO]
    var dayConfirmations: [DayConfirmationDTO]
    /// 旧备份里没有这两项，解码时允许为空
    var goals: [GoalDTO]?
    var achievements: [GoalAchievementDTO]?
    /// 奖杯解锁：旧备份里没有
    var trophies: [TrophyUnlockDTO]?
}

struct AccountDTO: Codable {
    var id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var kindRawValue: String
    var initialBalanceCents: Int64
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ account: Account) {
        id = account.id
        name = account.name
        iconName = account.iconName
        colorHex = account.colorHex
        kindRawValue = account.kindRawValue
        initialBalanceCents = account.initialBalanceCents
        sortOrder = account.sortOrder
        isArchived = account.isArchived
        createdAt = account.createdAt
        updatedAt = account.updatedAt
    }
}

struct CategoryDTO: Codable {
    var id: UUID
    var name: String
    var code: String?
    var iconName: String
    var colorHex: String
    var kindRawValue: String
    var domainRawValue: String
    /// 旧备份里没有这个字段
    var scope: String?
    var sortOrder: Int
    var isSystem: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ category: Category) {
        id = category.id
        name = category.name
        code = category.code
        iconName = category.iconName
        colorHex = category.colorHex
        kindRawValue = category.kindRawValue
        domainRawValue = category.domainRawValue
        scope = category.scope
        sortOrder = category.sortOrder
        isSystem = category.isSystem
        isArchived = category.isArchived
        createdAt = category.createdAt
        updatedAt = category.updatedAt
    }
}

struct TransactionDTO: Codable {
    var id: UUID
    var amountCents: Int64
    var kindRawValue: String
    var date: Date
    var note: String?
    var sourceRawValue: String
    var categoryID: UUID?
    var accountID: UUID
    var createdAt: Date
    var updatedAt: Date

    init(_ txn: Transaction) {
        id = txn.id
        amountCents = txn.amountCents
        kindRawValue = txn.kindRawValue
        date = txn.date
        note = txn.note
        sourceRawValue = txn.sourceRawValue
        categoryID = txn.category?.id
        accountID = txn.account.id
        createdAt = txn.createdAt
        updatedAt = txn.updatedAt
    }
}

struct BudgetDTO: Codable {
    var id: UUID
    var categoryID: UUID?
    var amountCents: Int64
    var year: Int
    var month: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ budget: Budget) {
        id = budget.id
        categoryID = budget.category?.id
        amountCents = budget.amountCents
        year = budget.year
        month = budget.month
        createdAt = budget.createdAt
        updatedAt = budget.updatedAt
    }
}

struct GoalDTO: Codable {
    var id: UUID
    var title: String
    var kindRawValue: String
    var categoryCodes: [String]
    var periodRawValue: String
    var targetValue: Int
    var basisRawValue: String
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ goal: Goal) {
        id = goal.id
        title = goal.title
        kindRawValue = goal.kindRawValue
        categoryCodes = goal.categoryCodes
        periodRawValue = goal.periodRawValue
        targetValue = goal.targetValue
        basisRawValue = goal.basisRawValue
        isActive = goal.isActive
        sortOrder = goal.sortOrder
        createdAt = goal.createdAt
        updatedAt = goal.updatedAt
    }
}

struct GoalAchievementDTO: Codable {
    var id: UUID
    var goalID: UUID
    var title: String
    var periodRawValue: String
    var periodStart: Date
    var achieved: Bool
    var currentValue: Int
    var targetValue: Int
    var unitRawValue: String
    var createdAt: Date

    init(_ item: GoalAchievement) {
        id = item.id
        goalID = item.goalID
        title = item.title
        periodRawValue = item.periodRawValue
        periodStart = item.periodStart
        achieved = item.achieved
        currentValue = item.currentValue
        targetValue = item.targetValue
        unitRawValue = item.unitRawValue
        createdAt = item.createdAt
    }
}

struct TrophyUnlockDTO: Codable {
    var trophyID: String
    var unlockedAt: Date

    init(_ item: TrophyUnlock) {
        trophyID = item.trophyID
        unlockedAt = item.unlockedAt
    }
}

struct DayConfirmationDTO: Codable {
    var id: UUID
    var day: Date
    var createdAt: Date

    init(_ item: DayConfirmation) {
        id = item.id
        day = item.day
        createdAt = item.createdAt
    }
}
