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
    /// 流水区滚到顶部的日期：柱图指示器和记账日期都跟着它走
    @State private var visibleDay: Date?
    /// 程序触发的滚动过程中不要让偏移量改日期，否则会打断动画
    @State private var isProgrammaticScroll = false
    /// 最近一次测到的各组位置，程序滚动结束后用它补算一次
    @State private var lastFrames: [Date: CGRect] = [:]
    /// 滚动时用来强制重算一次视图：GeometryReader 只在重算时才会汇报新位置
    @State private var scrollTick = 0

    private var selectedDay: Date {
        visibleDay ?? dayGroups.first?.day ?? calendar.startOfDay(for: .now)
    }

    private let calendar = Calendar.current
    private let barGap: CGFloat = 5

    private struct DayStat: Identifiable {
        let id: Int
        let amountCents: Int64
        let count: Int
        let hasRecord: Bool
    }

    // MARK: - 数据

    /// 首页只看当月
    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: .now)?.start ?? calendar.startOfDay(for: .now)
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(monthStart, equalTo: .now, toGranularity: .month)
    }

    private var dayTransactions: [Transaction] {
        transactions
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date < $1.date }
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

    /// 流水里的一组：一天，加上那天的记录
    private struct DayGroup: Identifiable {
        let day: Date
        let transactions: [Transaction]
        let isConfirmed: Bool

        var id: Date { day }
    }

    /// 本月有内容的日期，倒序。今天即使是空的也留着，好让「没花钱」还有入口
    private var dayGroups: [DayGroup] {
        var grouped: [Date: [Transaction]] = [:]
        for txn in transactions where calendar.isDate(txn.date, equalTo: monthStart, toGranularity: .month) {
            let key = calendar.startOfDay(for: txn.date)
            grouped[key, default: []].append(txn)
        }

        var confirmed: Set<Date> = []
        for item in confirmations where calendar.isDate(item.day, equalTo: monthStart, toGranularity: .month) {
            confirmed.insert(calendar.startOfDay(for: item.day))
        }

        // 本月已经过去的每一天都列出来：没记录的一天也要能被确认成「没花钱」
        let today = calendar.startOfDay(for: .now)
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        var days: [Date] = []
        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let start = calendar.startOfDay(for: date)
            guard start <= today else { break }
            days.append(start)
        }

        return days.sorted(by: >).map { day in
            DayGroup(day: day,
                     transactions: (grouped[day] ?? []).sorted { $0.date < $1.date },
                     isConfirmed: confirmed.contains(day))
        }
    }

    private var monthExpenseCents: Int64 {
        transactions
            .filter { $0.kind == .expense && calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
            .reduce(0) { $0 + $1.amountCents }
    }

    // MARK: - 页面

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    topBlock
                    chartBlock(proxy: proxy)
                    listBlock
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.top, 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: focus) { _, newValue in
                    guard let newValue else { return }
                    scroll(to: newValue, proxy: proxy)
                }
                .onChange(of: scenePhase) { _, phase in
                    // 从后台回来只刷新顶部那句话，不动流水的滚动位置
                    if phase == .active { refresh() }
                }
            }

            fab
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { refresh() }
        .onChange(of: transactions.count) { _, _ in
            refresh()
            if !dayTransactions.isEmpty, confirmedSelectedDay {
                try? DayConfirmationService(context: context).remove(on: selectedDay)
            }
        }
    }

    // MARK: - 顶部：情绪句（今天）或日期

    /// 顶部这句话不跟着滚动变：下面的流水滚到哪天，它都稳定待在原位
    private var topBlock: some View {
        VStack(alignment: .leading, spacing: PageLayout.inlineGap) {
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
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
    }

    /// 数字用品牌色
    private func highlighted(_ text: String) -> Text {
        Text(text).foregroundColor(.brand)
    }

    // MARK: - 柱状图

    private func chartBlock(proxy: ScrollViewProxy) -> some View {
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
                        scrollToDay(index: index, proxy: proxy)
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
                Text("流水")
                    .font(Typography.sectionTitle)
                Spacer(minLength: 12)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("本月支出")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                    Text(AmountFormat.string(cents: monthExpenseCents))
                        .font(Typography.numberSmall)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            // 高度固定，只有这一块滚动；柱图和上面那句不动
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(dayGroups) { group in
                            // 间距放在测量之外：判断「卡片是否滚出去」时不能把日期间的空白算进来
                            daySection(group)
                                .id(group.day)
                                .background(
                                    GeometryReader { inner in
                                        Color.clear.preference(
                                            key: DayFrameKey.self,
                                            value: [group.day: inner.frame(in: .named("flow"))]
                                        )
                                    }
                                )
                                .padding(.bottom, 24)
                        }
                    }
                    // 底部先留给悬浮底栏和记账按钮，再多留一整屏：
                    // 否则靠后的日期顶不到列表顶部，点它聚焦不过去
                    .padding(.bottom, max(104, geo.size.height))
                }
                .coordinateSpace(name: "flow")
                .modifier(ScrollTickModifier { scrollTick &+= 1 })
                .scrollIndicators(.hidden)
                .onPreferenceChange(DayFrameKey.self) { frames in
                    updateVisibleDay(frames)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func daySection(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(dayTitle(group.day))
                    .font(Typography.label)
                    .foregroundStyle(.secondary)

                DashedLine()
                    .stroke(Color.secondary.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .frame(height: 1)
            }

            if group.transactions.isEmpty {
                noSpendCard(group.day)
            } else {
                TransactionCard(
                    transactions: group.transactions,
                    onDelete: { txn in try? TransactionService(context: context).delete(txn) },
                    onTap: onEdit
                )
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let month = calendar.component(.month, from: day)
        let number = calendar.component(.day, from: day)
        let weekday = day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
        return "\(month)月\(number)日 \(weekday)"
    }

    /// 没有支出的一天：已确认的显示勾，今天还没记录的给一个「没花钱」入口
    /// 没有支出的一天：已确认的留一个安静的勾，今天还没记录的给一个小按钮
    private func noSpendCard(_ day: Date) -> some View {
        let confirmed = confirmations.contains { calendar.isDate($0.day, inSameDayAs: day) }
        let today = calendar.isDateInToday(day)

        return CardContainer {
            HStack(spacing: 6) {
                if confirmed {
                    Button {
                        try? DayConfirmationService(context: context).remove(on: day)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(Typography.body)
                                .foregroundStyle(Color.brand)
                            Text(today ? "今天没花钱" : "这天没花钱")
                                .font(Typography.body)
                                .foregroundStyle(Color.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(today ? "今天还没记录" : "这天没记录")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button {
                        try? DayConfirmationService(context: context).confirmNoSpend(on: day)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "circle")
                                .font(.system(size: 14, weight: .regular))
                            Text("没花钱")
                                .font(Typography.label)
                        }
                        .foregroundStyle(Color.textSecondary)
                        // 用放大的点击区代替内边距，行高才和已确认态一样
                        .contentShape(Rectangle().inset(by: -12))
                    }
                    .buttonStyle(.plain)
                }
            }
            // 两种状态用同一个高度，卡片不会忽高忽低
            .frame(height: 26)
        }
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            onOpenRecord(selectedDay)
        } label: {
            Image(systemName: "plus")
                .font(Typography.pageTitle)
                .foregroundStyle(Color.onAccent)
                .frame(width: 58, height: 58)
                .background(Color.brand, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 20)
    }

    // MARK: - 动作

    /// 聚焦日期 = 第一个还有内容露在可视区里的组。
    /// 这一天的最后一张卡片完全滚出去之后，就交给下一天，不用等它的日期头贴到顶
    private func updateVisibleDay(_ frames: [Date: CGRect]) {
        _ = scrollTick
        lastFrames = frames
        guard !isProgrammaticScroll else { return }
        recomputeVisibleDay()
    }

    /// 取第一个还有内容露在可视区里的组：这一天的最后一张卡片滚出去，才轮到下一天
    private func recomputeVisibleDay() {
        let current = dayGroups.first { group in
            guard let frame = lastFrames[group.day] else { return false }
            return frame.maxY > 0
        }
        guard let day = current?.day, day != visibleDay else { return }
        visibleDay = day
    }

    /// 点柱子：把那天滚到流水区第一行。没内容的日子不滚
    private func scrollToDay(index: Int, proxy: ScrollViewProxy) {
        guard let date = calendar.date(byAdding: .day, value: index, to: monthStart) else { return }
        scroll(to: date, proxy: proxy)
    }

    /// 把某一天对齐到流水区顶部：日期和虚线落在第一行
    private func scroll(to date: Date, proxy: ScrollViewProxy) {
        let day = calendar.startOfDay(for: date)
        guard dayGroups.contains(where: { $0.day == day }) else { return }
        isProgrammaticScroll = true
        visibleDay = day
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(day, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isProgrammaticScroll = false
            recomputeVisibleDay()
        }
    }

    private func refresh() {
        insight = try? InsightService(context: context).headline()
    }
}

/// 滚动时定时戳一下视图，让下面各组的 GeometryReader 重新汇报位置。
/// GeometryReader 只在布局重算时才会更新 frame，光靠滚动它是不动的。
private struct ScrollTickModifier: ViewModifier {
    let onTick: () -> Void
    @State private var lastOffset: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                guard abs(newOffset - lastOffset) >= 16 else { return }
                lastOffset = newOffset
                onTick()
            }
        } else {
            content
        }
    }
}

/// 每组日期在流水区里的位置
private struct DayFrameKey: SwiftUI.PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]

    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 日期之间的虚分割线
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

