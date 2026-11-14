import Foundation
import SwiftData

/// 首屏那句话：大句给情绪，小句给事实。
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
        let today = try transactions(from: calendar.startOfDay(for: .now), to: .now)
        let monthStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let totalCount = try context.fetchCount(FetchDescriptor<Transaction>())

        // 1. 今天有记录：按「今天发生了什么」说一句
        if !today.isEmpty {
            return todayInsight(today)
        }

        // 2. 今天确认过没花钱
        if try isConfirmedToday() {
            return Insight(title: "今天没花钱", detail: "也是一种过法")
        }

        // 3. 刚开始用：先别谈数据
        if totalCount < 5 {
            return Insight(title: "从今天开始，它会越来越懂你", detail: nil)
        }

        // 4. 有缺口：说成"有些天没记上"，不报天数
        let coverage = try coverage(forMonth: calendar.component(.month, from: .now),
                                    year: calendar.component(.year, from: .now))
        if coverage.elapsedDays - coverage.coveredDays >= 3 {
            return Insight(title: "有些事没记上", detail: "想补的时候补一下就好")
        }

        // 5. 兜底：本周与上周的外卖对比，数字放在小字里
        return try weeklyInsight(monthStart: monthStart)
    }

    // MARK: - 今天的句子

    private func todayInsight(_ transactions: [Transaction]) -> Insight {
        // 发薪日单独说
        if transactions.contains(where: { $0.category?.categoryCode == .salary }) {
            return Insight(title: "发薪日快乐", detail: "这个月慢慢花")
        }

        let takeoutCount = transactions.filter { $0.category?.categoryCode == .takeout }.count
        if takeoutCount >= 2 {
            return Insight(
                title: "今天点了 \(takeoutCount) 次外卖",
                detail: "偶尔这样，也没关系"
            )
        }

        // 取今天最有「事」的一笔：优先非收入、有分类的
        let candidate = transactions.first { $0.category != nil } ?? transactions[0]
        guard let code = candidate.category?.categoryCode else {
            return Insight(title: "记下了", detail: nil)
        }
        return copy(for: code)
    }

    /// 每个分类两句话，按日期轮换，避免连着几天说一模一样的话。
    private func copy(for code: CategoryCode) -> Insight {
        let options: [(String, String?)]
        switch code {
        case .takeout:
            options = [("今天吃得简单", "偶尔这样也挺好"), ("这顿解决了，省下不少时间", nil)]
        case .grocery:
            options = [("买了菜", "厨房今晚有动静了"), ("提着菜回来的路上，日子挺具体", nil)]
        case .dineout:
            options = [("今天在外面吃了一顿", nil), ("下馆子的快乐，值得记一笔", nil)]
        case .drink:
            options = [("一杯在手，慢慢来", nil), ("今天的甜，是这杯给的", nil)]
        case .snack:
            options = [("给自己买了点甜", nil), ("嘴上有事做，心里就踏实些", nil)]
        case .outing:
            options = [("出门了", "路上总会遇到点新鲜事"), ("今天走的路比平时多", nil)]
        case .housing:
            options = [("该交的都交完了", "踏实"), ("这些钱，换的是安稳", nil)]
        case .daily:
            options = [("把日子一点点补齐", nil), ("这些小东西，撑起了日常", nil)]
        case .wear:
            options = [("添了件新东西", nil), ("穿起来应该不错", nil)]
        case .gear:
            options = [("又多了件趁手的家伙", nil), ("工具到位，事情就好办了", nil)]
        case .appliance:
            options = [("家里更像家了", nil), ("添置完，屋子会舒服一点", nil)]
        case .subscription:
            options = [("该续的都续上了", nil), ("这些是无声的开销", nil)]
        case .social:
            options = [("人情往来", "花出去的总会回来"), ("该到的心意到了", nil)]
        case .health:
            options = [("照顾好自己这件事，值得", nil), ("身体这笔账，先记上", nil)]
        case .otherExpense:
            options = [("记下了", nil), ("有些开销说不清，也没关系", nil)]
        default:
            options = [("有进账", "安心一点"), ("今天有笔收入", nil)]
        }

        let index = calendar.ordinality(of: .day, in: .year, for: .now) ?? 0
        let choice = options[index % options.count]
        return Insight(title: choice.0, detail: choice.1)
    }

    // MARK: - 兜底：本周与上周

    private func weeklyInsight(monthStart: Date) throws -> Insight {
        let now = Date.now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart

        let thisWeek = try count(.takeout, from: weekStart, to: now)
        let lastWeek = try count(.takeout, from: lastWeekStart, to: weekStart)

        if lastWeek > 0 {
            let diff = thisWeek - lastWeek
            if diff == 0 {
                return Insight(
                    title: "这周和上周一样，点了 \(thisWeek) 次外卖",
                    detail: nil
                )
            }
            return Insight(
                title: "这周外卖比上周\(diff > 0 ? "多" : "少")了 \(abs(diff)) 次",
                detail: "上周 \(lastWeek) 次，这周 \(thisWeek) 次"
            )
        }

        let monthCount = try context.fetchCount(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= monthStart }
        ))
        return Insight(
            title: "这个月记了 \(monthCount) 笔",
            detail: "慢慢来"
        )
    }

    // MARK: - 查询

    private func transactions(from start: Date, to end: Date) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func count(_ code: CategoryCode, from start: Date, to end: Date) throws -> Int {
        let raw = code.rawValue
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.category?.code == raw }
        )
        return try context.fetchCount(descriptor)
    }

    private func isConfirmedToday() throws -> Bool {
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let descriptor = FetchDescriptor<DayConfirmation>(
            predicate: #Predicate { $0.day >= start && $0.day < end }
        )
        return try context.fetchCount(descriptor) > 0
    }

    private func coverage(forMonth month: Int, year: Int) throws -> MonthCoverage {
        try TransactionService(context: context, calendar: calendar)
            .coverage(forMonth: year, month: month)
    }
}
