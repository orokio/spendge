import SwiftUI
import SwiftData

/// 回看：讲生活，不讲报表。
/// 只用描述句——给事实贴标签就是审判。
struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]

    @State private var coverage: MonthCoverage?

    private var monthTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    private var expenseTransactions: [Transaction] {
        monthTransactions.filter { $0.kind == .expense }
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    coverageCard
                    dietCard
                    domainCard
                    if monthBudget != nil { budgetCard }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("回看")
            .task { refresh() }
            .onChange(of: transactions.count) { _, _ in refresh() }
        }
    }

    // MARK: - 覆盖率

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这个月")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if let coverage {
                Text("\(coverage.coveredDays) 天有你的记录")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(coverage.daysConfirmedNoSpend > 0
                     ? "其中 \(coverage.daysConfirmedNoSpend) 天是确认没花钱 · 覆盖 \(Int(coverage.ratio * 100))%"
                     : "覆盖 \(Int(coverage.ratio * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没有数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 饮食结构

    private var dietCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("吃的", systemImage: "fork.knife")
                .font(.headline)

            HStack(spacing: 0) {
                statColumn(value: "\(homemadeDays)", unit: "天", title: "自己做饭")
                statColumn(value: "\(count(.takeout))", unit: "次", title: "外卖")
                statColumn(value: "\(count(.dineout))", unit: "次", title: "下馆子")
                statColumn(value: "\(count(.drink))", unit: "杯", title: "咖啡奶茶")
            }

            if impulseCount > 0 {
                Text("其中有 \(impulseCount) 笔被你标为「冲动了」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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

    // MARK: - 领域分布

    private var domainCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("钱花在哪儿", systemImage: "circle.grid.2x2")
                .font(.headline)

            if domainRows.isEmpty {
                Text("本月还没有支出")
                    .font(.caption)
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
                                Capsule().fill(Color(.systemGray5))
                                Capsule()
                                    .fill(Color.brand.opacity(0.85))
                                    .frame(width: max(geo.size.width * Double(row.cents) / Double(maxCents), 6))
                            }
                        }
                        .frame(height: 6)

                        Text(AmountFormat.string(cents: row.cents))
                            .font(.caption.weight(.medium))
                            .frame(width: 76, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 预算

    @ViewBuilder
    private var budgetCard: some View {
        if let budget = monthBudget {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("本月预算", systemImage: "target")
                        .font(.headline)
                    Spacer()
                    Text(AmountFormat.string(cents: budget.amountCents))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: min(Double(totalExpenseCents) / Double(max(budget.amountCents, 1)), 1))
                    .tint(Color.brand)

                Text(budgetDescription(budget))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// 描述句，不是评判句。
    private func budgetDescription(_ budget: Budget) -> String {
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
