import Foundation
import SwiftData

/// 首屏那句话。
/// 规则：事实 + 一个对比 + 一句轻判断。数字全部确定性计算，不经过模型。
/// 只用描述句和邀请句，不用评判句和催促句。
struct Insight: Equatable {
    let title: String
    let detail: String?
}

@MainActor
final class InsightService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func headline() throws -> Insight {
        let now = Date.now
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart

        // 还没有任何记录时，给一句开场，而不是报缺口
        let monthTransactions = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= monthStart }
        ))
        if monthTransactions.isEmpty {
            return Insight(title: "从今天开始，它会越来越懂你", detail: nil)
        }

        let takeoutThisWeek = try count(.takeout, from: weekStart, to: now)
        let takeoutLastWeek = try count(.takeout, from: lastWeekStart, to: weekStart)
        let homemadeDays = try distinctDays(.grocery, from: monthStart, to: now)
        let drinkCount = try count(.drink, from: monthStart, to: now)

        // 1. 本周 vs 上周（对比优先：用户自己记不住的量）
        if takeoutLastWeek > 0 || takeoutThisWeek > 0 {
            if takeoutThisWeek == 0, takeoutLastWeek > 0 {
                return Insight(title: "这周你还没点外卖", detail: "上周是 \(takeoutLastWeek) 次")
            }
            if takeoutThisWeek > 0, takeoutThisWeek != takeoutLastWeek, takeoutLastWeek > 0 {
                let diff = takeoutThisWeek - takeoutLastWeek
                let word = diff > 0 ? "多" : "少"
                return Insight(
                    title: "这周点了 \(takeoutThisWeek) 次外卖，比上周\(word) \(abs(diff)) 次",
                    detail: drinkCount > 0 ? "本月咖啡奶茶 \(drinkCount) 杯" : nil
                )
            }
        }

        // 2. 生活结构
        if homemadeDays > 0 {
            return Insight(
                title: "这个月你买了 \(homemadeDays) 天菜",
                detail: takeoutThisWeek > 0 ? "这周还有 \(takeoutThisWeek) 次外卖" : nil
            )
        }

        // 3. 缺口（主语是系统，不是用户的过失）
        let coverage = try TransactionService(context: context, calendar: calendar)
            .coverage(forMonth: yearOf(now), month: monthOf(now))
        let missing = coverage.elapsedDays - coverage.coveredDays
        if missing >= 3 {
            return Insight(
                title: "这 \(missing) 天我还没有你的记录",
                detail: "本月覆盖 \(Int(coverage.ratio * 100))%"
            )
        }

        // 4. 兜底：总量
        return Insight(
            title: "这个月你记了 \(monthTransactions.count) 笔",
            detail: coverage.coveredDays > 0 ? "覆盖 \(coverage.coveredDays) 天" : nil
        )
    }

    // MARK: - 查询

    private func count(_ code: CategoryCode, from start: Date, to end: Date) throws -> Int {
        let raw = code.rawValue
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.category?.code == raw }
        )
        return try context.fetchCount(descriptor)
    }

    private func distinctDays(_ code: CategoryCode, from start: Date, to end: Date) throws -> Int {
        let raw = code.rawValue
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.category?.code == raw }
        )
        let days = try context.fetch(descriptor).map { calendar.startOfDay(for: $0.date) }
        return Set(days).count
    }

    private func yearOf(_ date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    private func monthOf(_ date: Date) -> Int {
        calendar.component(.month, from: date)
    }
}
