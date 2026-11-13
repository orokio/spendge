import Foundation
import SwiftData

/// 单分类月度汇总条目（面向 UI 的快照，不直接暴露模型）。
struct CategorySummary: Identifiable, Equatable {
    let categoryID: UUID
    let categoryName: String
    let iconName: String
    let colorHex: String
    let amountCents: Int64

    var id: UUID { categoryID }
    var amount: Decimal { Money.yuan(from: amountCents) }
}

/// 月度汇总快照。
struct MonthlySummary: Equatable {
    let year: Int
    let month: Int
    var totalExpenseCents: Int64 = 0
    var totalIncomeCents: Int64 = 0
    var expenseByCategory: [CategorySummary] = []
    var incomeByCategory: [CategorySummary] = []

    var netCents: Int64 { totalIncomeCents - totalExpenseCents }
    var totalExpense: Decimal { Money.yuan(from: totalExpenseCents) }
    var totalIncome: Decimal { Money.yuan(from: totalIncomeCents) }
}

/// 月度数据覆盖率。覆盖率不是加分项，是回看的前提。
struct MonthCoverage: Equatable {
    let daysWithRecords: Int
    let daysConfirmedNoSpend: Int
    let coveredDays: Int
    let daysInMonth: Int
    /// 已经过去的天数（当月 = 今天几号；过去的月份 = 整月）。
    /// 覆盖率按它做分母，否则月初每个人看起来都像没记账。
    let elapsedDays: Int

    var ratio: Double {
        guard elapsedDays > 0 else { return 0 }
        return Double(coveredDays) / Double(elapsedDays)
    }
}

/// 账单业务逻辑：记账、改账、删账、查询、月度统计、余额计算。
@MainActor
final class TransactionService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - 记账

    @discardableResult
    func add(
        amountCents: Int64,
        kind: TransactionKind,
        date: Date = .now,
        note: String? = nil,
        source: TransactionSource = .manual,
        category: Category? = nil,
        account: Account
    ) throws -> Transaction {
        guard amountCents > 0 else { throw SpendgeError.invalidAmount }
        let transaction = Transaction(
            amountCents: amountCents,
            kind: kind,
            date: date,
            note: note,
            source: source,
            category: category,
            account: account
        )
        context.insert(transaction)
        try context.save()
        return transaction
    }

    /// 改一笔：只更新传入的字段。
    func update(
        _ transaction: Transaction,
        amountCents: Int64? = nil,
        kind: TransactionKind? = nil,
        date: Date? = nil,
        note: String? = nil,
        category: Category? = nil,
        account: Account? = nil
    ) throws {
        if let amountCents {
            guard amountCents > 0 else { throw SpendgeError.invalidAmount }
            transaction.amountCents = amountCents
        }
        if let kind { transaction.kind = kind }
        if let date { transaction.date = date }
        if let note { transaction.note = note }
        if let category { transaction.category = category }
        if let account { transaction.account = account }
        transaction.updatedAt = .now
        try context.save()
    }

    /// 删一笔。
    func delete(_ transaction: Transaction) throws {
        context.delete(transaction)
        try context.save()
    }

    // MARK: - 查询

    /// 时间区间（半开区间 [start, end)）内的账单，按时间倒序。
    func transactions(from start: Date? = nil, to end: Date? = nil) throws -> [Transaction] {
        var predicate: Predicate<Transaction>?
        if let start, let end {
            predicate = #Predicate { $0.date >= start && $0.date < end }
        } else if let start {
            predicate = #Predicate { $0.date >= start }
        } else if let end {
            predicate = #Predicate { $0.date < end }
        }

        var descriptor = FetchDescriptor<Transaction>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.date, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// 某账户的全部账单。
    func transactions(account: Account) throws -> [Transaction] {
        let accountID = account.id
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account.id == accountID }
        )
        descriptor.sortBy = [SortDescriptor(\.date, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// 某分类的全部账单。
    func transactions(category: Category) throws -> [Transaction] {
        let categoryID = category.id
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.category?.id == categoryID }
        )
        descriptor.sortBy = [SortDescriptor(\.date, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// 按备注关键词搜索。
    func search(noteContaining keyword: String) throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.note?.localizedStandardContains(keyword) == true }
        )
        descriptor.sortBy = [SortDescriptor(\.date, order: .reverse)]
        return try context.fetch(descriptor)
    }

    // MARK: - 金额建议

    /// 最近用过的不同金额（全分类共享），用于键盘上方的快填芯片。
    /// 不做统计推断：只记忆用户真的输过的数字，最多 limit 个，按时间倒序去重。
    func recentAmounts(limit: Int = 3, sampleLimit: Int = 40) throws -> [Int64] {
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = sampleLimit
        var result: [Int64] = []
        for amount in try context.fetch(descriptor).map(\.amountCents) {
            guard amount > 0, !result.contains(amount) else { continue }
            result.append(amount)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - 覆盖率

    /// 某月的覆盖率：有记录或已确认无支出的天数。
    func coverage(forMonth year: Int, month: Int) throws -> MonthCoverage {
        let range = try monthRange(year: year, month: month)
        let txns = try transactions(from: range.start, to: range.end)
        let monthStart = range.start
        let monthEnd = range.end
        let confirmations = try context.fetch(FetchDescriptor<DayConfirmation>(
            predicate: #Predicate { $0.day >= monthStart && $0.day < monthEnd }
        ))

        var recorded: Set<Int> = []
        for txn in txns { recorded.insert(calendar.component(.day, from: txn.date)) }

        var confirmed: Set<Int> = []
        for item in confirmations { confirmed.insert(calendar.component(.day, from: item.day)) }

        let daysInMonth = calendar.dayCount(inMonthOf: range.start)
        let isCurrentMonth = calendar.isDate(range.start, equalTo: .now, toGranularity: .month)
        let elapsedDays = isCurrentMonth ? calendar.component(.day, from: .now) : daysInMonth

        return MonthCoverage(
            daysWithRecords: recorded.count,
            daysConfirmedNoSpend: confirmed.subtracting(recorded).count,
            coveredDays: recorded.union(confirmed).count,
            daysInMonth: daysInMonth,
            elapsedDays: elapsedDays
        )
    }

    // MARK: - 统计

    /// 账户当前余额（分）= 期初余额 + 收入 - 支出。
    func balanceCents(for account: Account) throws -> Int64 {
        let txns = try transactions(account: account)
        return account.initialBalanceCents + txns.reduce(into: Int64(0)) { $0 += $1.balanceDeltaCents }
    }

    /// 月度汇总：总额 + 分类分布。
    func summary(forMonth year: Int, month: Int) throws -> MonthlySummary {
        let range = try monthRange(year: year, month: month)
        let txns = try transactions(from: range.start, to: range.end)

        var summary = MonthlySummary(year: year, month: month)
        var expenseGroups: [UUID: (Category, Int64)] = [:]
        var incomeGroups: [UUID: (Category, Int64)] = [:]

        for txn in txns {
            switch txn.kind {
            case .expense:
                summary.totalExpenseCents += txn.amountCents
                if let category = txn.category {
                    let current = expenseGroups[category.id]?.1 ?? 0
                    expenseGroups[category.id] = (category, current + txn.amountCents)
                }
            case .income:
                summary.totalIncomeCents += txn.amountCents
                if let category = txn.category {
                    let current = incomeGroups[category.id]?.1 ?? 0
                    incomeGroups[category.id] = (category, current + txn.amountCents)
                }
            }
        }

        summary.expenseByCategory = makeCategorySummaries(from: expenseGroups)
        summary.incomeByCategory = makeCategorySummaries(from: incomeGroups)
        return summary
    }

    private func monthRange(year: Int, month: Int) throws -> (start: Date, end: Date) {
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            throw SpendgeError.invalidDate
        }
        return (start, end)
    }

    private func makeCategorySummaries(
        from groups: [UUID: (Category, Int64)]
    ) -> [CategorySummary] {
        groups.values
            .map { category, amountCents in
                CategorySummary(
                    categoryID: category.id,
                    categoryName: category.name,
                    iconName: category.iconName,
                    colorHex: category.colorHex,
                    amountCents: amountCents
                )
            }
            .sorted { $0.amountCents > $1.amountCents }
    }
}