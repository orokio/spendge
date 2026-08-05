import SwiftUI
import SwiftData

struct StatisticsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @State private var month = Calendar.current.startOfMonth(for: .now)

    private var monthTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var totalExpenseCents: Int64 {
        monthTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var totalIncomeCents: Int64 {
        monthTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
    }

    private var expenseBreakdown: [CategorySummary] {
        let expenseTransactions = monthTransactions.filter { $0.kind == .expense && $0.category != nil }
        let groups = Dictionary(grouping: expenseTransactions) { $0.category!.id }
        return groups.values
            .compactMap { items -> CategorySummary? in
                guard let category = items.first?.category else { return nil }
                return CategorySummary(
                    categoryID: category.id,
                    categoryName: category.name,
                    iconName: category.iconName,
                    colorHex: category.colorHex,
                    amountCents: items.reduce(0) { $0 + $1.amountCents }
                )
            }
            .sorted { $0.amountCents > $1.amountCents }
    }

    private var monthBudget: Budget? {
        let comps = Calendar.current.dateComponents([.year, .month], from: month)
        return budgets.first {
            $0.year == comps.year && $0.month == comps.month && $0.category == nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthStepper(month: $month)
                    summaryCard
                    budgetCard
                    breakdownCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryItem(title: "支出", cents: totalExpenseCents, color: .primary, showsSign: false)
            Divider().padding(.vertical, 12)
            summaryItem(title: "收入", cents: totalIncomeCents, color: .income, showsSign: false)
            Divider().padding(.vertical, 12)
            summaryItem(
                title: "结余",
                cents: totalIncomeCents - totalExpenseCents,
                color: .brand,
                showsSign: true
            )
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(title: String, cents: Int64, color: Color, showsSign: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AmountFormat.string(cents: cents, showsSign: showsSign))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本月预算", systemImage: "target")
                    .font(.headline)
                Spacer()
                if let budget = monthBudget {
                    Text(AmountFormat.string(cents: budget.amountCents))
                        .font(.subheadline.weight(.semibold))
                }
            }

            if let budget = monthBudget {
                let ratio = Double(totalExpenseCents) / Double(budget.amountCents)
                ProgressView(value: min(ratio, 1))
                    .tint(totalExpenseCents > budget.amountCents ? .red : .brand)
                Text(budgetStatus(over: totalExpenseCents > budget.amountCents))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没有设置本月预算")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func budgetStatus(over: Bool) -> String {
        guard let budget = monthBudget else { return "" }
        let remaining = budget.amountCents - totalExpenseCents
        if over {
            return "已超支 \(AmountFormat.string(cents: -remaining))"
        }
        return "剩余 \(AmountFormat.string(cents: remaining))"
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("支出分类", systemImage: "chart.pie.fill")
                .font(.headline)

            if expenseBreakdown.isEmpty {
                Text("本月还没有支出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(expenseBreakdown) { item in
                    expenseRow(item)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func expenseRow(_ item: CategorySummary) -> some View {
        let maxCents = max(expenseBreakdown.first?.amountCents ?? 1, 1)
        let ratio = Double(item.amountCents) / Double(maxCents)
        return HStack(spacing: 12) {
            CategoryIcon(iconName: item.iconName, colorHex: item.colorHex, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.categoryName)
                        .font(.subheadline)
                    Spacer()
                    Text(AmountFormat.string(cents: item.amountCents))
                        .font(.subheadline.weight(.semibold))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        Capsule()
                            .fill(Color(hex: item.colorHex))
                            .frame(width: max(geo.size.width * ratio, 8))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}
