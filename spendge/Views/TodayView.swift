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
    @State private var sheetOffset = UIScreen.main.bounds.width

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if showSheet {
                RecordPage(onClose: closeSheet)
                    .offset(x: sheetOffset)
                    .zIndex(1)
            }
        }
        .task { refresh() }
        .onChange(of: transactions.count) { _, _ in refresh() }
        .onChange(of: confirmations.count) { _, _ in refresh() }
    }

    // MARK: - hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 28)
    }

    // MARK: - 今天

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 一行：日期靠左，「今天没花钱」靠右
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(Date.now.formatted(
                        .dateTime.month(.abbreviated).day().weekday(.abbreviated)
                            .locale(Locale(identifier: "zh_CN"))
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
        HStack(alignment: .bottom, spacing: 12) {
            // 回看入口：小一号、低对比，作为手势的兜底
            Button(action: onOpenReview) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .frame(height: 58, alignment: .bottom)

            Button {
                openSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.brand, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 26)
    }

    // MARK: - 动作

    private func signedCents(_ transaction: Transaction) -> Int64 {
        transaction.kind == .expense ? -transaction.amountCents : transaction.amountCents
    }

    /// 先把页面放到屏幕右侧，再动画拉进来：避免插入瞬间闪出一帧完整内容。
    private func openSheet() {
        sheetOffset = UIScreen.main.bounds.width
        showSheet = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            sheetOffset = 0
        }
    }

    private func closeSheet() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            sheetOffset = UIScreen.main.bounds.width
        } completion: {
            showSheet = false
        }
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