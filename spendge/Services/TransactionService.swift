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

/// 金额输入建议：用户看到的是「已经填好的金额」或「几个档位」。
struct AmountSuggestion: Equatable {
    enum Style: String, Equatable {
        case none             // 数据不足，手输
        case mode             // 众数预填
        case medianWithChips  // 中位数预填 + 常用档
        case bucketsOnly      // 只给档位，不预填历史值
    }

    let prefillCents: Int64?
    let chips: [Int64]
    let style: Style

    /// 选档位得到的是估计值，写入时带上标记。
    var isEstimate: Bool { style == .bucketsOnly }

    static let empty = AmountSuggestion(prefillCents: nil, chips: [], style: .none)
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
        isApproximateAmount: Bool = false,
        isImpulse: Bool? = nil,
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
            isApproximateAmount: isApproximateAmount,
            isImpulse: isImpulse,
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

    /// 按分类历史金额的离散程度给出预填策略。
    /// 高方差分类不预填历史值——会诱发锚定偏差，用户看一眼就确认，数据被污染。
    func amountSuggestion(for category: Category, sampleLimit: Int = 30) throws -> AmountSuggestion {
        let categoryID = category.id
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.category?.id == categoryID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = sampleLimit
        let amounts = try context.fetch(descriptor).map(\.amountCents)

        guard amounts.count >= 3 else { return .empty }

        let mean = Double(amounts.reduce(into: Int64(0)) { $0 += $1 }) / Double(amounts.count)
        guard mean > 0 else { return .empty }
        let variance = amounts.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(amounts.count)
        let coefficient = variance.squareRoot() / mean

        if coefficient < 0.15 {
            return AmountSuggestion(prefillCents: mode(of: amounts), chips: [], style: .mode)
        }
        if coefficient <= 0.5 {
            let prefill = median(of: Array(amounts.prefix(3)))
            let chips = topValues(of: amounts, limit: 2, excluding: prefill)
            return AmountSuggestion(prefillCents: prefill, chips: chips, style: .medianWithChips)
        }
        return AmountSuggestion(prefillCents: nil, chips: quantileChips(of: amounts), style: .bucketsOnly)
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

        let daysInMonth = calendar.range(of: .day, in: .month, for: range.start)?.count ?? 30
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

    // MARK: - 建议辅助

    /// 众数；平票取最近一笔（amounts 已按时间倒序）。
    private func mode(of amounts: [Int64]) -> Int64 {
        var counts: [Int64: Int] = [:]
        for amount in amounts { counts[amount, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 1
        let candidates = Set(counts.filter { $0.value == maxCount }.keys)
        return amounts.first { candidates.contains($0) } ?? amounts[0]
    }

    private func median(of amounts: [Int64]) -> Int64 {
        let sorted = amounts.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private func topValues(of amounts: [Int64], limit: Int, excluding value: Int64) -> [Int64] {
        var counts: [Int64: Int] = [:]
        for amount in amounts where amount != value { counts[amount, default: 0] += 1 }
        return counts
            .sorted { $0.value == $1.value ? $0.key > $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    /// 档位：历史分位数，四舍五入到 5 元，去重。
    private func quantileChips(of amounts: [Int64]) -> [Int64] {
        let sorted = amounts.sorted()
        let quantiles: [Double] = [0.25, 0.5, 0.75, 0.9]
        var result: [Int64] = []
        for quantile in quantiles {
            let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * quantile).rounded())))
            let rounded = Int64((Double(sorted[index]) / 500).rounded()) * 500
            let value = max(100, rounded)
            if !result.contains(value) { result.append(value) }
        }
        return result
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
