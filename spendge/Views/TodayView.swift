import SwiftUI
import SwiftData

/// 今天：一句话 + 今天记了什么。只回答一个问题。
struct TodayView: View {
    let onOpenRecord: () -> Void
    let onEdit: (Transaction) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var confirmations: [DayConfirmation]

    @State private var insight: Insight?

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
                // 滚到底时最后一行要落在渐隐区之上
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)

            // 底部渐隐：与回看页一致，行滚到 ＋ 号前淡出，不做硬裁切
            LinearGradient(
                stops: [
                    .init(color: Color.canvas.opacity(0), location: 0),
                    .init(color: Color.canvas, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            fab
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 底部留白也算页面：不留形状的话那块透明区域点不中，翻页手势起不来
        .contentShape(Rectangle())
        .task { refresh() }
        .onChange(of: transactions.count) { _, _ in refresh() }
        .onChange(of: confirmations.count) { _, _ in refresh() }
    }

    // MARK: - hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: PageLayout.inlineGap) {
            highlighted(insight?.title ?? "正在看你的账本…")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .offset(y: 6)))

            if let detail = insight?.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PageLayout.pageInset)
        .padding(.top, 56)
    }

    // MARK: - 今天

    private var todayList: some View {
        // 与回看页一致：日期行到列表保持 22pt
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            // 一行：日期靠左，「今天没花钱」靠右
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(Date.now.formatted(
                        .dateTime.month(.abbreviated).day().weekday(.abbreviated)
                            .locale(.autoupdatingCurrent)
                    ))
                    if todayExpenseCents > 0 {
                        Text("·")
                        Text(AmountFormat.string(cents: todayExpenseCents))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                if todayTransactions.isEmpty {
                    Button {
                        toggleNoSpend()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: confirmedToday ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                            Text("今天没花钱")
                                .font(.footnote)
                        }
                        .foregroundStyle(confirmedToday ? Color.brand : Color.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !todayTransactions.isEmpty {
                TransactionList(
                    transactions: todayTransactions,
                    onDelete: { txn in try? TransactionService(context: context).delete(txn) },
                    onTap: onEdit
                )
            }
        }
        .padding(.horizontal, PageLayout.pageInset)
        // 情绪块到列表：比普通区块再松一档（28 + 12 = 40），与回看页一致
        .padding(.top, PageLayout.sectionGap + PageLayout.blockGap)
    }

    /// 数字用品牌色，句子本身保持中性。
    private func highlighted(_ text: String) -> Text {
        var result = Text("")
        var buffer = ""
        var bufferIsNumber = false

        for character in text {
            let isNumber = character.isNumber
            if !buffer.isEmpty, isNumber != bufferIsNumber {
                result = result + Text(buffer).foregroundColor(bufferIsNumber ? .brand : .primary)
                buffer = ""
            }
            buffer.append(character)
            bufferIsNumber = isNumber
        }
        if !buffer.isEmpty {
            result = result + Text(buffer).foregroundColor(bufferIsNumber ? .brand : .primary)
        }
        return result
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            onOpenRecord()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.brand, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 26)
    }

    // MARK: - 动作

    private func signedCents(_ transaction: Transaction) -> Int64 {
        transaction.kind == .expense ? -transaction.amountCents : transaction.amountCents
    }

    /// 点一下确认，再点一下取消——勾选必须是可逆的。
    private func toggleNoSpend() {
        let service = DayConfirmationService(context: context)
        if confirmedToday {
            try? service.remove(on: .now)
        } else {
            try? service.confirmNoSpend()
        }
    }

    private func refresh() {
        insight = try? InsightService(context: context).headline()
    }
}