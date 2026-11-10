import SwiftUI
import SwiftData

/// 回看：只回答一个问题——这个月过成什么样。
/// 一种时间尺度（月份），不掺日视角的交互。
struct ReviewView: View {
    let onBack: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @Query private var confirmations: [DayConfirmation]

    @State private var coverage: MonthCoverage?

    private struct DayStat: Identifiable {
        let id: Int
        let count: Int
        let hasRecord: Bool
    }

    private var monthTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    private var expenseTransactions: [Transaction] {
        monthTransactions.filter { $0.kind == .expense }
    }

    private var dayStats: [DayStat] {
        let calendar = Calendar.current
        // 只画到今天：未来的日期不是「缺口」，不该出现在图里
        let dayCount = calendar.component(.day, from: .now)
        var counts: [Int: Int] = [:]
        var recorded: Set<Int> = []

        for txn in monthTransactions {
            let day = calendar.component(.day, from: txn.date)
            recorded.insert(day)
            counts[day, default: 0] += 1
        }
        for item in confirmations where calendar.isDate(item.day, equalTo: .now, toGranularity: .month) {
            recorded.insert(calendar.component(.day, from: item.day))
        }

        return (1...dayCount).map { day in
            DayStat(id: day, count: counts[day] ?? 0, hasRecord: recorded.contains(day))
        }
    }

    private var homemadeDays: Int {
        let days = expenseTransactions
            .filter { $0.category?.categoryCode == .grocery }
            .map { Calendar.current.startOfDay(for: $0.date) }
        return Set(days).count
    }

    private func count(_ code: CategoryCode) -> Int {
        expenseTransactions.filter { $0.category?.categoryCode == code }.count
    }

    private var impulseCount: Int {
        monthTransactions.filter { $0.isImpulse == true }.count
    }

    private var domainRows: [(domain: CategoryDomain, cents: Int64)] {
        var totals: [CategoryDomain: Int64] = [:]
        for txn in expenseTransactions {
            totals[txn.category?.domain ?? .other, default: 0] += txn.amountCents
        }
        return totals
            .map { (domain: $0.key, cents: $0.value) }
            .sorted { $0.cents > $1.cents }
    }

    private var monthBudget: Budget? {
        let comps = Calendar.current.dateComponents([.year, .month], from: .now)
        return budgets.first { $0.year == comps.year && $0.month == comps.month && $0.category == nil }
    }

    private var totalExpenseCents: Int64 {
        expenseTransactions.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                dietSection
                domainSection
                if monthBudget != nil { budgetSection }
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 8)
            .padding(.top, 8)
        }
        .task { refresh() }
        .onChange(of: transactions.count) { _, _ in refresh() }
        .onChange(of: confirmations.count) { _, _ in refresh() }
    }

    // MARK: - 这个月

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("这个月")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let coverage {
                Text("\(coverage.coveredDays) 天有你的记录")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("覆盖 \(Int(coverage.ratio * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没有数据")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }

            sparkline
                .padding(.top, 2)
        }
    }

    /// 静态柱状图：有记录的高度表示金额，缺口是 2pt 的细线。
    private var sparkline: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(dayStats) { stat in
                RoundedRectangle(cornerRadius: 1)
                    .fill(stat.hasRecord ? Color.brand.opacity(0.8) : Color.secondary.opacity(0.16))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(stat))
            }
        }
        .frame(height: 32, alignment: .bottom)
    }

    /// 柱高表示当天记了几笔——这根条讲的是记录密度，不是金额结构。
    /// 金额会被房租这类固定大额压平，笔数不会。
    private func barHeight(_ stat: DayStat) -> CGFloat {
        guard stat.hasRecord else { return 2 }
        guard stat.count > 0 else { return 8 }
        return min(30, 8 + CGFloat(stat.count) * 7)
    }

    // MARK: - 吃的

    private var dietSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("吃的")
                .font(.headline)

            HStack(spacing: 0) {
                statColumn(value: "\(homemadeDays)", unit: "天", title: "自己做饭")
                statColumn(value: "\(count(.takeout))", unit: "次", title: "外卖")
                statColumn(value: "\(count(.dineout))", unit: "次", title: "下馆子")
                statColumn(value: "\(count(.drink))", unit: "杯", title: "咖啡奶茶")
            }

            if impulseCount > 0 {
                Text("其中有 \(impulseCount) 笔被你标为「冲动了」。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statColumn(value: String, unit: String, title: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 钱花在哪儿

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("钱花在哪儿")
                .font(.headline)

            if domainRows.isEmpty {
                Text("本月还没有支出")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let maxCents = max(domainRows.first?.cents ?? 1, 1)
                ForEach(domainRows, id: \.domain) { row in
                    HStack(spacing: 12) {
                        Text(row.domain.displayName)
                            .font(.subheadline)
                            .frame(width: 44, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.12))
                                Capsule()
                                    .fill(Color.brand.opacity(0.75))
                                    .frame(width: max(geo.size.width * Double(row.cents) / Double(maxCents), 6))
                            }
                        }
                        .frame(height: 5)

                        Text(AmountFormat.string(cents: row.cents))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - 预算

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("预算")
                    .font(.headline)
                Spacer()
                Text(budgetDescription())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let budget = monthBudget {
                ProgressView(value: min(Double(totalExpenseCents) / Double(max(budget.amountCents, 1)), 1))
                    .tint(Color.brand)
            }
        }
    }

    private func budgetDescription() -> String {
        guard let budget = monthBudget else { return "" }
        let remaining = budget.amountCents - totalExpenseCents
        if remaining >= 0 {
            return "还剩 \(AmountFormat.string(cents: remaining))"
        }
        return "比预算多花了 \(AmountFormat.string(cents: -remaining))"
    }

    private func refresh() {
        let comps = Calendar.current.dateComponents([.year, .month], from: .now)
        coverage = try? TransactionService(context: context)
            .coverage(forMonth: comps.year ?? 2026, month: comps.month ?? 1)
    }
}
