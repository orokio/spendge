#if DEBUG
import Foundation
import SwiftData

enum DebugScenario: String, CaseIterable, Identifiable {
    case empty
    case firstWeek
    case oneMonth
    case nearTrophyUnlock
    case overBudget
    case incomeHeavy
    case pastGoals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: return "清空数据"
        case .firstWeek: return "首周"
        case .oneMonth: return "一个月"
        case .nearTrophyUnlock: return "近解锁"
        case .overBudget: return "超预算"
        case .incomeHeavy: return "收入为主"
        case .pastGoals: return "过去三个月目标"
        }
    }

    var detail: String {
        switch self {
        case .empty: return "删除全部账单、目标、预算、没花钱确认与奖杯记录"
        case .firstWeek: return "7 天、每天 1–2 笔，含一条备注"
        case .oneMonth: return "30 天、覆盖主要分类与一笔工资"
        case .nearTrophyUnlock: return "99 笔记录，再记一笔解锁「一百笔」"
        case .overBudget: return "本月预算 1000 元，账单已超支"
        case .incomeHeavy: return "两笔收入 + 少量支出"
        case .pastGoals: return "前三个月各生成账单、预算与目标达成记录，用于回看"
        }
    }
}

/// 确定性数据模拟：同一场景每次生成相同的日期与金额。
@MainActor
struct DebugDataSeeder {
    let context: ModelContext
    private let calendar = Calendar.current

    func run(_ scenario: DebugScenario) throws {
        try wipe()

        switch scenario {
        case .empty:
            break
        case .firstWeek:
            try seed(days: 7, perDay: 1...2, includeIncome: false)
        case .oneMonth:
            try seed(days: 30, perDay: 1...2, includeIncome: true)
        case .nearTrophyUnlock:
            try seedFixedCount(99)
        case .overBudget:
            try seedOverBudget()
        case .incomeHeavy:
            try seedIncomeHeavy()
        case .pastGoals:
            try seedPastGoals()
        }

        try context.save()
        try? AchievementService(context: context).refreshUnlocks()
    }

    // MARK: - 场景

    private func seed(days: Int, perDay: ClosedRange<Int>, includeIncome: Bool) throws {
        let (expenses, incomes) = try base()
        var rng = SeededRandom(seed: 20261123)
        let today = calendar.startOfDay(for: .now)

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let count = perDay.lowerBound + rng.next(perDay.count)
            for index in 0..<count {
                let category = expenses[rng.next(expenses.count)]
                let amount = Int64(1200 + rng.next(8800))
                let note: String? = (offset == 1 && index == 0) ? "楼下便利店" : (rng.next(4) == 0 ? "随手记" : nil)
                let txn = Transaction(
                    amountCents: amount,
                    kind: .expense,
                    date: day.addingTimeInterval(TimeInterval(9 + index * 6) * 3600),
                    note: note,
                    category: category
                )
                context.insert(txn)
            }

            if includeIncome, offset > 0, offset % 7 == 0, let salary = incomes.first {
                context.insert(Transaction(
                    amountCents: 1_500_000,
                    kind: .income,
                    date: day.addingTimeInterval(10 * 3600),
                    note: nil,
                    category: salary
                ))
            }
        }
    }

    private func seedFixedCount(_ count: Int) throws {
        let (expenses, _) = try base()
        var rng = SeededRandom(seed: 20261124)
        let today = calendar.startOfDay(for: .now)

        for index in 0..<count {
            let dayOffset = index / 3
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let category = expenses[rng.next(expenses.count)]
            context.insert(Transaction(
                amountCents: Int64(1500 + rng.next(6000)),
                kind: .expense,
                date: day.addingTimeInterval(TimeInterval(9 + (index % 3) * 5) * 3600),
                note: index % 3 == 0 ? "记一笔" : nil,
                category: category
            ))
        }
    }

    private func seedOverBudget() throws {
        let (expenses, _) = try base()
        var rng = SeededRandom(seed: 20261125)
        let now = Date.now
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let year = comps.year, let month = comps.month else { return }

        context.insert(Budget(category: nil, amountCents: 100_000, year: year, month: month))
        let today = calendar.startOfDay(for: now)
        for offset in 0..<20 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let category = expenses[rng.next(expenses.count)]
            context.insert(Transaction(
                amountCents: Int64(6000 + rng.next(6000)),
                kind: .expense,
                date: day.addingTimeInterval(12 * 3600),
                note: nil,
                category: category
            ))
        }
    }

    private func seedIncomeHeavy() throws {
        let (expenses, incomes) = try base()
        let today = calendar.startOfDay(for: .now)
        var rng = SeededRandom(seed: 20261126)

        for (index, category) in incomes.prefix(2).enumerated() {
            context.insert(Transaction(
                amountCents: index == 0 ? 1_500_000 : 300_000,
                kind: .income,
                date: today.addingTimeInterval(TimeInterval(-index) * 86400 + 10 * 3600),
                note: nil,
                category: category
            ))
        }
        for index in 0..<5 {
            let category = expenses[rng.next(expenses.count)]
            context.insert(Transaction(
                amountCents: Int64(1800 + rng.next(4000)),
                kind: .expense,
                date: today.addingTimeInterval(TimeInterval(-index) * 86400 + 18 * 3600),
                note: nil,
                category: category
            ))
        }
    }

    // MARK: - 基础

    /// 前三个月：账单 + 预算 + 两个目标的达成记录（其中一个月故意未达成）
    private func seedPastGoals() throws {
        let (expenses, _) = try base()
        var rng = SeededRandom(seed: 20261126)
        let currentMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now

        for offset in 1...3 {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonth) else { continue }

            for index in 0..<8 {
                guard let day = calendar.date(byAdding: .day, value: index * 3, to: monthStart) else { continue }
                let category = expenses[rng.next(expenses.count)]
                context.insert(Transaction(
                    amountCents: Int64(2000 + rng.next(8000)),
                    kind: .expense,
                    date: day.addingTimeInterval(12 * 3600),
                    category: category
                ))
            }

            let comps = calendar.dateComponents([.year, .month], from: monthStart)
            if let year = comps.year, let month = comps.month {
                context.insert(Budget(category: nil, amountCents: 300_000, year: year, month: month))
            }
        }

        // 每个月都是独立的目标对象，第二个月的计数目标故意没达成
        for offset in 1...3 {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonth) else { continue }
            let missed = (offset == 2)
            let month = calendar.component(.month, from: monthStart)

            let countGoal = Goal(title: "\(month)月外卖 4 次以内", kind: .countLimit,
                                 categoryCodes: [CategoryCode.takeout.rawValue],
                                 period: .month, periodStart: monthStart,
                                 targetValue: 4, sortOrder: offset, createdAt: monthStart)
            let sumGoal = Goal(title: "\(month)月奶茶咖啡 200 元以内", kind: .categorySum,
                               categoryCodes: [CategoryCode.drink.rawValue],
                               period: .month, periodStart: monthStart,
                               targetValue: 20_000, sortOrder: offset, createdAt: monthStart)
            context.insert(countGoal)
            context.insert(sumGoal)

            context.insert(GoalAchievement(
                goalID: countGoal.id, title: countGoal.title, period: .month, periodStart: monthStart,
                achieved: !missed, currentValue: missed ? 5 : 3, targetValue: 4, unit: .count
            ))
            context.insert(GoalAchievement(
                goalID: sumGoal.id, title: sumGoal.title, period: .month, periodStart: monthStart,
                achieved: true, currentValue: 15_000, targetValue: 20_000, unit: .cents
            ))
        }
    }

    private func base() throws -> ([Category], [Category]) {
        let categories = try context.fetch(FetchDescriptor<Category>())
        let expenses = categories.filter { $0.kind == .expense && $0.categoryCode != .otherExpense }
        let incomes = categories.filter { $0.kind == .income }
        return (expenses.isEmpty ? categories : expenses, incomes)
    }


    private func wipe() throws {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        for goal in goals { _ = goal.categoryCodes }
        for item in try context.fetch(FetchDescriptor<GoalAchievement>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TrophyUnlock>()) { context.delete(item) }
        for goal in goals { context.delete(goal) }
        for item in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Budget>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DayConfirmation>()) { context.delete(item) }
        try context.save()
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(_ upper: Int) -> Int {
        guard upper > 0 else { return 0 }
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(upper))
    }
}
#endif
