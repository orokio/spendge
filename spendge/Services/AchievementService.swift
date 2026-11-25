import Foundation
import SwiftData

/// 一枚奖杯的完成度。current / target 都是整数，单位决定文案。
struct TrophyProgress: Equatable {
    let current: Int
    let target: Int
    let unit: TrophyUnit

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(current) / Double(max(target, 1)))
    }

    var isComplete: Bool { target > 0 && current >= target }

    var remainingText: String {
        if isComplete { return "已完成" }
        let gap = max(0, target - current)
        return unit == .percent ? "还差 \(gap)%" : "还差 \(gap) \(unit.suffix)"
    }

    var valueText: String {
        unit == .percent ? "\(current) / \(target)%" : "\(current) / \(target) \(unit.suffix)"
    }
}

/// 一次扫描的整体结果：30 枚的状态 + 顶部的累计天数与最长连续
struct AchievementSnapshot {
    let states: [TrophyID: TrophyState]
    let recordDays: Int
    let longestDayStreak: Int

    var unlockedCount: Int { states.values.filter { $0.isUnlocked }.count }
}

/// 奖杯墙的一行数据：目录 + 当前进度 + 解锁时间
struct TrophyState: Identifiable {
    let spec: TrophySpec
    let progress: TrophyProgress
    let unlockedAt: Date?

    var id: TrophyID { spec.id }
    var isUnlocked: Bool { unlockedAt != nil }
    /// 有进度但还没拿到：卡片显示迷你进度条
    var isInProgress: Bool { !isUnlocked && progress.current > 0 }
}

/// 奖杯判定：一次扫描把 30 枚需要的统计量全部算出来，再按 id 取。
///
/// 不缓存、不落中间表：个人账本的数据量下一次扫描是毫秒级，
/// 缓存反而会带来「数据变了进度没变」的麻烦。
@MainActor
final class AchievementService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - 查询

    func unlocks() -> [TrophyUnlock] {
        (try? context.fetch(FetchDescriptor<TrophyUnlock>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
    }

    func snapshot() -> AchievementSnapshot {
        let stats = loadStats()
        let unlockMap = Dictionary(unlocks().compactMap { item -> (TrophyID, Date)? in
            guard let id = item.id else { return nil }
            return (id, item.unlockedAt)
        }, uniquingKeysWith: { first, _ in first })

        var result: [TrophyID: TrophyState] = [:]
        for spec in TrophyCatalog.all {
            result[spec.id] = TrophyState(
                spec: spec,
                progress: progress(for: spec.id, stats: stats),
                unlockedAt: unlockMap[spec.id]
            )
        }
        return AchievementSnapshot(
            states: result,
            recordDays: stats.recordDayCount,
            longestDayStreak: stats.longestDayStreak
        )
    }

    /// 写入新解锁的奖杯，返回本次新拿到的（按目录顺序）。
    @discardableResult
    func refreshUnlocks(now: Date = .now) -> [TrophySpec] {
        let stats = loadStats()
        let owned = Set(unlocks().compactMap(\.id))
        var created: [TrophySpec] = []

        for spec in TrophyCatalog.all where !owned.contains(spec.id) {
            if progress(for: spec.id, stats: stats).isComplete {
                context.insert(TrophyUnlock(trophyID: spec.id, unlockedAt: now))
                created.append(spec)
            }
        }

        if !created.isEmpty { try? context.save() }
        return created
    }

    // MARK: - 统计

    private struct Stats {
        var transactionCount = 0
        var notedCount = 0
        var incomeCount = 0
        var recordDayCount = 0
        var longestDayStreak = 0
        var longestMonthStreak = 0
        var goalCount = 0
        var achievedCount = 0
        var longestGoalChain = 0
        var budgetKeptCount = 0
        var longestBudgetStreak = 0
        var bestNoteRatio = 0.0
        var bestCoveredDays = 0
        var bestCoveredDaysInMonth = 28
        var maxCategoriesInMonth = 0
        var hasNightRecord = false
        var hasEarlyRecord = false
        var hasBackdatedRecord = false
    }

    private func loadStats() -> Stats {
        var stats = Stats()

        let transactions = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let goals = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let achievements = (try? context.fetch(FetchDescriptor<GoalAchievement>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let confirmations = (try? context.fetch(FetchDescriptor<DayConfirmation>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []

        stats.transactionCount = transactions.count
        stats.incomeCount = transactions.filter { $0.kind == .income }.count
        stats.goalCount = goals.filter { $0.kind != .budget }.count
        stats.achievedCount = achievements.filter {
            $0.achieved && $0.kindRawValue != GoalKind.budget.rawValue
        }.count

        var days: Set<Date> = []
        var monthsWithRecord: Set<Date> = []
        var expenseByMonth: [Date: Int64] = [:]
        var monthTotals: [Date: (total: Int, noted: Int)] = [:]
        var monthDays: [Date: Set<Date>] = [:]
        var monthCategories: [Date: Set<UUID>] = [:]

        for txn in transactions {
            let day = calendar.startOfDay(for: txn.date)
            days.insert(day)

            guard let month = calendar.dateInterval(of: .month, for: txn.date)?.start else { continue }
            monthsWithRecord.insert(month)
            monthDays[month, default: []].insert(day)
            monthTotals[month, default: (0, 0)].total += 1
            if txn.note?.isEmpty == false { monthTotals[month, default: (0, 0)].noted += 1 }
            if let categoryID = txn.category?.id {
                monthCategories[month, default: []].insert(categoryID)
            }
            if txn.kind == .expense {
                expenseByMonth[month, default: 0] += txn.amountCents
            }

            let createdHour = calendar.component(.hour, from: txn.createdAt)
            if createdHour >= 23 { stats.hasNightRecord = true }
            if createdHour < 7 { stats.hasEarlyRecord = true }

            let recordedDay = calendar.startOfDay(for: txn.createdAt)
            if let gap = calendar.dateComponents([.day], from: day, to: recordedDay).day, gap >= 3 {
                stats.hasBackdatedRecord = true
            }
        }

        // 备注数：收支都算，只要写了字
        stats.notedCount = transactions.filter { $0.note?.isEmpty == false }.count
        stats.recordDayCount = days.count

        // 连续天数：排序后逐日比对
        let sortedDays = days.sorted()
        var dayRun = 0
        var previousDay: Date?
        for day in sortedDays {
            if let previousDay,
               calendar.dateComponents([.day], from: previousDay, to: day).day == 1 {
                dayRun += 1
            } else {
                dayRun = 1
            }
            stats.longestDayStreak = max(stats.longestDayStreak, dayRun)
            previousDay = day
        }

        // 连续月份：有记录的月份里最长的连续段
        let sortedMonths = monthsWithRecord.sorted()
        var monthRun = 0
        var previousMonth: Date?
        for month in sortedMonths {
            if let previousMonth,
               let expected = calendar.date(byAdding: .month, value: 1, to: previousMonth),
               calendar.isDate(month, equalTo: expected, toGranularity: .month) {
                monthRun += 1
            } else {
                monthRun = 1
            }
            stats.longestMonthStreak = max(stats.longestMonthStreak, monthRun)
            previousMonth = month
        }

        // 按月的备注占比、覆盖天数、分类数
        for (month, totals) in monthTotals where totals.total > 0 {
            let ratio = Double(totals.noted) / Double(totals.total)
            stats.bestNoteRatio = max(stats.bestNoteRatio, ratio)
            stats.maxCategoriesInMonth = max(stats.maxCategoriesInMonth, monthCategories[month]?.count ?? 0)
        }

        // 满月：账单日 + 「没花钱」确认日，取覆盖最好的那个月
        var coveredByMonth: [Date: Set<Date>] = monthDays
        for confirmation in confirmations {
            let day = calendar.startOfDay(for: confirmation.day)
            guard let month = calendar.dateInterval(of: .month, for: day)?.start else { continue }
            coveredByMonth[month, default: []].insert(day)
        }
        for (month, covered) in coveredByMonth {
            let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
            let ratio = Double(covered.count) / Double(dayCount)
            let bestRatio = Double(stats.bestCoveredDays) / Double(max(stats.bestCoveredDaysInMonth, 1))
            if ratio > bestRatio || (ratio == bestRatio && dayCount > stats.bestCoveredDaysInMonth) {
                stats.bestCoveredDays = covered.count
                stats.bestCoveredDaysInMonth = dayCount
            }
        }

        // 同一目标连续达成的月份数
        var achievedMonthsByGoal: [UUID: Set<Date>] = [:]
        for item in achievements where item.achieved && item.period == .month && item.kindRawValue != GoalKind.budget.rawValue {
            guard let month = calendar.dateInterval(of: .month, for: item.periodStart)?.start else { continue }
            achievedMonthsByGoal[item.goalID, default: []].insert(month)
        }
        for months in achievedMonthsByGoal.values {
            var run = 0
            var previous: Date?
            for month in months.sorted() {
                if let previous,
                   let expected = calendar.date(byAdding: .month, value: 1, to: previous),
                   calendar.isDate(month, equalTo: expected, toGranularity: .month) {
                    run += 1
                } else {
                    run = 1
                }
                stats.longestGoalChain = max(stats.longestGoalChain, run)
                previous = month
            }
        }

        // 预算：只看「全部预算」，没超的月份数与最长连续段
        var keptMonths: Set<Date> = []
        for goal in goals where goal.kind == .budget && goal.categoryCodes.isEmpty {
            let month = calendar.dateInterval(of: .month, for: goal.monthStart)?.start ?? goal.monthStart
            let spent = expenseByMonth[month] ?? 0
            if spent <= goal.targetValue { keptMonths.insert(month) }
        }
        stats.budgetKeptCount = keptMonths.count
        var budgetRun = 0
        var previousBudgetMonth: Date?
        for month in keptMonths.sorted() {
            if let previousBudgetMonth,
               let expected = calendar.date(byAdding: .month, value: 1, to: previousBudgetMonth),
               calendar.isDate(month, equalTo: expected, toGranularity: .month) {
                budgetRun += 1
            } else {
                budgetRun = 1
            }
            stats.longestBudgetStreak = max(stats.longestBudgetStreak, budgetRun)
            previousBudgetMonth = month
        }

        return stats
    }

    // MARK: - 单枚判定

    private func progress(for id: TrophyID, stats: Stats) -> TrophyProgress {
        switch id {
        case .firstRecord:
            return percentage(stats.transactionCount, 1, .records)
        case .firstGoal:
            return percentage(stats.goalCount, 1, .categories)
        case .firstAchievement:
            return percentage(stats.achievedCount, 1, .times)
        case .firstIncome:
            return percentage(stats.incomeCount, 1, .records)
        case .firstNote:
            return percentage(stats.notedCount, 1, .records)

        case .records100:
            return capped(stats.transactionCount, 100, .records)
        case .records500:
            return capped(stats.transactionCount, 500, .records)
        case .records1000:
            return capped(stats.transactionCount, 1000, .records)
        case .records5000:
            return capped(stats.transactionCount, 5000, .records)

        case .days90:
            return capped(stats.recordDayCount, 90, .days)
        case .days365:
            return capped(stats.recordDayCount, 365, .days)
        case .days730:
            return capped(stats.recordDayCount, 730, .days)

        case .streak7:
            return capped(stats.longestDayStreak, 7, .days)
        case .streak30:
            return capped(stats.longestDayStreak, 30, .days)
        case .streak100:
            return capped(stats.longestDayStreak, 100, .days)
        case .streak365:
            return capped(stats.longestDayStreak, 365, .days)
        case .months12:
            return capped(stats.longestMonthStreak, 12, .months)

        case .goals3:
            return capped(stats.achievedCount, 3, .times)
        case .goals12:
            return capped(stats.achievedCount, 12, .times)
        case .goalChain3:
            return capped(stats.longestGoalChain, 3, .months)
        case .goalChain12:
            return capped(stats.longestGoalChain, 12, .months)
        case .budgets3:
            return capped(stats.budgetKeptCount, 3, .times)
        case .budgets12:
            return capped(stats.longestBudgetStreak, 12, .months)

        case .notes100:
            return capped(stats.notedCount, 100, .notes)
        case .notesHalf:
            return TrophyProgress(current: Int(stats.bestNoteRatio * 100), target: 50, unit: .percent)
        case .fullMonth:
            return TrophyProgress(current: stats.bestCoveredDays,
                                  target: stats.bestCoveredDaysInMonth,
                                  unit: .days)
        case .allCategories:
            return capped(stats.maxCategoriesInMonth, 8, .categories)

        case .nightOwl:
            return percentage(stats.hasNightRecord ? 1 : 0, 1, .times)
        case .backdated:
            return percentage(stats.hasBackdatedRecord ? 1 : 0, 1, .times)
        case .earlyBird:
            return percentage(stats.hasEarlyRecord ? 1 : 0, 1, .times)
        }
    }

    private func capped(_ current: Int, _ target: Int, _ unit: TrophyUnit) -> TrophyProgress {
        TrophyProgress(current: current, target: target, unit: unit)
    }

    private func percentage(_ current: Int, _ target: Int, _ unit: TrophyUnit) -> TrophyProgress {
        TrophyProgress(current: min(current, target), target: target, unit: unit)
    }
}
