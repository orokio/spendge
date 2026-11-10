import SwiftUI
import SwiftData

/// 今天：一句话 + 今天记了什么。只回答一个问题。
struct TodayView: View {
    let onOpenReview: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var confirmations: [DayConfirmation]

    @State private var insight: Insight?
    @State private var showSheet = false

    private var todayTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayExpenseCents: Int64 {
        todayTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var confirmedToday: Bool {
        confirmations.contains { Calendar.current.isDateInToday($0.day) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    todayList
                }
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)

            fab
        }
        .background {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                LinearGradient(
                    stops: [
                        .init(color: Color.brand.opacity(0.17), location: 0),
                        .init(color: Color.brand.opacity(0.05), location: 0.6),
                        .init(color: Color.brand.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 330)
                .ignoresSafeArea(edges: .top)
            }
        }
        .sheet(isPresented: $showSheet) {
            RecordSheet()
        }
        .task { refresh() }
        .onChange(of: transactions.count) { _, _ in refresh() }
        .onChange(of: confirmations.count) { _, _ in refresh() }
    }

    // MARK: - hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button(action: onOpenReview) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .padding(.top, 2)
                .padding(.trailing, -10)
            }
            .padding(.bottom, -4)

            Text(insight?.title ?? "正在看你的账本…")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .offset(y: 6)))

            if let detail = insight?.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    // MARK: - 今天

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if todayTransactions.isEmpty {
                emptyState
            } else {
                if todayTransactions.count > 1 || todayExpenseCents > 0 {
                    Text("今天 · \(AmountFormat.string(cents: todayExpenseCents))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    ForEach(todayTransactions) { txn in
                        row(txn)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private func row(_ txn: Transaction) -> some View {
        HStack(spacing: 14) {
            CategoryIcon(
                iconName: txn.category?.iconName ?? "tag",
                colorHex: txn.category?.colorHex ?? "#9CA3AF",
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(txn.category?.name ?? "未分类")
                    .font(.body)
                if let note = txn.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(AmountFormat.string(cents: signedCents(txn), showsSign: true))
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(txn.kind == .income ? Color.income : .primary)
        }
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            if confirmedToday {
                Label("今天确认没花钱", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.brand)
            } else {
                Text("今天还没记")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    confirmNoSpend()
                } label: {
                    Text("今天没花钱")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.brand.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.brand)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.brand, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 26)
    }

    // MARK: - 动作

    private func signedCents(_ transaction: Transaction) -> Int64 {
        transaction.kind == .expense ? -transaction.amountCents : transaction.amountCents
    }

    private func confirmNoSpend() {
        try? DayConfirmationService(context: context).confirmNoSpend()
    }

    private func refresh() {
        insight = try? InsightService(context: context).headline()
    }
}
