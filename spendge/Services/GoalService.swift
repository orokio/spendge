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
                predicate: #Predicate { $0.isActive == true && $0.deletedAt == nil },
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
        targetValue: Int,
        isRecurring: Bool = false
    ) throws -> Goal {
        try FaultInjection.current.check(.goalWrite)
        try validate(title: title, kind: kind, targetValue: targetValue)

        // 免费版限制：本月 1 个整体预算 + 2 个其他目标，两类分开计数
        if !Entitlements.can(.unlimitedGoals) {
            let monthStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
            let monthGoals = try goals().filter {
                calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month)
            }
            let isBudget = kind == .budget && categoryCodes.isEmpty
            if isBudget {
                let budgets = monthGoals.filter(\.isBudget).count
                guard budgets < Entitlements.freeBudgetLimit else {
                    throw SpendgeError.budgetLimitReached
                }
            } else {
                let others = monthGoals.filter { !$0.isBudget }.count
                guard others < Entitlements.freeGoalLimit else {
                    throw SpendgeError.goalLimitReached
                }
            }
        }

        let existing = try goals()
        let goal = Goal(
            title: title,
            kind: kind,
            categoryCodes: categoryCodes,
            period: period,
            periodStart: calendar.dateInterval(of: .month, for: .now)?.start,
            ledgerID: DefaultData.defaultLedgerID(context: context),
            targetValue: targetValue,
            isRecurring: isRecurring,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1
        )
        context.insert(goal)
        try context.save()
        Analytics.record(.goalCreated, ["kind": kind.rawValue, "period": period.rawValue])
        return goal
    }

    /// 修改参数：只动目标本身，已经固化的达成记录不受影响
    func update(_ goal: Goal, title: String, kind: GoalKind,
                categoryCodes: [String], period: GoalPeriod, targetValue: Int,
                isRecurring: Bool? = nil) throws {
        try FaultInjection.current.check(.goalWrite)
        try validate(title: title, kind: kind, targetValue: targetValue)
        goal.title = title
        goal.kindRawValue = kind.rawValue
        goal.categoryCodes = categoryCodes
        goal.periodRawValue = period.rawValue
        goal.targetValue = targetValue
        if let isRecurring { goal.isRecurring = isRecurring }
        goal.updatedAt = .now
        try context.save()
    }

    /// 删除目标：先把已经走完的周期固化下来，再删。
    /// 记录不会跟着删——用户不想做了，但已经做到的事要留着。
    func delete(_ goal: Goal) throws {
        try FaultInjection.current.check(.goalWrite)
        try materializeAchievements(for: goal)
        goal.deletedAt = .now
        try context.save()
    }

    private func validate(title: String, kind: GoalKind, targetValue: Int) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpendgeError.invalidGoalTarget }
        guard trimmed.count <= InputLimits.goalTitleLength else { throw SpendgeError.goalTitleTooLong }

        switch kind {
        case .countLimit:
            // 0 是合法上限：「本月奶茶 0 次」
            guard (0...InputLimits.countTargetMax).contains(targetValue) else {
                throw SpendgeError.invalidGoalTarget
            }
        case .budget:
            guard targetValue >= 0, Int64(targetValue) <= InputLimits.amountCentsMax else {
                throw SpendgeError.invalidGoalTarget
            }
        case .shareCap:
            guard (0...100).contains(targetValue) else {
                throw SpendgeError.invalidGoalTarget
            }
        }
    }

    // MARK: - 达成记录

    func achievements() throws -> [GoalAchievement] {
        try context.fetch(
            FetchDescriptor<GoalAchievement>(
                predicate: #Predicate { $0.deletedAt == nil },
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

    /// 每个月一份目标：只给这一份目标所属的月份固化一条记录
    func materializeAchievements(for goal: Goal, asOf date: Date = .now) throws {
        guard let currentStart = calendar.dateInterval(of: .month, for: date)?.start else { return }
        guard goal.monthStart < currentStart else { return }

        let recorded = Set(try achievements(forGoalID: goal.id).map { $0.periodStart })
        guard !recorded.contains(goal.monthStart) else { return }

        let progress = try progress(for: goal)
        let achieved = progress.isAtMost
            ? progress.current <= progress.target
            : progress.current >= progress.target
        context.insert(GoalAchievement(
            goalID: goal.id,
            title: goal.title,
            period: goal.period,
            periodStart: goal.monthStart,
            achieved: achieved,
            currentValue: progress.current,
            targetValue: progress.target,
            unit: progress.unit,
            kindRawValue: goal.kindRawValue
        ))
        try context.save()
    }

    /// 上个月勾了「循环应用」的目标，这个月自动建一份一样的（新对象，不复用）
    func carryForwardIfNeeded(asOf date: Date = .now) throws {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) else { return }

        // 硬幂等：每个月只补一次，之后用户删了也不会再生成
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        let carryKey = "goal.carry.\(comps.year ?? 0)-\(comps.month ?? 0)"
        guard !UserDefaults.standard.bool(forKey: carryKey) else { return }

        let all = try goals()
        let current = all.filter {
            calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month)
        }
        let sources = all.filter {
            $0.isRecurring && calendar.isDate($0.monthStart, equalTo: previousStart, toGranularity: .month)
        }

        var created = false
        for source in sources {
            let exists = current.contains {
                $0.kind == source.kind && $0.categoryCodes.sorted() == source.categoryCodes.sorted()
            }
            guard !exists else { continue }
            context.insert(Goal(
                title: source.title,
                kind: source.kind,
                categoryCodes: source.categoryCodes,
                period: source.period,
                periodStart: monthStart,
                ledgerID: source.ledgerID ?? DefaultData.defaultLedgerID(context: context),
                targetValue: source.targetValue,
                isRecurring: true,
                sortOrder: source.sortOrder
            ))
            created = true
        }
        if created { try context.save() }
        UserDefaults.standard.set(true, forKey: carryKey)
    }

    // MARK: - 预算（kind = budget，分类为空）

    /// 某月的整体预算（原预算卡的数据源）
    func budget(year: Int, month: Int) throws -> Goal? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        guard let start = calendar.date(from: comps) else { return nil }
        return try goals().first {
            $0.isBudget && calendar.isDate($0.monthStart, equalTo: start, toGranularity: .month)
        }
    }

    @discardableResult
    func setBudget(amountCents: Int64, year: Int, month: Int, isRecurring: Bool = false) throws -> Goal {
        try FaultInjection.current.check(.budgetWrite)
        guard amountCents >= 0, amountCents <= InputLimits.amountCentsMax else {
            throw SpendgeError.invalidAmount
        }
        if let existing = try budget(year: year, month: month) {
            existing.targetValue = Int(amountCents)
            existing.isRecurring = isRecurring
            existing.updatedAt = .now
            try context.save()
            return existing
        }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        guard let start = calendar.date(from: comps) else { throw SpendgeError.invalidDate }
        let goal = Goal(title: "本月预算",
                        kind: .budget,
                        categoryCodes: [],
                        period: .month,
                        periodStart: start,
                        ledgerID: DefaultData.defaultLedgerID(context: context),
                        targetValue: Int(amountCents),
                        isRecurring: isRecurring)
        context.insert(goal)
        try context.save()
        return goal
    }

    func deleteBudget(_ goal: Goal) throws {
        try FaultInjection.current.check(.budgetWrite)
        goal.deletedAt = .now
        try context.save()
    }

    /// 是否已有同类型、同分类范围、同周期的目标（阈值不同也算同一个）
    func existingGoal(kind: GoalKind, categoryCodes: [String], period: GoalPeriod) throws -> Goal? {
        let codes = categoryCodes.sorted()
        let monthStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return try goals().first {
            calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month) &&
            $0.kind == kind && $0.categoryCodes.sorted() == codes && $0.period == period
        }
    }

    // MARK: - 进度

    func progress(for goal: Goal, asOf date: Date = .now) throws -> GoalProgress {
        let range = try periodRange(goal.period, asOf: goal.monthStart)
        let unit: GoalProgress.Unit
        let current: Int
        let isAtMost: Bool

        switch goal.kind {
        case .countLimit:
            unit = .count
            isAtMost = true
            // 退款不是一次消费，计数型目标不计入
            current = try transactions(
                from: range.start, to: range.end, codes: goal.categoryCodes, kind: .expense
            ).filter { $0.refundOfID == nil }.count
        case .budget:
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
        let component: Calendar.Component = .month
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
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.deletedAt == nil }
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
