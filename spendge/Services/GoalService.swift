import Foundation
import SwiftData

/// 目标的当前进度。计数用点，金额用条，视图自己挑。
struct GoalProgress: Equatable {
    enum Unit: Equatable {
        case count
        case cents
        /// 占比，0-100 的整数
        case percent
    }

    let current: Int
    let target: Int
    let unit: Unit
    /// true = 上限型（用得越少越好），false = 下限型（攒得越多越好）
    let isAtMost: Bool
    let period: GoalPeriod

    /// 是否达标：上限型看有没有超，下限型看有没有到
    var isReached: Bool {
        isAtMost ? current <= target : current >= target
    }

    /// 上限型 = 还能用多少；下限型 = 还差多少
    var remaining: Int {
        max(0, target - current)
    }

    /// 上限型给「已用比例」，视图里取 1- 就是剩余的绿色
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(current) / Double(target))
    }
}

/// 目标的聚合与进度。只做四种封闭类型，不解析表达式。
@MainActor
final class GoalService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - 增删查

    func goals() throws -> [Goal] {
        try context.fetch(
            FetchDescriptor<Goal>(
                predicate: #Predicate { $0.isActive == true },
                sortBy: [SortDescriptor(\Goal.sortOrder), SortDescriptor(\Goal.createdAt)]
            )
        )
    }

    @discardableResult
    func create(
        title: String,
        kind: GoalKind,
        categoryCodes: [String] = [],
        period: GoalPeriod,
        targetValue: Int
    ) throws -> Goal {
        let existing = try goals()
        let goal = Goal(
            title: title,
            kind: kind,
            categoryCodes: categoryCodes,
            period: period,
            targetValue: targetValue,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1
        )
        context.insert(goal)
        try context.save()
        return goal
    }

    /// 修改参数：只动目标本身，已经固化的达成记录不受影响
    func update(_ goal: Goal, title: String, kind: GoalKind,
                categoryCodes: [String], period: GoalPeriod, targetValue: Int) throws {
        goal.title = title
        goal.kindRawValue = kind.rawValue
        goal.categoryCodes = categoryCodes
        goal.periodRawValue = period.rawValue
        goal.targetValue = targetValue
        goal.updatedAt = .now
        try context.save()
    }

    /// 删除目标：先把已经走完的周期固化下来，再删。
    /// 记录不会跟着删——用户不想做了，但已经做到的事要留着。
    func delete(_ goal: Goal) throws {
        try materializeAchievements(for: goal)
        context.delete(goal)
        try context.save()
    }

    // MARK: - 达成记录

    func achievements() throws -> [GoalAchievement] {
        try context.fetch(
            FetchDescriptor<GoalAchievement>(
                sortBy: [SortDescriptor(\GoalAchievement.periodStart, order: .reverse)]
            )
        )
    }

    func achievements(forGoalID id: UUID) throws -> [GoalAchievement] {
        try achievements().filter { $0.goalID == id }
    }

    /// 把已经走完的周期固化成记录，幂等
    func materializeAchievements(asOf date: Date = .now) throws {
        for goal in try goals() {
            try materializeAchievements(for: goal, asOf: date)
        }
    }

    func materializeAchievements(for goal: Goal, asOf date: Date = .now) throws {
        let component: Calendar.Component = goal.period == .week ? .weekOfYear : .month
        var recorded = Set(try achievements(forGoalID: goal.id).map { $0.periodStart })

        guard var cursor = calendar.dateInterval(of: component, for: goal.createdAt)?.start,
              let currentStart = calendar.dateInterval(of: component, for: date)?.start else { return }

        while cursor < currentStart {
            guard let range = calendar.dateInterval(of: component, for: cursor) else { break }
            if !recorded.contains(range.start) {
                let progress = try progress(for: goal, asOf: range.start)
                let achieved = progress.isAtMost
                    ? progress.current <= progress.target
                    : progress.current >= progress.target
                context.insert(GoalAchievement(
                    goalID: goal.id,
                    title: goal.title,
                    period: goal.period,
                    periodStart: range.start,
                    achieved: achieved,
                    currentValue: progress.current,
                    targetValue: progress.target,
                    unit: progress.unit
                ))
                recorded.insert(range.start)
            }
            guard let next = calendar.date(byAdding: component, value: 1, to: range.start) else { break }
            cursor = next
        }
        try context.save()
    }

    /// 是否已有同类型、同分类范围、同周期的目标（阈值不同也算同一个）
    func existingGoal(kind: GoalKind, categoryCodes: [String], period: GoalPeriod) throws -> Goal? {
        let codes = categoryCodes.sorted()
        return try goals().first {
            $0.kind == kind && $0.categoryCodes.sorted() == codes && $0.period == period
        }
    }

    // MARK: - 进度

    func progress(for goal: Goal, asOf date: Date = .now) throws -> GoalProgress {
        let range = try periodRange(goal.period, asOf: date)
        let unit: GoalProgress.Unit
        let current: Int
        let isAtMost: Bool

        switch goal.kind {
        case .countLimit:
            unit = .count
            isAtMost = true
            current = try transactions(
                from: range.start, to: range.end, codes: goal.categoryCodes, kind: .expense
            ).count
        case .categorySum:
            unit = .cents
            isAtMost = true
            current = Int(try transactions(
                from: range.start, to: range.end, codes: goal.categoryCodes, kind: .expense
            ).reduce(into: Int64(0)) { $0 += $1.amountCents })
        case .shareCap:
            unit = .percent
            isAtMost = true
            let scoped = try transactions(from: range.start, to: range.end,
                                          codes: goal.categoryCodes, kind: .expense)
                .reduce(into: Int64(0)) { $0 += $1.amountCents }
            let total = try transactions(from: range.start, to: range.end, codes: [], kind: .expense)
                .reduce(into: Int64(0)) { $0 += $1.amountCents }
            current = total > 0 ? Int((Double(scoped) / Double(total) * 100).rounded()) : 0
        }

        return GoalProgress(
            current: current,
            target: goal.targetValue,
            unit: unit,
            isAtMost: isAtMost,
            period: goal.period
        )
    }

    // MARK: - 区间与取样

    func periodRange(_ period: GoalPeriod, asOf date: Date = .now) throws -> (start: Date, end: Date) {
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            throw SpendgeError.invalidDate
        }
        return (interval.start, interval.end)
    }

    private func transactions(
        from start: Date,
        to end: Date,
        codes: [String],
        kind: TransactionKind
    ) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let all = try context.fetch(descriptor)
        return all.filter { txn in
            guard txn.kind == kind else { return false }
            guard !codes.isEmpty else { return true }
            guard let code = txn.category?.categoryCode?.rawValue else { return false }
            return codes.contains(code)
        }
    }

}
