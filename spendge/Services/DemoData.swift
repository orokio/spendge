#if DEBUG
import Foundation
import SwiftData

/// 仅 DEBUG 构建：首次启动生成 3 个月模拟账单，方便 UI 演示与自检。
/// 分类一律按 code 匹配，改名不会让模拟数据失效。
enum DemoData {
    static func installIfNeeded(context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Transaction>())) == 0 else { return }
        guard let categories = try? context.fetch(FetchDescriptor<Category>()),
              let account = try? context.fetch(FetchDescriptor<Account>()).first else { return }

        var byCode: [CategoryCode: Category] = [:]
        for category in categories {
            if let code = category.categoryCode { byCode[code] = category }
        }
        func category(_ code: CategoryCode) -> Category? { byCode[code] }

        var rng = SeededRandom(seed: 2_026_080_501)
        let calendar = Calendar.current

        for offset in 0...2 {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: .now) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            let dayCount = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
            let maxDay = offset == 0 ? min(dayCount, calendar.component(.day, from: .now)) : dayCount

            // 每月 1 号发工资
            if let date = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1, hour: 10)) {
                insert(context: context, amountCents: 1_800_000, kind: .income,
                       category: category(.salary), account: account, date: date, note: "工资")
            }

            // 每月 5 号房租（低方差，众数预填的典型场景）
            if let date = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 5, hour: 9)) {
                insert(context: context, amountCents: 450_000, kind: .expense,
                       category: category(.housing), account: account, date: date, note: "房租")
            }

            for day in 1...maxDay {
                guard let noon = calendar.date(
                    from: DateComponents(year: comps.year, month: comps.month, day: day, hour: 12, minute: 30)
                ) else { continue }

                // 外卖：几乎每天，金额窄幅波动
                if Int.random(in: 0...9, using: &rng) < 8 {
                    let amount = Int64(1_800 + Int.random(in: 0...10, using: &rng) * 100)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.takeout), account: account, date: noon,
                           note: ["杨国福麻辣烫", "黄焖鸡", "沙县小吃", "兰州拉面"].randomElement(using: &rng))
                }

                // 咖啡奶茶：一半的日子，金额窄幅
                if let morning = calendar.date(byAdding: .hour, value: -2, to: noon),
                   Int.random(in: 0...9, using: &rng) < 5 {
                    let amount = Int64(1_500 + Int.random(in: 0...8, using: &rng) * 200)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.drink), account: account, date: morning,
                           note: ["瑞幸", "库迪", "蜜雪冰城", "茶百道"].randomElement(using: &rng))
                }

                // 买菜：每周一次，金额方差大
                if day % 7 == 1,
                   let evening = calendar.date(byAdding: .hour, value: 8, to: noon) {
                    // 日常小买 vs 一周屯货，方差大 —— 用来验证「纯档位」策略
                    let isBigTrip = Int.random(in: 0...9, using: &rng) < 4
                    let amount = isBigTrip
                        ? Int64(10_000 + Int.random(in: 0...10, using: &rng) * 1_000)
                        : Int64(2_000 + Int.random(in: 0...3, using: &rng) * 1_000)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.grocery), account: account, date: evening,
                           note: ["永辉超市", "菜市场", "社区团购"].randomElement(using: &rng))
                }

                // 下馆子：每周约两次，金额方差大
                if day % 7 == 5 || day % 7 == 6,
                   let evening = calendar.date(byAdding: .hour, value: 7, to: noon) {
                    let amount = Int64(6_000 + Int.random(in: 0...14, using: &rng) * 1_000)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.dineout), account: account, date: evening,
                           note: ["海底捞", "小炒店", "面馆"].randomElement(using: &rng))
                }

                // 出行：小额的常态 + 偶发的大额（双峰）
                if Int.random(in: 0...9, using: &rng) < 4,
                   let morning = calendar.date(byAdding: .hour, value: -3, to: noon) {
                    let isTaxi = Int.random(in: 0...9, using: &rng) < 3
                    let amount = isTaxi
                        ? Int64(2_000 + Int.random(in: 0...15, using: &rng) * 100)
                        : Int64(300 + Int.random(in: 0...3, using: &rng) * 100)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.transport), account: account, date: morning,
                           note: isTaxi ? "打车" : "地铁")
                }

                // 买东西 / 玩：低频，方差大
                if Int.random(in: 0...9, using: &rng) < 2,
                   let afternoon = calendar.date(byAdding: .hour, value: 4, to: noon) {
                    let amount = Int64(3_000 + Int.random(in: 0...13, using: &rng) * 1_000)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.shopping), account: account, date: afternoon,
                           note: ["日用品", "衣服"].randomElement(using: &rng))
                }

                if Int.random(in: 0...9, using: &rng) < 1,
                   let evening = calendar.date(byAdding: .hour, value: 7, to: noon) {
                    let amount = Int64(2_000 + Int.random(in: 0...8, using: &rng) * 1_000)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.fun), account: account, date: evening,
                           note: ["电影", "游戏", "会员"].randomElement(using: &rng))
                }

                // 人情：低频但金额不小
                if day % 11 == 3,
                   let evening = calendar.date(byAdding: .hour, value: 6, to: noon) {
                    let amount = Int64(20_000 + Int.random(in: 0...6, using: &rng) * 10_000)
                    insert(context: context, amountCents: amount, kind: .expense,
                           category: category(.social), account: account, date: evening,
                           note: ["随礼", "请客"].randomElement(using: &rng))
                }
            }
        }

        // 本月整体预算
        let comps = calendar.dateComponents([.year, .month], from: .now)
        context.insert(Budget(
            amountCents: 300_000,
            year: comps.year ?? 2026,
            month: comps.month ?? 1
        ))

        try? context.save()
    }

    private static func insert(
        context: ModelContext,
        amountCents: Int64,
        kind: TransactionKind,
        category: Category?,
        account: Account,
        date: Date,
        note: String? = nil
    ) {
        context.insert(Transaction(
            amountCents: amountCents,
            kind: kind,
            date: date,
            note: note,
            category: category,
            account: account
        ))
    }

    private struct SeededRandom: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
#endif
