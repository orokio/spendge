import Foundation
import SwiftData

/// 预算业务逻辑：设置 / 更新 / 查询预算、计算已支出与进度。
@MainActor
final class BudgetService {
    struct BudgetProgress: Equatable {
        let spentCents: Int64
        let budgetCents: Int64

        var remainingCents: Int64 { budgetCents - spentCents }
        var ratio: Double {
            guard budgetCents > 0 else { return 0 }
            return Double(spentCents) / Double(budgetCents)
        }
    }

    private let context: ModelContext
    private let transactionService: TransactionService
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.transactionService = TransactionService(context: context, calendar: calendar)
        self.calendar = calendar
    }

    func budgets(year: Int, month: Int) throws -> [Budget] {
        var descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.year == year && $0.month == month }
        )
        descriptor.sortBy = [SortDescriptor(\.amountCents, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// 查询某月某分类（或全部）的预算。
    func budget(category: Category?, year: Int, month: Int) throws -> Budget? {
        if let category {
            let categoryID = category.id
            let descriptor = FetchDescriptor<Budget>(
                predicate: #Predicate { $0.year == year && $0.month == month && $0.category?.id == categoryID }
            )
            return try context.fetch(descriptor).first
        } else {
            return try budgets(year: year, month: month).first { $0.category == nil }
        }
    }

    /// 设置预算：同月同分类已存在则更新金额。
    @discardableResult
    func setBudget(
        category: Category? = nil,
        amountCents: Int64,
        year: Int,
        month: Int,
        isRecurring: Bool = false
    ) throws -> Budget {
        guard amountCents >= 0 else { throw SpendgeError.invalidAmount }
        if let existing = try budget(category: category, year: year, month: month) {
            existing.amountCents = amountCents
            existing.isRecurring = isRecurring
            existing.updatedAt = .now
            try context.save()
            return existing
        }
        let budget = Budget(category: category, amountCents: amountCents,
                            year: year, month: month, isRecurring: isRecurring)
        context.insert(budget)
        try context.save()
        return budget
    }

    /// 上个月勾了「循环应用」时，给本月补一条
    func carryForwardIfNeeded(asOf date: Date = .now) throws {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return }
        guard try budget(category: nil, year: year, month: month) == nil else { return }

        let all = try context.fetch(
            FetchDescriptor<Budget>(sortBy: [
                SortDescriptor(\Budget.year, order: .reverse),
                SortDescriptor(\Budget.month, order: .reverse),
            ])
        )
        guard let source = all.first(where: { $0.category == nil && $0.isRecurring }) else { return }
        let copy = Budget(category: nil, amountCents: source.amountCents,
                          year: year, month: month, isRecurring: true)
        context.insert(copy)
        try context.save()
    }

    func deleteBudget(_ budget: Budget) throws {
        context.delete(budget)
        try context.save()
    }

    /// 某月某分类（或全部）的已支出金额（分），只统计支出。
    func spentCents(category: Category?, year: Int, month: Int) throws -> Int64 {
        let range = try monthRange(year: year, month: month)
        let txns = try transactionService.transactions(from: range.start, to: range.end)
        return txns.reduce(into: Int64(0)) { partial, txn in
            guard txn.kind == .expense else { return }
            if let category, txn.category?.id != category.id { return }
            partial += txn.amountCents
        }
    }

    /// 预算进度（已支出 / 预算金额）。
    func progress(for budget: Budget, year: Int, month: Int) throws -> BudgetProgress {
        let spent = try spentCents(category: budget.category, year: year, month: month)
        return BudgetProgress(spentCents: spent, budgetCents: budget.amountCents)
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
}
