import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var month = Calendar.current.startOfMonth(for: .now)

    private var monthTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var groupedByDay: [(day: Date, items: [Transaction])] {
        let groups = Dictionary(grouping: monthTransactions) { Calendar.current.startOfDay(for: $0.date) }
        return groups.map { (day: $0.key, items: $0.value) }.sorted { $0.day > $1.day }
    }

    private var totalExpenseCents: Int64 {
        monthTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var totalIncomeCents: Int64 {
        monthTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                MonthStepper(month: $month)
                    .padding(.vertical, 12)

                summaryCard
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                if groupedByDay.isEmpty {
                    ContentUnavailableView(
                        "这个月还没有账单",
                        systemImage: "tray",
                        description: Text("去「记一笔」添加第一笔吧")
                    )
                } else {
                    List {
                        ForEach(Array(groupedByDay.enumerated()), id: \.offset) { _, entry in
                            Section {
                                ForEach(entry.items) { transaction in
                                    TransactionRow(transaction: transaction)
                                        .swipeActions {
                                            Button(role: .destructive) {
                                                try? TransactionService(context: context).delete(transaction)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                Text(dayTitle(entry.day))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("流水")
        }
    }

    private var summaryCard: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本月支出")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Text(AmountFormat.string(cents: totalExpenseCents))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("收入 \(AmountFormat.string(cents: totalIncomeCents))")
                Text("结余 \(AmountFormat.string(cents: totalIncomeCents - totalExpenseCents, showsSign: true))")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.brand, Color.brand.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func dayTitle(_ date: Date) -> String {
        date.formatted(
            .dateTime.month(.defaultDigits).day().weekday(.abbreviated)
                .locale(Locale(identifier: "zh_CN"))
        )
    }
}

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            if let category = transaction.category {
                CategoryIcon(iconName: category.iconName, colorHex: category.colorHex, size: 40)
            } else {
                CategoryIcon(iconName: "tag", colorHex: "#9CA3AF", size: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.category?.name ?? "未分类")
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(AmountFormat.string(
                cents: transaction.kind == .expense ? -transaction.amountCents : transaction.amountCents,
                showsSign: true
            ))
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(transaction.kind == .income ? Color.income : .primary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let note = transaction.note, !note.isEmpty {
            parts.append(note)
        }
        parts.append(transaction.account.name)
        return parts.joined(separator: " · ")
    }
}
