import SwiftUI
import SwiftData

/// 统计：按月 / 按年看钱花在哪。一个下拉选期间，没有图表。
struct ReviewView: View {
    let onEdit: (Transaction) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    /// 「今天没花钱」的确认。曲线里它也算有数据的一天
    @Query(sort: \DayConfirmation.day, order: .reverse) private var confirmations: [DayConfirmation]

    /// 当前查看的期间：某个月，或某一整年
    @State private var period: Period = .month(Date())
    @State private var showPicker = false
    /// 分类默认只露前三行，其余折起来
    @State private var showAllCategories = false

    private let calendar = Calendar.current

    enum Period: Equatable {
        case month(Date)
        case year(Int)

        var title: String {
            let calendar = Calendar.current
            switch self {
            case .month(let date):
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                return "\(year)年\(month)月"
            case .year(let year):
                return "\(year)年"
            }
        }
    }

    private struct CategoryRow: Identifiable {
        let id: String
        let cents: Int64
        let count: Int
        /// 用来取图标与颜色；分类被删掉时为空
        let category: Category?
    }

    // MARK: - 数据

    private var scopedTransactions: [Transaction] {
        switch period {
        case .month(let date):
            return transactions.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
        case .year(let year):
            return transactions.filter { calendar.component(.year, from: $0.date) == year }
        }
    }

    private var categoryRows: [CategoryRow] {
        var cents: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        var categories: [String: Category] = [:]
        for txn in scopedTransactions where txn.kind == .expense {
            let name = txn.category?.name ?? "未分类"
            cents[name, default: 0] += txn.amountCents
            counts[name, default: 0] += 1
            if let category = txn.category { categories[name] = category }
        }
        return cents
            .map { CategoryRow(id: $0.key, cents: $0.value, count: counts[$0.key] ?? 0,
                               category: categories[$0.key]) }
            .sorted { $0.cents > $1.cents }
    }

    private var totalCents: Int64 {
        categoryRows.reduce(0) { $0 + $1.cents }
    }

    /// 可选期间：有记录的月份倒序排列，每年 1 月后面跟一个「整年」
    private var periodOptions: [Period] {
        let months = transactions.compactMap { txn -> Date? in
            calendar.dateInterval(of: .month, for: txn.date)?.start
        }
        let uniqueMonths = Array(Set(months)).sorted(by: >)
        let currentMonth = calendar.dateInterval(of: .month, for: .now)?.start
        let allMonths = Set(uniqueMonths + [currentMonth].compactMap { $0 }).sorted(by: >)

        var result: [Period] = []
        var seenYears: Set<Int> = []
        for month in allMonths {
            result.append(.month(month))
            let year = calendar.component(.year, from: month)
            let isJanuary = calendar.component(.month, from: month) == 1
            let isLastOfYear = !allMonths.contains { calendar.component(.year, from: $0) == year && $0 < month }
            if (isJanuary || isLastOfYear), !seenYears.contains(year) {
                result.append(.year(year))
                seenYears.insert(year)
            }
        }
        return result
    }

    // MARK: - 页面

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                headerBlock
                VStack(alignment: .leading, spacing: PageLayout.blockGap) {
                    Text("花钱节奏")
                        .font(Typography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    insightCard
                }
                VStack(alignment: .leading, spacing: PageLayout.blockGap) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("支出分类")
                            .font(Typography.sectionTitle)
                        Spacer(minLength: 12)
                        Text("共 \(categoryRows.reduce(0) { $0 + $1.count }) 笔")
                            .font(Typography.label)
                            .foregroundStyle(.secondary)
                    }
                    domainSection
                }
            }
            .padding(.horizontal, PageLayout.pageInset)
            .padding(.top, 56)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showPicker) {
            PeriodPickerSheet(options: periodOptions, selected: period) { picked in
                period = picked
                showPicker = false
            }
            .presentationDetents([.fraction(0.45)])
            .presentationCornerRadius(24)
            .presentationBackground(Color.surfaceElevated)
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Text(period.title)
                            .font(Typography.pageTitle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.textPrimary)
                }
                .buttonStyle(.plain)

            }
        }
    }

    // MARK: - 洞察

    /// 一句话洞察：主句是事实（其中一个数字放大），副句只给视角、不评价
    private struct InsightText {
        let before: String
        let highlight: String
        let after: String
        let sub: String
    }

    private var expenses: [Transaction] {
        scopedTransactions.filter { $0.kind == .expense }
    }

    private var periodWord: String {
        if case .year = period { return "这一年" }
        return "这个月"
    }

    private var previousWord: String {
        if case .year = period { return "去年" }
        return "上月"
    }

    /// 优先级：结构 → 频次 → 时间 → 金额分布 → 对比 → 兜底
    private var insight: InsightText {
        let items = expenses
        guard !items.isEmpty else {
            return InsightText(before: periodWord, highlight: "还没有", after: "支出",
                               sub: "记下第一笔，这里就会有结论")
        }
        let word = periodWord

        // 1. 结构：某一类占 60% 以上，才算「大多去了同一个地方」
        if let top = categoryRows.first, totalCents > 0 {
            let share = Int((Double(top.cents) / Double(totalCents) * 100).rounded())
            if share >= 60 {
                return InsightText(before: "\(word) ", highlight: "\(share)%", after: " 花在了\(top.id)",
                                   sub: "钱大多去了同一个地方")
            }
        }

        // 2. 频次：有多少天被记下来（仅月档）
        if case .month = period {
            let days = Set(items.map { calendar.startOfDay(for: $0.date) }).count
            if days >= 3 {
                return InsightText(before: "\(word)有 ", highlight: "\(days)", after: " 天被记下来",
                                   sub: "空着的那几天，也在过日子")
            }
        }

        // 3. 时间：晚上记的账占比
        let evening = items.filter { calendar.component(.hour, from: $0.date) >= 18 }.count
        if items.count >= 6 {
            let share = Int(Double(evening) / Double(items.count) * 100)
            if share >= 60 {
                return InsightText(before: "\(word)的账，", highlight: "\(share)%", after: " 记在晚上",
                                   sub: "晚上手松一点，也正常")
            }
        }

        // 4. 金额分布：单笔中位数
        if items.count >= 4 {
            let median = medianYuan(items.map { $0.amountCents })
            return InsightText(before: "一半的支出在 ", highlight: "\(median)", after: " 元以下",
                               sub: "这些才是\(word == "这一年" ? "这一年" : "这个月")的日子")
        }

        // 5. 对比：和上一个周期比
        if let change = comparisonPercent(), abs(change) >= 20 {
            let direction = change > 0 ? "多花了" : "少花了"
            let tail = change > 0 ? "" : ""
            return InsightText(before: "\(word)比\(previousWord)\(direction) ", highlight: "\(abs(change))%", after: tail,
                               sub: change > 0 ? "花得快一点，也正常" : "省下来的，都在账上")
        }

        // 6. 兜底
        return InsightText(before: "\(word)记了 ", highlight: "\(items.count)", after: " 笔",
                           sub: "先记着，慢慢就有样子了")
    }

    private func medianYuan(_ cents: [Int64]) -> Int64 {
        let sorted = cents.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        let value = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return max(1, value / 100)
    }

    /// 与上一个周期的总额变化（百分比）；上一周期没有数据时返回 nil
    private func comparisonPercent() -> Int? {
        let previous: Int64
        switch period {
        case .month(let date):
            guard let previousDate = calendar.date(byAdding: .month, value: -1, to: date) else { return nil }
            previous = transactions
                .filter { calendar.isDate($0.date, equalTo: previousDate, toGranularity: .month) && $0.kind == .expense }
                .reduce(0) { $0 + $1.amountCents }
        case .year(let year):
            previous = transactions
                .filter { calendar.component(.year, from: $0.date) == year - 1 && $0.kind == .expense }
                .reduce(0) { $0 + $1.amountCents }
        }
        guard previous > 0 else { return nil }
        return Int(((Double(totalCents) - Double(previous)) / Double(previous) * 100).rounded())
    }

    private var insightCard: some View {
        let text = insight
        let hasData = !expenses.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            if hasData {
                HStack(alignment: .firstTextBaseline) {
                    Text("累计支出")
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.brand)
                            .frame(width: 12, height: 2.5)
                        Text(curveRangeLabel)

                        HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.textSecondary.opacity(0.45))
                                        .frame(width: 2.5, height: 2.5)
                                }
                        }
                        .padding(.leading, 6)
                        Text(previousCurveLabel)
                    }
                }
                .font(Typography.captionStrong)
                .foregroundStyle(Color.textSecondary)

                cumulativeCurve
                    .padding(.top, 8)

                statRow
                    .padding(.top, 14)
            }

            // 主句与副句并成一段：灰字，只有数字保留品牌色
            (Text(text.before).foregroundColor(Color.textSecondary)
             + Text(text.highlight).foregroundColor(Color.brand)
             + Text(text.after).foregroundColor(Color.textSecondary)
             + Text("，").foregroundColor(Color.textSecondary)
             + Text(text.sub).foregroundColor(Color.textSecondary))
                .font(Typography.body.weight(.semibold))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
    }

    // MARK: - 累计曲线

    /// 曲线上的一个点：从期间开始累计到这一天的支出
    private struct CurvePoint {
        let cents: Int64
        /// 这一天（年档是一个月）有没有数据。
        /// 有支出、或确认过「没花钱」都算有数据；只有彻底空着的一天才是灰线
        let isCovered: Bool
    }

    /// 已确认「没花钱」的日子，按零点对齐
    private var confirmedDays: Set<Date> {
        Set(confirmations.map { calendar.startOfDay(for: $0.day) })
    }

    /// 日累计（年档为月累计）。第一天之前补一个 0 起点，曲线从底部长出来
    private var curvePoints: [CurvePoint] {
        var result = [CurvePoint(cents: 0, isCovered: false)]
        let confirmed = confirmedDays
        switch period {
        case .month(let date):
            let dayCount = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            let isCurrent = calendar.isDate(date, equalTo: .now, toGranularity: .month)
            let limit = isCurrent ? calendar.component(.day, from: .now) : dayCount
            guard let start = calendar.dateInterval(of: .month, for: date)?.start else { return result }
            var running: Int64 = 0
            for day in 1...max(1, limit) {
                guard let dayDate = calendar.date(byAdding: .day, value: day - 1, to: start) else { continue }
                let dayTotal = expenses
                    .filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
                    .reduce(0) { $0 + $1.amountCents }
                running += dayTotal
                let covered = dayTotal > 0 || confirmed.contains(calendar.startOfDay(for: dayDate))
                result.append(CurvePoint(cents: running, isCovered: covered))
            }
        case .year(let year):
            let isCurrent = calendar.component(.year, from: .now) == year
            let limit = isCurrent ? calendar.component(.month, from: .now) : 12
            var running: Int64 = 0
            for month in 1...max(1, limit) {
                let monthTotal = expenses
                    .filter { calendar.component(.month, from: $0.date) == month }
                    .reduce(0) { $0 + $1.amountCents }
                running += monthTotal
                let covered = monthTotal > 0 || confirmations.contains {
                    calendar.component(.year, from: $0.day) == year
                    && calendar.component(.month, from: $0.day) == month
                }
                result.append(CurvePoint(cents: running, isCovered: covered))
            }
        }
        return result
    }

    /// 期间里最大的一笔，曲线上只标这一个 tooltip
    private var largestExpense: Transaction? {
        expenses.max { $0.amountCents < $1.amountCents }
    }

    /// 最大那笔落在曲线的第几个点上
    private var largestIndex: Int? {
        guard let txn = largestExpense else { return nil }
        let index: Int
        switch period {
        case .month:
            index = calendar.component(.day, from: txn.date)
        case .year:
            index = calendar.component(.month, from: txn.date)
        }
        return index < curvePoints.count ? index : nil
    }

    /// 横轴分几格：月档是当月天数，年档是 12 个月
    private var slotCount: Int {
        switch period {
        case .month(let date):
            return calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        case .year:
            return 12
        }
    }

    /// 横轴刻度：月档标 1、5、10…，年档标每个月
    private var axisTicks: [Int] {
        switch period {
        case .month:
            let count = slotCount
            guard count > 1 else { return [1] }
            var ticks = [1]
            var day = 5
            while day <= count - 3 {
                ticks.append(day)
                day += 5
            }
            ticks.append(count)
            return ticks
        case .year:
            return Array(1...12)
        }
    }

    /// 曲线区的坐标换算。抽出来是因为 ViewBuilder 里不能放局部函数
    private struct CurveFrame {
        let width: CGFloat
        let height: CGFloat
        let slots: Int
        let maxValue: CGFloat

        let topInset: CGFloat = 32
        let axisHeight: CGFloat = 18
        let hInset: CGFloat = 3

        var plotWidth: CGFloat { max(1, width - hInset * 2) }
        var usable: CGFloat { max(1, height - topInset - axisHeight) }
        var plot: CGRect { CGRect(x: hInset, y: topInset, width: plotWidth, height: usable) }

        func x(slot: Int) -> CGFloat {
            hInset + plotWidth * CGFloat(slot) / CGFloat(max(1, slots))
        }

        func y(cents: Int64) -> CGFloat {
            topInset + usable * (1 - CGFloat(Double(cents)) / maxValue)
        }
    }

    /// 上期同期的累计：月档是上月 1 号到上月同一天，年档是去年同月份。
    /// 没有数据时返回空，图上就不画这条线
    private var previousCurvePoints: [Int64] {
        switch period {
        case .month(let date):
            guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: date),
                  let previousDays = calendar.range(of: .day, in: .month, for: previousMonth)?.count,
                  let start = calendar.dateInterval(of: .month, for: previousMonth)?.start
            else { return [] }
            let isCurrent = calendar.isDate(date, equalTo: .now, toGranularity: .month)
            let limit = isCurrent
                ? min(calendar.component(.day, from: .now), previousDays)
                : previousDays
            var result: [Int64] = []
            var running: Int64 = 0
            for day in 1...max(1, limit) {
                guard let dayDate = calendar.date(byAdding: .day, value: day - 1, to: start) else { continue }
                running += transactions
                    .filter { $0.kind == .expense && calendar.isDate($0.date, inSameDayAs: dayDate) }
                    .reduce(0) { $0 + $1.amountCents }
                result.append(running)
            }
            return result
        case .year(let year):
            let isCurrent = calendar.component(.year, from: .now) == year
            let limit = isCurrent ? calendar.component(.month, from: .now) : 12
            var result: [Int64] = []
            var running: Int64 = 0
            for month in 1...max(1, limit) {
                running += transactions
                    .filter {
                        $0.kind == .expense
                        && calendar.component(.year, from: $0.date) == year - 1
                        && calendar.component(.month, from: $0.date) == month
                    }
                    .reduce(0) { $0 + $1.amountCents }
                result.append(running)
            }
            return result
        }
    }

    private var previousCurveLabel: String {
        if case .year = period { return "去年" }
        return "上月"
    }

    private var cumulativeCurve: some View {
        let points = curvePoints
        let previous = previousCurvePoints
        let slots = slotCount
        let ticks = axisTicks
        let tipIndex = largestIndex
        let tip = largestExpense

        return GeometryReader { geo in
            // 两条线共用同一根纵轴，谁高按谁定
            let frame = CurveFrame(
                width: geo.size.width,
                height: geo.size.height,
                slots: slots,
                maxValue: CGFloat(max(1, max(points.last?.cents ?? 0, previous.last ?? 0)))
            )
            let coords = points.enumerated().map { index, point in
                CGPoint(x: frame.x(slot: index), y: frame.y(cents: point.cents))
            }
            let previousCoords: [CGPoint]? = (previous.last ?? 0) > 0
                ? previous.enumerated().map { index, cents in
                    CGPoint(x: frame.x(slot: index + 1), y: frame.y(cents: cents))
                }
                : nil

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawCurve(context: &context,
                              points: points,
                              coords: coords,
                              previousCoords: previousCoords,
                              plot: frame.plot,
                              tipIndex: tipIndex)
                }

                // 横轴：1 日到月末
                ForEach(ticks, id: \.self) { tick in
                    Text("\(tick)")
                        .font(Typography.axisLabel)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 24)
                        .position(x: min(max(frame.x(slot: tick), 12), frame.width - 12),
                                  y: frame.height - frame.axisHeight / 2)
                }

                if let tipIndex = tipIndex, let tip = tip, tipIndex < coords.count {
                    let anchor = coords[tipIndex]
                    let cx = min(max(anchor.x, 52), max(52, frame.width - 52))
                    let cy = max(10, anchor.y - 16)
                    tooltip(tip).position(x: cx, y: cy)
                }
            }
        }
        .frame(height: 136)
    }

    /// 实线是本月累计，虚线是上月同期：同一时刻两条线的高差，就是节奏差
    private func drawCurve(context: inout GraphicsContext,
                           points: [CurvePoint],
                           coords: [CGPoint],
                           previousCoords: [CGPoint]?,
                           plot: CGRect,
                           tipIndex: Int?) {
        guard coords.count > 1 else { return }

        // 背景横线：顶部一条作上限，中间两条把纵向分成三格
        let gridColor = Color.textSecondary.opacity(0.10)
        for level in 0...2 {
            let gy = plot.minY + plot.height * CGFloat(level) / 3
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: gy))
            line.addLine(to: CGPoint(x: plot.maxX, y: gy))
            context.stroke(line, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.8))
        }

        // 底轴
        var axis = Path()
        axis.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        axis.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(axis,
                       with: .color(Color.textSecondary.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 1))

        // 上月同期
        if let previousCoords, previousCoords.count > 1 {
            var previousPath = Path()
            previousPath.addLines(previousCoords)
            context.stroke(
                previousPath,
                with: .color(Color.textSecondary.opacity(0.45)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [4, 4])
            )
        }

        // 有记录的日子是实线，没记录的日子压成浅灰
        let emptyColor = Color.textSecondary.opacity(0.30)
        for i in 1..<coords.count {
            var seg = Path()
            seg.move(to: coords[i - 1])
            seg.addLine(to: coords[i])
            let isCovered = points[i].isCovered
            context.stroke(
                seg,
                with: .color(isCovered ? Color.brand : emptyColor),
                style: StrokeStyle(
                    lineWidth: isCovered ? 2.5 : 1.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }

        guard let tipIndex = tipIndex, tipIndex < coords.count else { return }
        let anchor = coords[tipIndex]
        let halo = CGRect(x: anchor.x - 7, y: anchor.y - 7, width: 14, height: 14)
        context.fill(Path(ellipseIn: halo), with: .color(Color.brand.opacity(0.14)))
        let dot = CGRect(x: anchor.x - 3.5, y: anchor.y - 3.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: dot), with: .color(Color.brand))
    }

    private func tooltip(_ txn: Transaction) -> some View {
        HStack(spacing: 4) {
            Text(txn.category?.name ?? "未分类")
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
            Text(AmountFormat.string(cents: txn.amountCents))
                .font(Typography.captionStrong)
                .foregroundStyle(Color.textPrimary)
        }
        .fixedSize()
    }

    // MARK: - 曲线下的三个数

    /// 三格连成一条：共用绿底，之间只用一道竖短线分隔
    private var statRow: some View {
        HStack(spacing: 0) {
            statCell(title: "日均支出",
                     value: AmountFormat.string(cents: averageCents),
                     tint: Color.brand)
            statSeparator
            statCell(title: periodTotalTitle,
                     value: AmountFormat.string(cents: totalCents),
                     tint: Color.textPrimary)
            statSeparator
            changeCell
        }
        .padding(.vertical, 11)
        .background(Color.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statSeparator: some View {
        Rectangle()
            .fill(Color.brand.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    private func statCell(title: String,
                          value: String,
                          tint: Color,
                          arrow: String? = nil) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(value)
                    .font(Typography.numberSmall)
                    .foregroundStyle(tint)
                if let arrow {
                    Image(systemName: arrow)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var periodTotalTitle: String {
        if case .year = period { return "全年累计" }
        return "本月累计"
    }

    /// 曲线右上角的范围说明
    private var curveRangeLabel: String {
        switch period {
        case .month(let date):
            if calendar.isDate(date, equalTo: .now, toGranularity: .month) { return "本月" }
            return "\(calendar.component(.month, from: date))月"
        case .year(let year):
            return "\(year)年"
        }
    }

    /// 涨用暖黄，跌用品牌绿，没得比就灰着
    private var changeCell: some View {
        let title = periodTotalTitle == "全年累计" ? "较去年同期" : "较上月同期"
        guard let percent = changePercent, percent != 0 else {
            return statCell(title: title, value: "—", tint: Color.textSecondary)
        }
        let tint = percent > 0 ? Color.warning : Color.brand
        return statCell(title: title,
                        value: "\(abs(percent))%",
                        tint: tint,
                        arrow: percent > 0 ? "arrow.up" : "arrow.down")
    }

    /// 日均：当前周期只算到今天，过去的周期算满
    private var averageCents: Int64 {
        let elapsed: Int
        switch period {
        case .month(let date):
            if calendar.isDate(date, equalTo: .now, toGranularity: .month) {
                elapsed = calendar.component(.day, from: .now)
            } else {
                elapsed = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            }
        case .year(let year):
            if calendar.component(.year, from: .now) == year {
                elapsed = calendar.ordinality(of: .day, in: .year, for: .now) ?? 1
            } else {
                let reference = calendar.date(from: DateComponents(year: year, month: 6, day: 1)) ?? .now
                elapsed = calendar.range(of: .day, in: .year, for: reference)?.count ?? 365
            }
        }
        return totalCents / Int64(max(1, elapsed))
    }

    /// 同期对比：本月对到今天的上月同日，今年对到上月。
    /// 直接拿整月比会在月中永远显示下降。
    private var changePercent: Int? {
        let now = Date()
        let previousCents: Int64
        switch period {
        case .month(let date):
            guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: date),
                  let monthRange = calendar.range(of: .day, in: .month, for: previousMonth) else { return nil }
            let isCurrent = calendar.isDate(date, equalTo: now, toGranularity: .month)
            let limit = isCurrent
                ? min(calendar.component(.day, from: now), monthRange.count)
                : monthRange.count
            previousCents = transactions
                .filter {
                    $0.kind == .expense
                    && calendar.isDate($0.date, equalTo: previousMonth, toGranularity: .month)
                    && calendar.component(.day, from: $0.date) <= limit
                }
                .reduce(0) { $0 + $1.amountCents }
        case .year(let year):
            let isCurrent = calendar.component(.year, from: now) == year
            let limit = isCurrent ? calendar.component(.month, from: now) : 12
            previousCents = transactions
                .filter {
                    $0.kind == .expense
                    && calendar.component(.year, from: $0.date) == year - 1
                    && calendar.component(.month, from: $0.date) <= limit
                }
                .reduce(0) { $0 + $1.amountCents }
        }
        guard previousCents > 0 else { return nil }
        return Int(((Double(totalCents) - Double(previousCents)) / Double(previousCents) * 100).rounded())
    }

    // MARK: - 钱花在哪

    private var domainSection: some View {
        CardContainer {
            if categoryRows.isEmpty {
                Text("这段时间还没有支出")
                    .font(Typography.label)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(displayedRows) { row in
                        categoryRow(
                            iconName: row.category?.iconName ?? "tag",
                            colorHex: row.category?.colorHex ?? "#9CA3AF",
                            name: row.id,
                            cents: row.cents,
                            count: row.count
                        )
                    }

                    // 折叠时多出来的分类并成一行
                    if !restRows.isEmpty {
                        categoryRow(iconName: "ellipsis",
                                    colorHex: "#9CA3AF",
                                    name: "其余 \(restRows.count) 类",
                                    cents: restRows.reduce(0) { $0 + $1.cents },
                                    count: restRows.reduce(0) { $0 + $1.count },
                                    isSummary: true)
                    }

                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard categoryRows.count > 3 else { return }
            withAnimation(.snappy(duration: 0.28)) { showAllCategories.toggle() }
        }
    }

    private var displayedRows: [CategoryRow] {
        guard !showAllCategories, categoryRows.count > 3 else { return categoryRows }
        return Array(categoryRows.prefix(3))
    }

    private var restRows: [CategoryRow] {
        guard !showAllCategories, categoryRows.count > 3 else { return [] }
        return Array(categoryRows.dropFirst(3))
    }

    /// 单行：图标 · 分类名 · 笔数 —— 留空 —— 迷你进度条 · 金额
    /// - Parameter isSummary: 「其余 N 类」那一行，字号小一档、整体压灰、不画进度条
    private func categoryRow(iconName: String,
                             colorHex: String,
                             name: String,
                             cents: Int64,
                             count: Int,
                             isSummary: Bool = false) -> some View {
        let ratio = totalCents > 0 ? CGFloat(Double(cents) / Double(totalCents)) : 0
        return HStack(spacing: 8) {
            CategoryIcon(iconName: iconName, colorHex: colorHex, size: 24)

            Text(name)
                .font(isSummary ? Typography.label : Typography.body)
                .foregroundStyle(isSummary ? Color.textSecondary : Color.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 66, alignment: .leading)

            Text("\(count) 笔")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            Spacer(minLength: 8)

            if !isSummary {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.textSecondary.opacity(0.12))
                        .frame(width: 48, height: 5)
                    Capsule()
                        .fill(Color.brand.opacity(0.55))
                        .frame(width: max(4, 48 * ratio), height: 5)
                }
            }

            Text(AmountFormat.string(cents: cents))
                .font(isSummary ? Typography.label : Typography.numberSmall)
                .foregroundStyle(isSummary ? Color.textSecondary : Color.textPrimary)
                .frame(width: 72, alignment: .trailing)
        }
    }

}

/// 期间选择：月份与整年混在一条时间线上
struct PeriodPickerSheet: View {
    let options: [ReviewView.Period]
    let selected: ReviewView.Period
    let onPick: (ReviewView.Period) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("选择期间")
                .font(Typography.sectionTitle)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Button {
                            onPick(option)
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(Color.textPrimary)
                                if case .year = option {
                                    Text("全年")
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if option == selected {
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
