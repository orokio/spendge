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
        let totalCount = try context.fetchCount(FetchDescriptor<Transaction>())

        // 1. 今天有记录：按「今天发生了什么」说一句
        if !today.isEmpty {
            return todayInsight(today)
        }

        // 2. 今天确认过没花钱
        if try isConfirmedToday() {
            return Insight(title: "一分没花", detail: "钱包：今天我没上班")
        }

        // 3. 一笔都没有 / 刚刚开始：先别谈数据
        if totalCount == 0 {
            return Insight(title: "账本还空着", detail: "第一笔，等你")
        }
        if totalCount < 5 {
            return Insight(title: "账本刚开头", detail: "慢慢就顺手了")
        }

        // 4. 有缺口：说成"有些天没记上"，不报天数
        let coverage = try coverage(forMonth: calendar.component(.month, from: .now),
                                    year: calendar.component(.year, from: .now))
        if coverage.elapsedDays - coverage.coveredDays >= 3 {
            return Insight(title: "有几天空着", detail: "它们不会跑")
        }

        // 5. 兜底
        return Insight(title: "今天还空着", detail: "想起来就来")
    }

    // MARK: - 今天的句子

    private func todayInsight(_ transactions: [Transaction]) -> Insight {
        // 发薪日单独说
        if transactions.contains(where: { $0.category?.categoryCode == .salary }) {
            return Insight(title: "发薪日", detail: "今天你说了算")
        }

        let takeoutCount = transactions.filter { $0.category?.categoryCode == .takeout }.count
        if takeoutCount >= 2 {
            return Insight(
                title: "第 \(takeoutCount) 顿外卖",
                detail: "锅：我还能用"
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
            options = [("没开火，饭到了", "灶台今天放假"), ("外卖在门口", "筷子先别拆")]
        case .grocery:
            options = [("菜买回来了", "今晚厨房营业"), ("拎着菜上楼", "这顿自己动手")]
        case .dineout:
            options = [("今天下馆子", "菜单翻了两遍"), ("这顿在店里吃", "碗不用洗，赚了")]
        case .drink:
            options = [("一杯在手", "世界安静三分钟"), ("今天的甜，是这杯给的", nil)]
        case .snack:
            options = [("买了点甜", "先吃哪个，纠结一下"), ("嘴里有点事做", "手就不闲了")]
        case .outing:
            options = [("出门跑了一趟", "车没白养"), ("这一趟在路上", nil)]
        case .game:
            options = [("消遣了一下", "该松一松"), ("玩了会儿", nil)]
        case .housing:
            options = [("都交完了", "住处的事，办妥了"), ("这些钱，换的是安稳", nil)]
        case .daily:
            options = [("日子一格一格填满", nil), ("小东西，撑起日常", nil)]
        case .wear:
            options = [("买了件新的", "明天穿哪件，是道题"), ("衣柜里多了一件", "衣柜快满了")]
        case .digitalGear:
            options = [("又多了件趁手的", "手痒就对了"), ("设备到位了", "家伙事儿齐了不少")]
        case .sportsOutdoor:
            options = [("动了动身体", "这钱花得值"), ("为下次出门备的", nil)]
        case .alcoholBeverage:
            options = [("喝了一点", "下不为例"), ("这杯不算贵", nil)]
        case .utilities:
            options = [("水电都交上了", "日子照常转"), ("这些跑不掉", nil)]
        case .broadband:
            options = [("网和物业都清了", "安心住着"), ("住处的事，办妥了", nil)]
        case .renovation:
            options = [("家里动了动", "住着更顺了"), ("修好了，踏实", nil)]
        case .fuel:
            options = [("油箱加满了", "能跑一阵子"), ("补了次能", nil)]
        case .travel:
            options = [("出门一趟", "路费和住处记下了"), ("这一程，值了", nil)]
        case .carCare:
            options = [("车的事办好了", "养车不便宜"), ("停好、洗好", nil)]
        case .phone:
            options = [("话费充上了", "不失联"), ("这个月的通讯费", nil)]
        case .appliance:
            options = [("家里更像家了", nil), ("添完了，屋子舒服一点", nil)]
        case .subscription:
            options = [("都续上了", "这些还在每天用着"), ("这个月的订阅", "每月自动续，省得惦记")]
        case .social:
            options = [("心意到了", "花出去的总会回来"), ("这份人情，记下了", nil)]
        case .health:
            options = [("照顾好自己", "这笔不能省"), ("身体这笔账", "它说了算")]
        case .otherExpense:
            options = [("记下了", nil), ("说不清的，也记着", nil)]
        default:
            options = [("有进账", "今天的风是顺的"), ("今天有笔收入", nil)]
        }

        let index = calendar.ordinality(of: .day, in: .year, for: .now) ?? 0
        let choice = options[index % options.count]
        return Insight(title: choice.0, detail: choice.1)
    }

    // MARK: - 查询

    private func transactions(from start: Date, to end: Date) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
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
