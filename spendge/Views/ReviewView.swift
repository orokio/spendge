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

    @State private var monthAnchor = Date()
    @State private var coverage: MonthCoverage?
    @State private var showMonthPicker = false

    private let calendar = Calendar.current

    private struct DayStat: Identifiable {
        let id: Int
        let count: Int
        let hasRecord: Bool
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: monthAnchor)?.start ?? monthAnchor
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(monthStart, equalTo: .now, toGranularity: .month)
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    private var monthTransactions: [Transaction] {
        transactions.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
    }

    private var expenseTransactions: [Transaction] {
        monthTransactions.filter { $0.kind == .expense }
    }

    private var dayStats: [DayStat] {
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        // 当月只画到今天：未来的日期不是「缺口」
        let dayCount = isCurrentMonth ? calendar.component(.day, from: .now) : daysInMonth

        var counts: [Int: Int] = [:]
        var recorded: Set<Int> = []

        for txn in monthTransactions {
            let day = calendar.component(.day, from: txn.date)
            recorded.insert(day)
            counts[day, default: 0] += 1
        }
        for item in confirmations where calendar.isDate(item.day, equalTo: monthStart, toGranularity: .month) {
            recorded.insert(calendar.component(.day, from: item.day))
        }

        return (1...max(dayCount, 1)).map { day in
            DayStat(id: day, count: counts[day] ?? 0, hasRecord: recorded.contains(day))
        }
    }

    private var homemadeDays: Int {
        let days = expenseTransactions
            .filter { $0.category?.categoryCode == .grocery }
            .map { calendar.startOfDay(for: $0.date) }
        return Set(days).count
    }

    private func count(_ code: CategoryCode) -> Int {
        expenseTransactions.filter { $0.category?.categoryCode == code }.count
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
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        return budgets.first { $0.year == comps.year && $0.month == comps.month && $0.category == nil }
    }

    private var totalExpenseCents: Int64 {
        expenseTransactions.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                if !monthTransactions.isEmpty {
                    dietSection
                    if !domainRows.isEmpty { domainSection }
                }
                if monthBudget != nil { budgetSection }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottomTrailing) {
            monthButton
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(selected: monthStart) { picked in
                monthAnchor = picked
                showMonthPicker = false
            }
            .presentationDetents([.medium])
            .presentationCornerRadius(24)
            .presentationBackground(Color(.systemBackground))
        }
        .task { refresh() }
        .onChange(of: monthAnchor) { _, _ in refresh() }
        .onChange(of: transactions.count) { _, _ in refresh() }
        .onChange(of: confirmations.count) { _, _ in refresh() }
    }

    // MARK: - 这个月

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monthTitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let coverage, coverage.coveredDays > 0 {
                Text("\(coverage.coveredDays) 天有你的记录")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("覆盖 \(Int(coverage.ratio * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("这个月还没有记录")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }

            sparkline
                .padding(.top, 6)
        }
    }

    /// 静态柱状图：柱高 = 当天几笔，缺口是 2pt 的细线。
    private var sparkline: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(dayStats) { stat in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(stat))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(stat))
                }
            }
            .frame(height: 32, alignment: .bottom)

            HStack(spacing: 2) {
                ForEach(dayStats) { stat in
                    Text(dayLabel(stat.id))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barColor(_ stat: DayStat) -> Color {
        guard stat.hasRecord else { return Color.secondary.opacity(0.16) }
        let isToday = isCurrentMonth && calendar.component(.day, from: .now) == stat.id
        return Color.brand.opacity(isToday ? 1 : 0.6)
    }

    /// 柱高表示当天记了几笔——这根条讲的是记录密度，不是金额结构。
    private func barHeight(_ stat: DayStat) -> CGFloat {
        guard stat.hasRecord else { return 2 }
        guard stat.count > 0 else { return 8 }
        return min(30, 8 + CGFloat(stat.count) * 7)
    }

    private func dayLabel(_ day: Int) -> String {
        guard day == 1 || day % 5 == 0 else { return "" }
        return "\(day)"
    }

    private var monthButton: some View {
        Button {
            showMonthPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brand)
                Text(monthStart.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "zh_CN"))))
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .foregroundStyle(Color.brand)
            .overlay(Capsule().stroke(Color.brand.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 26)
    }

    // MARK: - 吃的

    private var dietSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("吃的")
                .font(.headline)

            HStack(spacing: 0) {
                statColumn(value: "\(homemadeDays)", unit: "天", title: "买菜")
                statColumn(value: "\(count(.takeout))", unit: "次", title: "外卖")
                statColumn(value: "\(count(.dineout))", unit: "次", title: "下馆子")
                statColumn(value: "\(count(.drink))", unit: "杯", title: "咖啡奶茶")
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
                Text("这个月还没有支出")
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
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        coverage = try? TransactionService(context: context)
            .coverage(forMonth: comps.year ?? 2026, month: comps.month ?? 1)
    }
}

/// 选择月份。只列最近 12 个月，够用且不用面对日历。
private struct MonthPickerSheet: View {
    let selected: Date
    let onPick: (Date) -> Void

    private var options: [Date] {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: .now)
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: base) }
    }

    var body: some View {
        NavigationStack {
            List(options, id: \.self) { date in
                Button {
                    onPick(date)
                } label: {
                    HStack {
                        Text(date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                            .foregroundStyle(.primary)
                        Spacer()
                        if Calendar.current.isDate(date, equalTo: selected, toGranularity: .month) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brand)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle("选择月份")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(Color(.systemBackground))
    }
}
