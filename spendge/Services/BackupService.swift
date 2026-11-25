import Foundation
import SwiftData

extension Notification.Name {
    /// 备份恢复完成：二级页和持有旧对象的表单需要立刻收起来
    static let dataRestored = Notification.Name("spendge.dataRestored")
}

/// 导出范围
enum BackupScope {
    case all
    case currentMonth
}

/// 备份校验失败：文案直接给用户看，不暴露解码细节。
enum BackupValidationError: LocalizedError {
    case unsupportedVersion
    case missingCoreData
    case duplicate(String)
    case unknownReference(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "备份文件版本不受支持"
        case .missingCoreData:
            return "备份文件缺少分类"
        case .duplicate(let label):
            return "备份文件里有重复的\(label)"
        case .unknownReference(let label):
            return "备份文件引用了不存在的\(label)"
        case .invalidValue(let label):
            return "备份文件里的\(label)不合法"
        }
    }
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
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil },
                                         sortBy: [SortDescriptor(\.date, order: .forward)])
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
        let ledgers = try context.fetch(FetchDescriptor<Ledger>(predicate: #Predicate { $0.deletedAt == nil }))
        let transactions = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil }))
        let confirmations = try context.fetch(FetchDescriptor<DayConfirmation>(predicate: #Predicate { $0.deletedAt == nil }))
        let goals = try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.deletedAt == nil }))
        let achievements = try context.fetch(FetchDescriptor<GoalAchievement>(predicate: #Predicate { $0.deletedAt == nil }))
        let trophies = try context.fetch(FetchDescriptor<TrophyUnlock>(predicate: #Predicate { $0.deletedAt == nil }))

        let file = BackupFile(
            version: BackupFile.currentVersion,
            exportedAt: .now,
            ledgers: ledgers.map(LedgerDTO.init),
            categories: [],
            transactions: transactions.map(TransactionDTO.init),
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

    func validateBackupData(_ data: Data) throws -> BackupFile {
        let file = normalize(try decodeBackup(data))
        try validate(file)
        return file
    }

    /// 旧版本导出过同 id 重复的记录；导入前先按身份键去重，不让整份备份失败。
    private func normalize(_ file: BackupFile) -> BackupFile {
        var copy = file
        copy.ledgers = file.ledgers.map { dedupe($0, key: { $0.id.uuidString }) }
        copy.categories = dedupe(file.categories, key: { $0.code ?? $0.id.uuidString })
        copy.transactions = dedupe(file.transactions, key: { $0.id.uuidString })
        copy.dayConfirmations = dedupe(file.dayConfirmations, key: {
            String(Int(calendar.startOfDay(for: $0.day).timeIntervalSince1970))
        })
        copy.budgets = file.budgets.map { dedupe($0, key: { $0.id.uuidString }) }
        copy.goals = file.goals.map { dedupe($0, key: { $0.id.uuidString }) }
        copy.achievements = file.achievements.map { dedupe($0, key: { $0.id.uuidString }) }
        copy.trophies = file.trophies.map { dedupe($0, key: { $0.trophyID }) }
        return copy
    }

    private func dedupe<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert(key($0)).inserted }
    }

    /// 只校验，不落库：所有检查通过后才允许清空
    func validate(_ file: BackupFile) throws {
        guard (1...BackupFile.currentVersion).contains(file.version) else {
            throw BackupValidationError.unsupportedVersion
        }

        try ensureUnique(file.categories.map(\.id), "分类")
        try ensureUnique(file.transactions.map(\.id), "账单")
        try ensureUnique((file.budgets ?? []).map(\.id), "预算")
        try ensureUnique((file.goals ?? []).map(\.id), "目标")
        try ensureUnique((file.achievements ?? []).map(\.id), "达成记录")

        for category in file.categories {
            guard TransactionKind(rawValue: category.kindRawValue) != nil,
                  CategoryDomain(rawValue: category.domainRawValue) != nil,
                  !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupValidationError.invalidValue("分类")
            }
        }

        let categoryIDs = Set(file.categories.map(\.id))
        let today = calendar.startOfDay(for: .now)

        let transactionIDs = Set(file.transactions.map(\.id))

        for txn in file.transactions {
            if let refundOfID = txn.refundOfID {
                // 退款：必须为负、且指向同文件里的原单
                guard txn.amountCents < 0 else {
                    throw BackupValidationError.invalidValue("退款金额")
                }
                guard transactionIDs.contains(refundOfID) else {
                    throw BackupValidationError.unknownReference("原账单")
                }
            } else {
                guard txn.amountCents > 0 else {
                    throw BackupValidationError.invalidValue("账单金额")
                }
            }
            guard TransactionKind(rawValue: txn.kindRawValue) != nil else {
                throw BackupValidationError.invalidValue("账单类型")
            }
            if let categoryID = txn.categoryID, !categoryIDs.contains(categoryID) {
                throw BackupValidationError.unknownReference("分类")
            }
            guard calendar.startOfDay(for: txn.date) <= today else {
                throw BackupValidationError.invalidValue("账单日期")
            }
        }

        for budget in file.budgets ?? [] {
            guard budget.amountCents >= 0,
                  (2000...2100).contains(budget.year), (1...12).contains(budget.month) else {
                throw BackupValidationError.invalidValue("预算")
            }
            if let categoryID = budget.categoryID, !categoryIDs.contains(categoryID) {
                throw BackupValidationError.unknownReference("分类")
            }
        }

        for goal in file.goals ?? [] {
            let title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw BackupValidationError.invalidValue("目标名称")
            }
            let kindRaw = goal.kindRawValue == "categorySum" ? GoalKind.budget.rawValue : goal.kindRawValue
            guard GoalPeriod(rawValue: goal.periodRawValue) != nil,
                  let kind = GoalKind(rawValue: kindRaw) else {
                throw BackupValidationError.invalidValue("目标类型")
            }
            switch kind {
            case .countLimit:
                guard (0...InputLimits.countTargetMax).contains(goal.targetValue) else {
                    throw BackupValidationError.invalidValue("目标数值")
                }
            case .budget:
                guard goal.targetValue >= 0 else {
                    throw BackupValidationError.invalidValue("目标数值")
                }
            case .shareCap:
                guard (0...100).contains(goal.targetValue) else {
                    throw BackupValidationError.invalidValue("目标数值")
                }
            }
        }

        for item in file.achievements ?? [] {
            guard item.targetValue > 0, item.currentValue >= 0,
                  GoalPeriod(rawValue: item.periodRawValue) != nil else {
                throw BackupValidationError.invalidValue("达成记录")
            }
        }

        var confirmedDays = Set<Date>()
        for item in file.dayConfirmations {
            guard confirmedDays.insert(calendar.startOfDay(for: item.day)).inserted else {
                throw BackupValidationError.duplicate("没花钱确认")
            }
        }

        var trophyIDs = Set<String>()
        for item in file.trophies ?? [] {
            // 目录以后可能改名或删项；未知奖杯恢复时会被跳过，不阻断整份备份
            guard TrophyID(rawValue: item.trophyID) != nil else { continue }
            guard trophyIDs.insert(item.trophyID).inserted else {
                throw BackupValidationError.duplicate("奖杯")
            }
        }
    }

    private func ensureUnique<T: Hashable>(_ values: [T], _ label: String) throws {
        guard Set(values).count == values.count else {
            throw BackupValidationError.duplicate(label)
        }
    }

    /// 覆盖恢复：先清空，再按备份重建；返回恢复的账单数
    @discardableResult
    func restore(from data: Data) throws -> Int {
        let file = normalize(try decodeBackup(data))
        try validate(file)

        // 清空（先删有引用的，再删被引用的）
        for item in try context.fetch(FetchDescriptor<GoalAchievement>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TrophyUnlock>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Goal>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DayConfirmation>()) { context.delete(item) }
        try context.save()

        // 账本：v1 备份没有，落到默认账本；v2 按 id 覆盖
        let defaultLedgerID = DefaultData.defaultLedgerID(context: context)
        if let ledgers = file.ledgers, !ledgers.isEmpty {
            let existing = (try? context.fetch(FetchDescriptor<Ledger>())) ?? []
            for dto in ledgers {
                if let ledger = existing.first(where: { $0.id == dto.id }) {
                    ledger.name = dto.name
                    ledger.kindRawValue = dto.kindRawValue
                    ledger.updatedAt = dto.updatedAt
                } else {
                    context.insert(Ledger(id: dto.id,
                                          name: dto.name,
                                          kind: LedgerKind(rawValue: dto.kindRawValue) ?? .personal,
                                          createdAt: dto.createdAt,
                                          updatedAt: dto.updatedAt))
                }
            }
        }


        var categoryMap: [UUID: CategoryInfo] = [:]
        for dto in file.categories {
            categoryMap[dto.id] = CategoryInfo(
                code: dto.code ?? dto.id.uuidString,
                name: dto.name,
                iconName: dto.iconName,
                colorHex: dto.colorHex,
                kindRawValue: dto.kindRawValue,
                domainRawValue: dto.domainRawValue,
                scope: dto.scope ?? "",
                sortOrder: dto.sortOrder,
                isArchived: dto.isArchived
            )
        }

        for dto in file.transactions {
            let txn = Transaction(
                id: dto.id,
                amountCents: dto.amountCents,
                kind: TransactionKind(rawValue: dto.kindRawValue) ?? .expense,
                date: dto.date,
                note: dto.note,
                category: dto.categoryID.flatMap { categoryMap[$0] },
                categoryCode: dto.categoryCode ?? dto.categoryID.flatMap { categoryMap[$0]?.code },
                ledgerID: dto.ledgerID ?? defaultLedgerID,
                refundOfID: dto.refundOfID,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
            context.insert(txn)
        }

        // 旧备份里的预算：并入 Goal（kind = budget，分类为空表示全部）
        for dto in file.budgets ?? [] {
            var comps = DateComponents()
            comps.year = dto.year
            comps.month = dto.month
            guard let start = calendar.date(from: comps) else { continue }
            let codes = dto.categoryID.flatMap { categoryMap[$0]?.code }.map { [$0] } ?? []
            context.insert(Goal(
                id: dto.id,
                title: codes.isEmpty ? "本月预算" : "分类预算",
                kind: .budget,
                categoryCodes: codes,
                period: .month,
                periodStart: start,
                ledgerID: dto.ledgerID ?? defaultLedgerID,
                targetValue: Int(dto.amountCents),
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            ))
        }

        for dto in file.dayConfirmations {
            context.insert(DayConfirmation(id: dto.id, day: dto.day,
                                            ledgerID: dto.ledgerID ?? defaultLedgerID,
                                            createdAt: dto.createdAt))
        }

        for dto in file.goals ?? [] {
            context.insert(Goal(
                id: dto.id,
                title: dto.title,
                kind: GoalKind(rawValue: dto.kindRawValue == "categorySum" ? GoalKind.budget.rawValue : dto.kindRawValue) ?? .countLimit,
                categoryCodes: dto.categoryCodes,
                period: GoalPeriod(rawValue: dto.periodRawValue) ?? .month,
                ledgerID: dto.ledgerID ?? defaultLedgerID,
                targetValue: dto.targetValue,
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
                kindRawValue: dto.kindRawValue ?? "",
                createdAt: dto.createdAt
            ))
        }

        for dto in file.trophies ?? [] {
            guard let id = TrophyID(rawValue: dto.trophyID) else { continue }
            context.insert(TrophyUnlock(trophyID: id, unlockedAt: dto.unlockedAt))
        }

        try context.save()
        DefaultData.dedupeRecords(context: context)
        return file.transactions.count
    }
}

// MARK: - 备份格式

struct BackupFile: Codable {
    static let currentVersion = 5

    var version: Int
    var exportedAt: Date
    /// v2 起有账本；v1 备份没有
    var ledgers: [LedgerDTO]?
    var categories: [CategoryDTO]
    var transactions: [TransactionDTO]
    /// 旧备份里的预算；v4 起并入 Goal，不再导出
    var budgets: [BudgetDTO]? = nil
    var dayConfirmations: [DayConfirmationDTO]
    /// 旧备份里没有这两项，解码时允许为空
    var goals: [GoalDTO]?
    var achievements: [GoalAchievementDTO]?
    /// 奖杯解锁：旧备份里没有
    var trophies: [TrophyUnlockDTO]?
}

struct LedgerDTO: Codable {
    var id: UUID
    var name: String
    var kindRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(_ ledger: Ledger) {
        id = ledger.id
        name = ledger.name
        kindRawValue = ledger.kindRawValue
        createdAt = ledger.createdAt
        updatedAt = ledger.updatedAt
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

}

struct TransactionDTO: Codable {
    var id: UUID
    var ledgerID: UUID?
    var amountCents: Int64
    var kindRawValue: String
    var date: Date
    var note: String?
    /// v4 起直接存 code，分类缺失时也能还原归属
    var categoryCode: String?
    var categoryID: UUID?
    /// 退款记录指回原单；普通账单为空
    var refundOfID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ txn: Transaction) {
        id = txn.id
        ledgerID = txn.ledgerID
        amountCents = txn.amountCents
        kindRawValue = txn.kindRawValue
        date = txn.date
        note = txn.note
        categoryCode = txn.categoryCode
        categoryID = nil // 分类不再有行 ID，优先使用 categoryCode
        refundOfID = txn.refundOfID
        createdAt = txn.createdAt
        updatedAt = txn.updatedAt
    }
}

struct BudgetDTO: Codable {
    var id: UUID
    var ledgerID: UUID?
    var categoryID: UUID?
    var amountCents: Int64
    var year: Int
    var month: Int
    var createdAt: Date
    var updatedAt: Date

}

struct GoalDTO: Codable {
    var id: UUID
    var ledgerID: UUID?
    var title: String
    var kindRawValue: String
    var categoryCodes: [String]
    var periodRawValue: String
    var targetValue: Int
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ goal: Goal) {
        id = goal.id
        ledgerID = goal.ledgerID
        title = goal.title
        kindRawValue = goal.kindRawValue
        categoryCodes = goal.categoryCodes
        periodRawValue = goal.periodRawValue
        targetValue = goal.targetValue
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
    /// v3 及更早没有这个字段
    var kindRawValue: String?
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
        kindRawValue = item.kindRawValue
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
    var ledgerID: UUID?
    var day: Date
    var createdAt: Date

    init(_ item: DayConfirmation) {
        id = item.id
        ledgerID = item.ledgerID
        day = item.day
        createdAt = item.createdAt
    }
}
