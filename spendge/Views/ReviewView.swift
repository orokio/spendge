import Charts
import SwiftUI
import SwiftData

/// 回看：只回答一个问题——这个月过成什么样。
/// 一种时间尺度（月份），不掺日视角的交互。
struct ReviewView: View {
    /// 正在翻页：月份切换不响应，避免滑动途中弹出月份面板
    let onEdit: (Transaction) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @Query private var confirmations: [DayConfirmation]

    @State private var monthAnchor = Date()
    @State private var coverage: MonthCoverage?
    @State private var showMonthPicker = false
    @State private var selectedDomain: CategoryDomain?
    @State private var selectedDay: Date?
    @State private var pieKind: TransactionKind = .expense
    @State private var showBudgetEditor = false
    /// 页面正在滚动：此时不响应点击，避免滚动途中误开半屏
    @State private var isScrolling = false

    private let calendar = Calendar.current

    /// 一屏正好露出 12 天；一个月的柱子在屏幕上放不下，横向滚动查看
    private let barGap: CGFloat = 3
    private let daysPerScreen: CGFloat = 12

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
        monthStart.formatted(.dateTime.year().month(.wide).locale(.autoupdatingCurrent))
    }

    private var monthTransactions: [Transaction] {
        transactions.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
    }

    private var expenseTransactions: [Transaction] {
        monthTransactions.filter { $0.kind == .expense }
    }

    private var dayStats: [DayStat] {
        let daysInMonth = calendar.dayCount(inMonthOf: monthStart)
        // 整月都画出来：还没到的日子就是 0，柱子留成一道浅痕
        let dayCount = daysInMonth

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

    /// 饼图当前展示的那一类（支出 / 收入）
    private var pieTransactions: [Transaction] {
        monthTransactions.filter { $0.kind == pieKind }
    }

    private var pieRows: [(domain: CategoryDomain, cents: Int64)] {
        var totals: [CategoryDomain: Int64] = [:]
        for txn in pieTransactions {
            totals[txn.category?.domain ?? .other, default: 0] += txn.amountCents
        }
        return totals
            .map { (domain: $0.key, cents: $0.value) }
            .sorted { $0.cents > $1.cents }
    }

    /// 与饼图同源：没有数据时就是 0，不会出现「空环但中间有钱」
    private var pieTotalCents: Int64 {
        pieRows.reduce(0) { $0 + $1.cents }
    }

    private var monthBudget: Budget? {
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        return budgets.first { $0.year == comps.year && $0.month == comps.month && $0.category == nil }
    }

    private var totalExpenseCents: Int64 {
        expenseTransactions.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    header
                    budgetSection
                    if !monthTransactions.isEmpty {
                        Group {
                            if let selectedDay {
                                daySection(for: selectedDay)
                            } else {
                                pieSection
                            }
                        }
                        // 预算块到内容块之间再松一档：28 + 12 = 40
                        .padding(.top, PageLayout.blockGap)
                    }
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.top, 56)
                // 滚到底时最后一行要落在渐隐区之上
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .modifier(ScrollPhaseGate { scrolling in isScrolling = scrolling })

            // 底部渐隐：行滚到月份控件前淡出，不做硬裁切
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
            // 一直接到屏幕最底部：底部安全区里不能露出没被渐隐盖住的列表
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            monthButton
        }
        // 底部留白也算页面：不留形状的话那块透明区域点不中，翻页手势起不来
        .contentShape(Rectangle())
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(selected: monthStart) { picked in
                monthAnchor = picked
                showMonthPicker = false
            }
            .presentationDetents([.fraction(1.0 / 3.0)])
            .presentationCornerRadius(24)
            .presentationBackground(Color.surfaceElevated)
        }
        .task { refresh() }
        .onChange(of: monthAnchor) { _, _ in refresh() }
        .onChange(of: transactions.count) { _, _ in refresh() }
        .onChange(of: confirmations.count) { _, _ in refresh() }
    }

    // MARK: - 这个月

    private var header: some View {
        VStack(alignment: .leading, spacing: PageLayout.inlineGap) {
            if let coverage, coverage.coveredDays > 0 {
                Text(String(format: String(localized: "review.recordedDays"), coverage.coveredDays))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(String(format: String(localized: "review.subtitle"), monthTitle, Int(coverage.ratio * 100)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("这个月还没有记录")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(monthTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            sparkline
                // 副标题到时间轴：行内 8 + 这里 4 = 块内 12
                .padding(.top, PageLayout.blockGap - PageLayout.inlineGap)
        }
    }

    /// 柱状图：柱高 = 当天几笔。柱子固定宽度，横向可滚，一个月都放得下。
    private var sparkline: some View {
        GeometryReader { geo in
            let width = barWidth(for: geo.size.width)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: barGap) {
                            ForEach(dayStats) { stat in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(barColor(stat))
                                    .frame(width: width, height: barHeight(stat, maxCount: maxDayCount))
                                    .id(stat.id)
                            }
                        }
                        .frame(height: 44, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let index = Int(location.x / (width + barGap))
                            openDay(at: min(max(index, 0), dayStats.count - 1))
                        }

                        HStack(spacing: barGap) {
                            ForEach(dayStats) { stat in
                                Text(dayLabel(stat.id))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: width)
                            }
                        }
                    }
                    // 上下留白同时是触摸区：手指更容易落在图上，不会误触翻页
                    .padding(.vertical, 8)
                }
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: monthAnchor) { _, _ in scrollToEnd(proxy, animated: false) }
            }
        }
        .frame(height: 82)
    }

    /// 一屏 12 天：按可用宽度算出柱宽
    private func barWidth(for available: CGFloat) -> CGFloat {
        max(14, (available - barGap * (daysPerScreen - 1)) / daysPerScreen)
    }

    /// 当月停在今天（最右），往月停在月初
    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        let target: Int?
        let anchor: UnitPoint
        if isCurrentMonth {
            target = min(calendar.component(.day, from: .now), dayStats.last?.id ?? 1)
            anchor = .trailing
        } else {
            target = dayStats.first?.id
            anchor = .leading
        }
        guard let target else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: anchor) }
        } else {
            proxy.scrollTo(target, anchor: anchor)
        }
    }

    private var maxDayCount: Int {
        max(dayStats.map(\.count).max() ?? 1, 1)
    }

    private func barColor(_ stat: DayStat) -> Color {
        // 还没到的日子更淡一点：那不是「漏记」，只是还没到
        if isCurrentMonth, stat.id > calendar.component(.day, from: .now) {
            return Color.secondary.opacity(0.08)
        }
        guard stat.hasRecord else { return Color.secondary.opacity(0.16) }
        if let selectedDay, calendar.isDate(selectedDay, equalTo: monthStart, toGranularity: .month) {
            let selectedComponent = calendar.component(.day, from: selectedDay)
            return stat.id == selectedComponent ? Color.brand : Color.brand.opacity(0.25)
        }
        // 没有选中时所有柱子同色，不再单独强调今天
        return Color.brand.opacity(0.6)
    }

    /// 柱高表示当天记了几笔：按当月最大笔数归一化，高度与笔数严格成正比。
    private func barHeight(_ stat: DayStat, maxCount: Int) -> CGFloat {
        guard stat.hasRecord else { return 2 }
        guard stat.count > 0 else { return 8 }
        let ratio = Double(stat.count) / Double(max(maxCount, 1))
        return 8 + 32 * ratio
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
                Text(monthStart.formatted(.dateTime.month(.abbreviated).locale(.autoupdatingCurrent)))
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .foregroundStyle(Color.secondary)
            .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.trailing, PageLayout.pageInset)
        .padding(.bottom, 26)
    }

    // MARK: - 吃的

    // MARK: - 钱花在哪儿

    // MARK: - 钱花在哪儿

    private var pieSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pieKind == .expense ? "钱花在哪儿" : "钱从哪来")
                .font(.headline)

            // 先列占比，再看饼图：数字比扇形面积更容易比较
            // 没有数据时，这句提示占据图例的位置
            if pieRows.isEmpty {
                Text(pieKind == .expense ? "这个月还没有支出" : "这个月还没有收入")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, PageLayout.blockGap)
            } else {
                // 与标题同一条边线：不再额外内缩
                pieLegend
                    .padding(.top, PageLayout.blockGap)
            }

            pieChart
                .padding(.top, PageLayout.blockGap)
        }
    }

    /// 饼图本身。某一类为空也照常画（空环）：中心按钮必须一直在，否则切过去就回不来了
    /// 没有数据时给一个灰色的整圈占位，形状与有数据时一致
    private var chartRows: [(domain: CategoryDomain, cents: Int64)] {
        pieRows.isEmpty ? [(domain: .other, cents: 1)] : pieRows
    }

    private var pieChart: some View {
        Chart(chartRows, id: \.domain) { row in
            SectorMark(
                angle: .value("金额", row.cents),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .foregroundStyle(color(for: row.domain))
            .cornerRadius(3)
        }
        .frame(height: 170)
        .chartLegend(.hidden)
        // overlay 必须在 padding 之前：否则它的居中是「图表 + 上边距」的居中，金额会比圆心高出一截
        .overlay {
            // 点中心切换支出 / 收入；金额严格居中，标签挂在下方
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    pieKind = pieKind == .expense ? .income : .expense
                }
            } label: {
                ZStack {
                    Text(AmountFormat.string(cents: pieTotalCents))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(pieKind == .expense ? "支出" : "收入")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .offset(y: 26)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var pieLegend: some View {
        VStack(spacing: 12) {
            ForEach(pieRows, id: \.domain) { row in
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: row.domain))
                        .frame(width: 10, height: 10)
                    Text(LocalizedStringKey(row.domain.displayName))
                        .font(.body)
                    Spacer()
                    Text(percentText(row.cents))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    // 百分比与金额之间的一条灰色短横线，前面留出更宽的间隔
                    Text("—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .padding(.leading, 26)
                    Text(AmountFormat.string(cents: row.cents))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }
            }
        }
    }

    private func percentText(_ cents: Int64) -> String {
        guard pieTotalCents > 0 else { return "" }
        return "\(Int((Double(cents) / Double(pieTotalCents) * 100).rounded()))%"
    }

    /// 领域配色由主题提供，换主题时饼图与图例一起变
    private func color(for domain: CategoryDomain) -> Color {
        Palette.current.domainColor(domain)
    }

    // MARK: - 某一天的明细

    private func daySection(for day: Date) -> some View {
        let items = transactions(on: day)
        return VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            Text(day.formatted(.dateTime.month(.abbreviated).day().weekday(.wide).locale(.autoupdatingCurrent)))
                .font(.headline)

            if items.isEmpty {
                Text("那天没有记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                TransactionList(
                    transactions: items,
                    spacing: 14,
                    onDelete: { txn in try? TransactionService(context: context).delete(txn) },
                    onTap: onEdit
                )
            }
        }
    }

    private var budgetSection: some View {
        Button {
            // 滚动途中不响应，避免手指划过时误开面板
            guard !isScrolling else { return }
            showBudgetEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("预算")
                    .font(.headline)

                Text(budgetDescription())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let budget = monthBudget, budget.amountCents > 0 {
                    // 进度条表示「还剩多少」：预算 3000、花了 600 → 绿色 80%（2400）
                    ProgressView(value: max(0, 1 - Double(totalExpenseCents) / Double(budget.amountCents)))
                        .tint(Color.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showBudgetEditor) {
            BudgetEditorSheet(
                monthTitle: monthTitle,
                initialCents: monthBudget?.amountCents,
                onSave: saveBudget,
                onClear: clearBudget
            )
            // 与月份选择面板保持一致的半层高度
            .presentationDetents([.fraction(1.0 / 3.0)])
            .presentationCornerRadius(24)
            .presentationBackground(Color.surfaceElevated)
        }
    }

    /// 陈述句，不做红黄绿告警
    private func budgetDescription() -> String {
        guard let budget = monthBudget else {
            return "设置一个数，用来对照这个月花到哪儿了"
        }
        let remaining = budget.amountCents - totalExpenseCents
        if remaining >= 0 {
            return String(
                format: String(localized: "review.spentLeft"),
                AmountFormat.string(cents: totalExpenseCents),
                AmountFormat.string(cents: remaining)
            )
        }
        return String(
            format: String(localized: "review.spentOver"),
            AmountFormat.string(cents: totalExpenseCents),
            AmountFormat.string(cents: -remaining)
        )
    }

    private func saveBudget(_ cents: Int64) {
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        try? BudgetService(context: context).setBudget(
            category: nil,
            amountCents: cents,
            year: comps.year ?? 2026,
            month: comps.month ?? 1
        )
    }

    private func clearBudget() {
        guard let budget = monthBudget else { return }
        try? BudgetService(context: context).deleteBudget(budget)
    }

    /// 点柱子看那天的流水；再点同一根回到月度饼图。
    private func openDay(at index: Int) {
        guard dayStats.indices.contains(index) else { return }
        guard let date = calendar.date(byAdding: .day, value: index, to: monthStart) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDay = calendar.isDate(date, inSameDayAs: selectedDay ?? .distantPast) ? nil : date
        }
    }

    private func transactions(on day: Date) -> [Transaction] {
        transactions
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    private func refresh() {
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        coverage = try? TransactionService(context: context)
            .coverage(forMonth: comps.year ?? 2026, month: comps.month ?? 1)
    }
}

/// 把「这个滚动容器正在滚」翻译成一个开关：滚动期间翻页手势让路。
/// iOS 18 用滚动阶段；更早的系统退化成「手指一动就算」。
private struct ScrollPhaseGate: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                switch phase {
                case .idle: onChange(false)
                default: onChange(true)
                }
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in onChange(true) }
                    .onEnded { _ in onChange(false) }
            )
        }
    }
}

/// 设置某个月的预算：只做一个总额，不提醒、不变色。
private struct BudgetEditorSheet: View {
    let monthTitle: String
    let initialCents: Int64?
    let onSave: (Int64) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(monthTitle: String,
         initialCents: Int64?,
         onSave: @escaping (Int64) -> Void,
         onClear: @escaping () -> Void) {
        self.monthTitle = monthTitle
        self.initialCents = initialCents
        self.onSave = onSave
        self.onClear = onClear
        _text = State(initialValue: initialCents.map { Self.text(fromCents: $0) } ?? "")
    }

    private static func text(fromCents cents: Int64) -> String {
        cents % 100 == 0 ? String(cents / 100) : String(format: "%.2f", Double(cents) / 100)
    }

    private var cents: Int64? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: "")), value > 0 else { return nil }
        return Int64((value * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text(String(format: String(localized: "review.budgetTitle"), monthTitle))
                    .font(.headline)

                Spacer()

                if initialCents != nil {
                    Button {
                        onClear()
                        dismiss()
                    } label: {
                        Text("清除预算")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let cents {
                        onSave(cents)
                        dismiss()
                    }
                } label: {
                    Text("保存")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cents == nil ? Color.secondary : Color.brand)
                }
                .buttonStyle(.plain)
                .disabled(cents == nil)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.brand)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }
}

/// 选择月份。不用导航栏，避免滚动时顶部出现半透明效果。
private struct MonthPickerSheet: View {
    let selected: Date
    let onPick: (Date) -> Void

    private var options: [Date] {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: .now)
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: base) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("选择月份")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { date in
                        Button {
                            onPick(date)
                        } label: {
                            HStack {
                                Text(date.formatted(.dateTime.year().month(.wide).locale(.autoupdatingCurrent)))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if Calendar.current.isDate(date, equalTo: selected, toGranularity: .month) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.brand)
                                }
                            }
                            .padding(.horizontal, PageLayout.pageInset)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color.surfaceElevated)
    }
}