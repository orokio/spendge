#if DEBUG
import Foundation
import SwiftData

/// 仅 DEBUG 构建：首次启动生成 3 个月模拟账单，方便 UI 演示。
enum DemoData {
    static func installIfNeeded(context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Transaction>())) == 0 else { return }
        guard let categories = try? context.fetch(FetchDescriptor<Category>()),
              let account = try? context.fetch(FetchDescriptor<Account>()).first else { return }

        let expense = categories.filter { $0.kind == .expense && !$0.isArchived }
        let food = expense.first { $0.name == "餐饮" }
        let transport = expense.first { $0.name == "交通" }
        let shopping = expense.first { $0.name == "购物" }
        let fun = expense.first { $0.name == "娱乐" }
        let housing = expense.first { $0.name == "居住" }
        let salary = categories.first { $0.kind == .income && $0.name == "工资" }

        var rng = SeededRandom(seed: 2_026_080_501)
        let calendar = Calendar.current

        for offset in 0...2 {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: .now) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            let dayCount = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
            let maxDay = offset == 0 ? min(dayCount, calendar.component(.day, from: .now)) : dayCount

            // 每月 1 号发工资
            if let salary,
               let date = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1, hour: 10)) {
                insert(
                    context: context,
                    amountCents: 1_800_000, // ¥18,000
                    kind: .income,
                    category: salary,
                    account: account,
                    date: date,
                    note: "工资"
                )
            }

            // 每月 5 号房租
            if let housing,
               let date = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 5, hour: 9)) {
                insert(
                    context: context,
                    amountCents: 450_000, // ¥4,500
                    kind: .expense,
                    category: housing,
                    account: account,
                    date: date,
                    note: "房租"
                )
            }

            for day in 1...maxDay {
                guard let noon = calendar.date(
                    from: DateComponents(year: comps.year, month: comps.month, day: day, hour: 12, minute: 30)
                ) else { continue }

                // 每天午餐
                if let food {
                    let lunch = Int64(1_800 + Int.random(in: 0...40, using: &rng) * 100)
                    insert(
                        context: context,
                        amountCents: lunch,
                        kind: .expense,
                        category: food,
                        account: account,
                        date: noon,
                        note: ["午餐", "午饭", "外卖"].randomElement(using: &rng)
                    )
                }

                // 约 40% 的天数有交通
                if let transport,
                   Int.random(in: 0...9, using: &rng) < 4,
                   let morning = calendar.date(byAdding: .hour, value: -3, to: noon) {
                    let fare = Int64(300 + Int.random(in: 0...5, using: &rng) * 100)
                    insert(
                        context: context,
                        amountCents: fare,
                        kind: .expense,
                        category: transport,
                        account: account,
                        date: morning,
                        note: "地铁"
                    )
                }

                // 约 20% 的天数有购物 / 娱乐
                if let shopping,
                   Int.random(in: 0...9, using: &rng) < 2,
                   let afternoon = calendar.date(byAdding: .hour, value: 4, to: noon) {
                    let amount = Int64(3_000 + Int.random(in: 0...20, using: &rng) * 500)
                    insert(
                        context: context,
                        amountCents: amount,
                        kind: .expense,
                        category: shopping,
                        account: account,
                        date: afternoon,
                        note: ["超市", "日用品"].randomElement(using: &rng)
                    )
                }

                if let fun,
                   Int.random(in: 0...9, using: &rng) < 2,
                   let evening = calendar.date(byAdding: .hour, value: 7, to: noon) {
                    let amount = Int64(2_000 + Int.random(in: 0...15, using: &rng) * 500)
                    insert(
                        context: context,
                        amountCents: amount,
                        kind: .expense,
                        category: fun,
                        account: account,
                        date: evening,
                        note: ["电影", "游戏"].randomElement(using: &rng)
                    )
                }
            }
        }

        // 本月整体预算 ¥3,000
        let comps = calendar.dateComponents([.year, .month], from: .now)
        context.insert(Budget(
            amountCents: 300_000,
            year: comps.year ?? 2026,
            month: comps.month ?? 8
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
