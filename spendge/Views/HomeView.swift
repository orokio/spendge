import SwiftUI
import SwiftData

/// 首屏：一句话 + 今天没花钱 + 本月概览 + 最近几笔。
/// 首屏不是图表，是一句「懂你」的话——它是唯一的留存引擎。
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var confirmations: [DayConfirmation]

    @State private var insight: Insight?
    @State private var coverage: MonthCoverage?

    private var monthTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    private var todayTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var confirmedToday: Bool {
        confirmations.contains { Calendar.current.isDateInToday($0.day) }
    }

    private var totalExpenseCents: Int64 {
        monthTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var totalIncomeCents: Int64 {
        monthTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headlineCard
                    todayCard
                    summaryCard
                    recentCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今天")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TransactionListView()
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
            .task { refresh() }
            .onChange(of: transactions.count) { _, _ in refresh() }
            .onChange(of: confirmations.count) { _, _ in refresh() }
        }
    }

    // MARK: - 一句话

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight?.title ?? "正在看你的账本…")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = insight?.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - 今天

    private var todayCard: some View {
        HStack(spacing: 12) {
            Image(systemName: confirmedToday ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(confirmedToday ? Color.brand : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                if confirmedToday {
                    Text("今天已确认没花钱")
                        .font(.subheadline.weight(.medium))
                } else if todayTransactions.isEmpty {
                    Text("今天还没记")
                        .font(.subheadline.weight(.medium))
                } else {
                    Text("今天记了 \(todayTransactions.count) 笔")
                        .font(.subheadline.weight(.medium))
                }

                if let coverage {
                    Text("本月覆盖 \(coverage.coveredDays) 天 · \(Int(coverage.ratio * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !confirmedToday && todayTransactions.isEmpty {
                Button {
                    confirmNoSpend()
                } label: {
                    Text("没花钱")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.brand.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.brand)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 本月

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("这个月")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                summaryColumn(title: "支出", cents: totalExpenseCents)
                summaryColumn(title: "收入", cents: totalIncomeCents)
                summaryColumn(
                    title: "结余",
                    cents: totalIncomeCents - totalExpenseCents,
                    showsSign: true
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryColumn(title: String, cents: Int64, showsSign: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AmountFormat.string(cents: cents, showsSign: showsSign))
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 最近

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if transactions.isEmpty {
                Text("还没有记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transactions.prefix(4)) { txn in
                    HStack(spacing: 10) {
                        CategoryIcon(
                            iconName: txn.category?.iconName ?? "tag",
                            colorHex: txn.category?.colorHex ?? "#9CA3AF",
                            size: 32
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.category?.name ?? "未分类")
                                .font(.subheadline)
                            if let note = txn.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(AmountFormat.string(cents: signedCents(txn), showsSign: true))
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(txn.kind == .income ? Color.income : .primary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// 支出显示为负数，收入为正数。
    private func signedCents(_ transaction: Transaction) -> Int64 {
        transaction.kind == .expense ? -transaction.amountCents : transaction.amountCents
    }

    // MARK: - 动作

    private func confirmNoSpend() {
        try? DayConfirmationService(context: context).confirmNoSpend()
        refresh()
    }

    private func refresh() {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: .now)
        insight = try? InsightService(context: context).headline()
        coverage = try? TransactionService(context: context)
            .coverage(forMonth: comps.year ?? 2026, month: comps.month ?? 1)
    }
}
