import SwiftUI
import SwiftData

/// 首页：一句话 + 当月柱图 + 当天明细。
/// 左右滑动切换日期；从后台回来、启动、记完一笔都会把视图聚焦到对应那天。
struct TodayView: View {
    let onOpenRecord: (Date) -> Void
    let onEdit: (Transaction) -> Void
    /// 外部要求聚焦的日期（启动、回到前台、记完一笔）
    var focus: Date?

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var confirmations: [DayConfirmation]

    @State private var insight: Insight?
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current
    private let barGap: CGFloat = 5

    private struct DayStat: Identifiable {
        let id: Int
        let amountCents: Int64
        let count: Int
        let hasRecord: Bool
    }

    // MARK: - 数据

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: selectedDay)?.start ?? selectedDay
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(monthStart, equalTo: .now, toGranularity: .month)
    }

    private var isToday: Bool {
        calendar.isDateInToday(selectedDay)
    }

    private var dayTransactions: [Transaction] {
        transactions
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date < $1.date }
    }

    private var dayExpenseCents: Int64 {
        dayTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var dayStats: [DayStat] {
        let daysInMonth = max(calendar.dayCount(inMonthOf: monthStart), 1)
        let monthTxns = transactions.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }

        var amounts: [Int: Int64] = [:]
        var counts: [Int: Int] = [:]
        var recorded: Set<Int> = []

        for txn in monthTxns {
            let day = calendar.component(.day, from: txn.date)
            recorded.insert(day)
            counts[day, default: 0] += 1
            if txn.kind == .expense {
                amounts[day, default: 0] += txn.amountCents
            }
        }
        for item in confirmations where calendar.isDate(item.day, equalTo: monthStart, toGranularity: .month) {
            recorded.insert(calendar.component(.day, from: item.day))
        }

        return (1...daysInMonth).map { day in
            DayStat(id: day, amountCents: amounts[day] ?? 0,
                    count: counts[day] ?? 0, hasRecord: recorded.contains(day))
        }
    }

    private var selectedSlot: Int? {
        guard calendar.isDate(selectedDay, equalTo: monthStart, toGranularity: .month) else { return nil }
        return calendar.component(.day, from: selectedDay)
    }

    private var confirmedSelectedDay: Bool {
        confirmations.contains { calendar.isDate($0.day, inSameDayAs: selectedDay) }
    }

    // MARK: - 页面

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    topBlock
                    chartBlock
                    listBlock
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.top, 56)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)

            fab
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -40 { moveDay(by: 1) }
                    else if value.translation.width > 40 { moveDay(by: -1) }
                }
        )
        .task { refresh() }
        .onAppear {
            if let focus { selectedDay = calendar.startOfDay(for: focus) }
        }
        .onChange(of: focus) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedDay = calendar.startOfDay(for: newValue)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                selectedDay = calendar.startOfDay(for: .now)
                refresh()
            }
        }
        .onChange(of: selectedDay) { _, _ in refresh() }
        .onChange(of: transactions.count) { _, _ in
            refresh()
            if !dayTransactions.isEmpty, confirmedSelectedDay {
                try? DayConfirmationService(context: context).remove(on: selectedDay)
            }
        }
    }

    // MARK: - 顶部：情绪句（今天）或日期

    @ViewBuilder
    private var topBlock: some View {
        VStack(alignment: .leading, spacing: PageLayout.inlineGap) {
            if isToday {
                // 主句与副句同一行：高度固定，下面的柱图不会因为有没有副句而上下跳
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(insight?.title ?? "正在看你的账本…")
                        .font(Typography.hero)
                        .foregroundStyle(Color.brand)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = insight?.detail {
                        Text(detail)
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(selectedDay.formatted(
                    .dateTime.month(.abbreviated).day().weekday(.wide).locale(Locale(identifier: "zh_CN"))
                ))
                .font(Typography.pageTitle)
            }
        }
        // 有没有副句、是情绪还是日期，顶部块高度都一致，柱图不会上下跳
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
    }

    /// 数字用品牌色
    private func highlighted(_ text: String) -> Text {
        Text(text).foregroundColor(.brand)
    }

    // MARK: - 柱状图

    private var chartBlock: some View {
        let stats = dayStats
        let maxCents = max(stats.map(\.amountCents).max() ?? 0, 1)
        let height: CGFloat = 76
        let shown = stats.count
        let slots = 31

        return GeometryReader { geo in
            let width = max(1, (geo.size.width - barGap * CGFloat(slots - 1)) / CGFloat(slots))
            let contentWidth = CGFloat(shown) * width + CGFloat(max(shown - 1, 0)) * barGap
            let inset = max(0, (geo.size.width - contentWidth) / 2)

            VStack(spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: barGap) {
                        ForEach(1...shown, id: \.self) { slot in
                            RoundedRectangle(cornerRadius: width / 2)
                                .fill(barFill(day: slot, amount: stats[slot - 1].amountCents))
                                .frame(width: width,
                                       height: barHeight(stats[slot - 1].amountCents, maxCents: maxCents, height: height))
                        }
                    }
                    .frame(height: height, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let index = Int(location.x / (width + barGap))
                        guard index < shown else { return }
                        selectDay(index: index)
                    }
                    .padding(.horizontal, inset)

                    if let slot = selectedSlot {
                        let barCenter = inset + CGFloat(slot - 1) * (width + barGap) + width / 2
                        let tooltipWidth: CGFloat = 150

                        Path { path in
                            path.move(to: CGPoint(x: barCenter, y: 0))
                            path.addLine(to: CGPoint(x: barCenter, y: height))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.3))

                        tooltip(slot: slot, amount: stats[slot - 1].amountCents, count: stats[slot - 1].count)
                            .offset(x: min(max(0, barCenter - tooltipWidth / 2), geo.size.width - tooltipWidth),
                                    y: -(height + 6))
                    }
                }

                HStack(spacing: barGap) {
                    ForEach(1...shown, id: \.self) { slot in
                        Text(slot == 1 || slot % 5 == 0 ? "\(slot)" : " ")
                            .font(Typography.axisLabel)
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .frame(width: width)
                    }
                }
                .padding(.horizontal, inset)
            }
        }
        .frame(height: 100)
    }

    private func barFill(day: Int, amount: Int64) -> Color {
        if isCurrentMonth, day > calendar.component(.day, from: .now) {
            return Color.secondary.opacity(0.06)
        }
        let stat = dayStats.first { $0.id == day }
        if let stat, stat.hasRecord, amount == 0 {
            return Color.brand.opacity(0.18)
        }
        guard amount > 0 else { return Color.secondary.opacity(0.10) }
        return day == selectedSlot ? Color.brand : Color.brand.opacity(0.30)
    }

    private func barHeight(_ amount: Int64, maxCents: Int64, height: CGFloat) -> CGFloat {
        guard amount > 0 else { return 0 }
        return max(4, height * CGFloat(Double(amount) / Double(maxCents)))
    }

    private func tooltip(slot: Int, amount: Int64, count: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: slot - 1, to: monthStart) ?? monthStart
        return (
            Text(date.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "zh_CN"))))
                .foregroundStyle(.secondary)
            + Text("  \(AmountFormat.string(cents: amount)) · \(count) 笔")
                .fontWeight(.semibold)
        )
        .font(Typography.caption)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: - 列表

    private var listBlock: some View {
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? "今日流水" : "当日流水")
                    .font(Typography.sectionTitle)
                Spacer(minLength: 12)
                if dayExpenseCents > 0 {
                    Text("支出合计 \(AmountFormat.string(cents: dayExpenseCents))")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                }
            }

            if dayTransactions.isEmpty {
                emptyCard
            } else {
                TransactionCard(
                    transactions: dayTransactions,
                    onDelete: { txn in try? TransactionService(context: context).delete(txn) },
                    onTap: onEdit
                )
            }
        }
    }

    private var emptyCard: some View {
        CardContainer {
            HStack(spacing: 6) {
                if confirmedSelectedDay {
                    // 已确认：点一下可以撤销，回到「还没记录」
                    Button {
                        toggleNoSpend()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(Typography.body)
                            Text(isToday ? "今天没花钱" : "这天没花钱")
                                .font(Typography.label)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.brand)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if isFutureDay {
                    Text("还没到这天")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    Text(isToday ? "今天还没记录" : "这天没记录")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button {
                        toggleNoSpend()
                    } label: {
                        Text("没花钱")
                            .font(Typography.label)
                            .foregroundStyle(Color.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var isFutureDay: Bool {
        calendar.startOfDay(for: selectedDay) > calendar.startOfDay(for: .now)
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            onOpenRecord(selectedDay)
        } label: {
            Image(systemName: "plus")
                .font(Typography.pageTitle)
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.brand, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 20)
    }

    // MARK: - 动作

    private func toggleNoSpend() {
        let service = DayConfirmationService(context: context)
        if confirmedSelectedDay {
            try? service.remove(on: selectedDay)
        } else {
            try? service.confirmNoSpend(on: selectedDay)
        }
    }

    private func selectDay(index: Int) {
        guard let date = calendar.date(byAdding: .day, value: index, to: monthStart) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDay = date
        }
    }

    private func moveDay(by delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: selectedDay) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDay = next
        }
    }

    private func refresh() {
        insight = try? InsightService(context: context).headline()
    }
}
