import SwiftUI
import SwiftData

/// 统计：按月 / 按年看收支结构。一个下拉选期间，支出侧带一级饼图。
struct ReviewView: View {
    let onEdit: (Transaction) -> Void
    let onOpenCategory: (CategoryScope) -> Void

    @Environment(\.modelContext) private var context
    @ObservedObject private var catalog = CategoryCatalog.shared
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil },
           sort: [SortDescriptor<Transaction>(\Transaction.date, order: .reverse),
                  SortDescriptor<Transaction>(\Transaction.createdAt, order: .reverse)])
    private var transactions: [Transaction]

    /// 当前查看的期间：某个月，或某一整年
    @State private var period: Period = .month(Date())
    @State private var showPicker = false
    /// 当前下钻的一级分类，默认吃
    @State private var selectedDomain: String? = CategoryDomain.food.rawValue
    /// 下方展示支出还是收入
    @State private var mode: StatMode = .expense

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
        let category: CategoryInfo?
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
        return rows(from: scopedTransactions.filter { $0.kind == .expense })
    }

    /// 按分类把一批账单归并成行，支出与收入共用
    private func rows(from items: [Transaction]) -> [CategoryRow] {
        var cents: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        var categories: [String: CategoryInfo] = [:]
        for txn in items {
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

    private enum StatMode {
        case expense
        case income
    }

    var body: some View {
        let _ = LaunchTrace.once("review.body")
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                headerBlock
                savingsCard
                modeSwitch

                if mode == .expense {
                    expenseContent
                } else {
                    incomeContent
                }
            }
            .padding(.horizontal, PageLayout.pageInset)
            .padding(.top, 56)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            Analytics.record(.reviewOpened, ["mode": mode == .expense ? "expense" : "income",
                                             "period": isYear ? "year" : "month"])
        }
        .sheet(isPresented: $showPicker) {
            PeriodPickerSheet(options: periodOptions,
                              selected: period) { picked in
                period = picked
                showPicker = false
            }
            .presentationDetents([.fraction(0.45)])
            .presentationCornerRadius(24)
            .presentationBackground(Color.surfaceElevated)
        }
    }

    private var headerBlock: some View {
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
        .padding(.bottom, 8)
    }

    // MARK: - 收支总览与切换

    /// 收入 / 支出 / 结余 / 储蓄率。不随下方的切换变
    private var savingsCard: some View {
        let surplus = surplusCents
        let rate = savingsRate

        return CardContainer {
            HStack(alignment: .center, spacing: 0) {
                statCell(title: "收入",
                         value: AmountFormat.string(cents: incomeTotalCents),
                         tint: Color.info,
                         valueFont: .system(size: 17, weight: .bold, design: .rounded))
                statCell(title: "支出",
                         value: AmountFormat.string(cents: totalCents),
                         tint: Color.textPrimary,
                         valueFont: .system(size: 17, weight: .bold, design: .rounded))
                statCell(title: "结余",
                         value: AmountFormat.string(cents: surplus, showsSign: true),
                         tint: surplus < 0 ? Color.danger : Color.brand,
                         valueFont: .system(size: 17, weight: .bold, design: .rounded))

                Rectangle()
                    .fill(Color.textSecondary.opacity(0.18))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 14)

                statCell(title: "储蓄率",
                         value: rate.map { "\($0)%" } ?? "—",
                         tint: (rate ?? 0) < 0 ? Color.danger : Color.brand,
                         valueFont: .system(size: 17, weight: .bold, design: .rounded),
                         expands: false)
            }
            .padding(.vertical, 4)
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton("支出", value: .expense)
            modeButton("收入", value: .income)
        }
        .padding(3)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    /// 与记一笔页的收支切换同款
    private func modeButton(_ title: String, value: StatMode) -> some View {
        let selected = mode == value
        return Button {
            withAnimation(.snappy(duration: 0.22)) { mode = value }
        } label: {
            Text(title)
                .font(selected ? Typography.bodyStrong : Typography.body)
                .foregroundStyle(selected ? Color.textPrimary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    selected ? Color.surfaceElevated : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }

    private var expenseContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isYear {
                yearlyCurveCard(title: "花钱节奏",
                                points: monthlyPoints(kind: .expense),
                                tint: Color.brand)
            } else {
                rhythmCard
            }
            structureCard(title: "支出结构",
                          fixedLabel: "刚性",
                          variableLabel: "弹性",
                          fixed: rigidCents,
                          variable: flexibleCents,
                          fixedNames: rigidNames,
                          variableNames: flexibleNames,
                          suffix: "等")
            domainSection
        }
    }

    private var incomeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isYear {
                yearlyCurveCard(title: "收入节奏",
                                points: monthlyPoints(kind: .income),
                                tint: Color.info)
            }
            structureCard(title: "收入结构",
                          fixedLabel: "稳定",
                          variableLabel: "浮动",
                          fixed: stableIncomeCents,
                          variable: incomeTotalCents - stableIncomeCents,
                          fixedNames: stableIncomeNames,
                          variableNames: floatingIncomeNames,
                          suffix: "…")
            incomeSourceCard
            surplusCard
        }
    }

    // MARK: - 花钱节奏

    private var rhythmCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("花钱节奏")
                        .font(Typography.bodyStrong)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 8)
                    if refundCents > 0 {
                        Text("含退款 −\(AmountFormat.string(cents: refundCents))")
                            .font(Typography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                statRow
            }
        }
    }

    /// 当前期间内退款总额（退款记录存负数，这里取绝对值展示）
    private var refundCents: Int64 {
        scopedTransactions
            .filter { $0.refundOfID != nil }
            .reduce(into: Int64(0)) { $0 += abs($1.amountCents) }
    }

    // MARK: - 年度曲线（按月）

    private var isYear: Bool {
        if case .year = period { return true }
        return false
    }

    private struct MonthPoint: Identifiable {
        let month: Int
        let cents: Int64
        var id: Int { month }
    }

    /// 选中那一年的分月合计；今年只画到当月，没到的月份不画成 0
    private func monthlyPoints(kind: TransactionKind) -> [MonthPoint] {
        guard case .year(let year) = period else { return [] }
        let isCurrentYear = calendar.component(.year, from: Date()) == year
        let lastMonth = isCurrentYear ? calendar.component(.month, from: Date()) : 12
        guard lastMonth > 0 else { return [] }

        return (1...lastMonth).map { month in
            let cents = transactions
                .filter {
                    $0.kind == kind
                    && calendar.component(.year, from: $0.date) == year
                    && calendar.component(.month, from: $0.date) == month
                }
                .reduce(into: Int64(0)) { $0 += $1.amountCents }
            return MonthPoint(month: month, cents: cents)
        }
    }

    private func yearlyCurveCard(title: String, points: [MonthPoint], tint: Color) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Typography.bodyStrong)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 12)
                    Text("按月")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                if points.allSatisfy({ $0.cents == 0 }) {
                    Text("这一年还没有记录")
                        .font(Typography.label)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 104)
                } else {
                    monthlyCurve(points, tint: tint)
                }
            }
        }
    }

    private func monthlyCurve(_ points: [MonthPoint], tint: Color) -> some View {
        let axisMax = niceCeiling(points.map(\.cents).max() ?? 0)
        let levels: [Int64] = [axisMax, axisMax / 2, 0]

        return VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let gutter: CGFloat = 44
                let plotWidth = width - gutter
                let slot = plotWidth / CGFloat(max(1, points.count))
                let inset: CGFloat = 10

                let coordinates = points.enumerated().map { index, point in
                    CGPoint(
                        x: gutter + slot * (CGFloat(index) + 0.5),
                        y: axisY(point.cents, max: axisMax, height: height, inset: inset)
                    )
                }

                ZStack {
                    // 纵轴：0 / 一半 / 顶，横向刻度线只铺在绘图区
                    ForEach(levels, id: \.self) { level in
                        let y = axisY(level, max: axisMax, height: height, inset: inset)

                        Rectangle()
                            .fill(Color.textSecondary.opacity(level == 0 ? 0.18 : 0.10))
                            .frame(width: plotWidth, height: 1)
                            .position(x: gutter + plotWidth / 2, y: y)

                        Text(AmountFormat.string(cents: level))
                            .font(Typography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: gutter - 8, alignment: .trailing)
                            .position(x: (gutter - 8) / 2, y: y)
                    }

                    if let first = coordinates.first, let last = coordinates.last {
                        // 线下方一层很淡的渐变，收住曲线，不让它悬空
                        curvePath(coordinates, closingTo: height - inset)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.16), tint.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        curvePath(coordinates)
                            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        Circle()
                            .fill(Color.surfaceElevated)
                            .frame(width: 3, height: 3)
                            .position(first)
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .position(last)
                    }
                }
            }
            .frame(height: 120)

            HStack(spacing: 0) {
                ForEach(points) { point in
                    Text("\(point.month)")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, 44)
        }
    }

    /// 纵轴刻度：向上取整到 1 / 2 / 5 × 10^n，标签才不会出现 ¥2,137 这种数
    private func niceCeiling(_ cents: Int64) -> Int64 {
        guard cents > 0 else { return 100 }
        let yuan = Double(cents) / 100
        let magnitude = pow(10, floor(log10(yuan)))
        let normalized = yuan / magnitude
        let step: Double
        if normalized <= 1 {
            step = 1
        } else if normalized <= 2 {
            step = 2
        } else if normalized <= 5 {
            step = 5
        } else {
            step = 10
        }
        return Int64((step * magnitude * 100).rounded())
    }

    private func axisY(_ cents: Int64, max axisMax: Int64, height: CGFloat, inset: CGFloat) -> CGFloat {
        let usable = height - inset * 2
        return height - inset - CGFloat(cents) / CGFloat(max(1, axisMax)) * usable
    }

    /// 单调三次插值（Fritsch–Carlson）：平滑，但不会冲出两个数据点的范围。
    /// 用普通 Catmull-Rom 时，0 收入月份两侧的斜率会把曲线压到零线以下。
    private func curvePath(_ points: [CGPoint], closingTo baseline: CGFloat? = nil) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }

        if let baseline {
            path.move(to: CGPoint(x: first.x, y: baseline))
            path.addLine(to: first)
        } else {
            path.move(to: first)
        }

        guard points.count > 1 else {
            if let baseline {
                path.addLine(to: CGPoint(x: first.x, y: baseline))
                path.closeSubpath()
            }
            return path
        }

        let count = points.count
        var secants = [CGFloat](repeating: 0, count: count - 1)
        for index in 0..<(count - 1) {
            let dx = points[index + 1].x - points[index].x
            secants[index] = dx == 0 ? 0 : (points[index + 1].y - points[index].y) / dx
        }

        var tangents = [CGFloat](repeating: 0, count: count)
        tangents[0] = secants[0]
        tangents[count - 1] = secants[count - 2]
        for index in 1..<(count - 1) {
            tangents[index] = secants[index - 1] * secants[index] <= 0
                ? 0
                : (secants[index - 1] + secants[index]) / 2
        }

        // 限制切线长度，保证每一段都落在两个端点之间
        for index in 0..<(count - 1) {
            let secant = secants[index]
            guard secant != 0 else {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }
            let alpha = tangents[index] / secant
            let beta = tangents[index + 1] / secant
            let magnitude = alpha * alpha + beta * beta
            if magnitude > 9 {
                let scale = 3 / magnitude.squareRoot()
                tangents[index] = scale * alpha * secant
                tangents[index + 1] = scale * beta * secant
            }
        }

        for index in 0..<(count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let dx = (end.x - start.x) / 3
            let control1 = CGPoint(x: start.x + dx, y: start.y + tangents[index] * dx)
            let control2 = CGPoint(x: end.x - dx, y: end.y - tangents[index + 1] * dx)
            path.addCurve(to: end, control1: control1, control2: control2)
        }

        if let baseline {
            path.addLine(to: CGPoint(x: last.x, y: baseline))
            path.closeSubpath()
        }
        return path
    }

    // MARK: - 结构（刚性 / 弹性、稳定 / 浮动）

    private func structureCard(title: String,
                               fixedLabel: String,
                               variableLabel: String,
                               fixed: Int64,
                               variable: Int64,
                               fixedNames: [String],
                               variableNames: [String],
                               suffix: String) -> some View {
        let total = fixed + variable
        let hasData = total > 0
        let fixedRatio = hasData ? Double(fixed) / Double(total) : 0
        let fixedColor = Color.info

        return CardContainer {
            VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
                Text(title)
                    .font(Typography.bodyStrong)
                    .foregroundStyle(Color.textPrimary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))

                        if hasData {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(fixedColor)
                                    .frame(width: geo.size.width * fixedRatio)
                                Rectangle()
                                    .fill(Color.brand)
                            }
                            .clipShape(Capsule())
                        }

                        // 两段的标识直接写在条里，左右各靠一边
                        if hasData {
                            HStack(spacing: 0) {
                                if fixedRatio >= 0.15 {
                                    Text("\(fixedLabel) \(Int((fixedRatio * 100).rounded()))%")
                                }
                                Spacer(minLength: 6)
                                if fixedRatio <= 0.85 {
                                    Text("\(variableLabel) \((100 - Int((fixedRatio * 100).rounded())))%")
                                }
                            }
                            .font(Typography.captionStrong)
                            .foregroundStyle(Color.onAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(height: 30)

                // 条下面补灰字：金额在前，分类名紧跟在金额后面，不另起一行
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AmountFormat.string(cents: fixed))
                        .font(Typography.captionStrong)
                    if !fixedNames.isEmpty {
                        Text(fixedNames.joined(separator: "、") + suffix)
                            .font(Typography.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(AmountFormat.string(cents: variable))
                        .font(Typography.captionStrong)
                }
                .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - 收入：钱从哪来

    private var incomeSourceCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("钱从哪来")
                        .font(Typography.bodyStrong)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 12)
                    Text("共 \(incomeRows.reduce(0) { $0 + $1.count }) 笔")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                if incomeRows.isEmpty {
                    Text("这段时间还没有收入")
                        .font(Typography.label)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(incomeRows) { row in
                            categoryRow(
                                iconName: row.category?.iconName ?? "tag",
                                colorHex: row.category?.colorHex ?? "#9CA3AF",
                                name: row.id,
                                cents: row.cents,
                                count: row.count,
                                baseCents: incomeTotalCents
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let category = row.category { openCategory(category) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 近 6 个月结余

    private var surplusCard: some View {
        let months = lastSixMonths
        let average = months.isEmpty
            ? 0
            : months.reduce(0) { $0 + $1.cents } / Int64(months.count)

        return CardContainer {
            VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("近 6 个月结余")
                        .font(Typography.bodyStrong)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 8)
                    Text("平均 \(AmountFormat.string(cents: average, showsSign: average < 0))")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                surplusChart(months)
            }
        }
    }

    private func surplusChart(_ months: [MonthSurplus]) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let slot = width / CGFloat(max(1, months.count))
                let barWidth = min(30, slot * 0.55)
                let maxUp = max(0, months.map(\.cents).max() ?? 0)
                let maxDown = max(0, -(months.map(\.cents).min() ?? 0))
                let range = CGFloat(max(1, maxUp + maxDown))
                let zeroY = height * CGFloat(maxUp) / range

                ZStack(alignment: .topLeading) {
                    // 零线：有负结余时它会在中间
                    Rectangle()
                        .fill(Color.textSecondary.opacity(0.18))
                        .frame(width: width, height: 1)
                        .position(x: width / 2, y: zeroY)

                    ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                        // 没有收支的月份不画，避免在零线上留一排绿短横
                        if month.cents != 0 {
                            let value = CGFloat(month.cents)
                            let barHeight = abs(value) / range * height
                            let x = slot * (CGFloat(index) + 0.5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(month.cents > 0 ? Color.brand : Color.danger)
                                .frame(width: barWidth, height: max(2, barHeight))
                                .position(x: x,
                                          y: value > 0 ? zeroY - barHeight / 2 : zeroY + barHeight / 2)
                        }
                    }
                }
            }
            .frame(height: 96)

            HStack(spacing: 0) {
                ForEach(months) { month in
                    Text("\(calendar.component(.month, from: month.monthStart))月")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - 三个金额标签

    /// 三格连成一条：共用绿底，之间只用一道竖短线分隔
    private var statRow: some View {
        HStack(spacing: 0) {
            statCell(title: "日均支出",
                     value: AmountFormat.string(cents: averageCents),
                     tint: Color.textPrimary)
            statSeparator
            changeCell
            statSeparator
            statCell(title: periodTotalTitle,
                     value: AmountFormat.string(cents: totalCents),
                     tint: Color.textPrimary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(Color.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statSeparator: some View {
        Rectangle()
            .fill(Color.textSecondary.opacity(0.18))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 12)
    }

    /// 标签在上、金额在下，靠左对齐
    private func statCell(title: String,
                          value: String,
                          tint: Color,
                          arrow: String? = nil,
                          valueFont: Font = Typography.numberSmall,
                          expands: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 2) {
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let arrow {
                    Image(systemName: arrow)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
    }

    private var periodTotalTitle: String {
        if case .year = period { return "全年累计" }
        return "本月累计"
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

    // MARK: - 收支数据

    private var incomes: [Transaction] {
        scopedTransactions.filter { $0.kind == .income }
    }

    /// 把当前期间换算成区间，和分类一起交给明细页
    private func openCategory(_ category: CategoryInfo) {
        let start: Date
        let end: Date
        switch period {
        case .month(let date):
            let range = calendar.dateInterval(of: .month, for: date)
            start = range?.start ?? date
            end = range?.end ?? date
        case .year(let year):
            start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
            end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? .now
        }
        onOpenCategory(CategoryScope(category: category,
                                     title: period.title,
                                     start: start,
                                     end: end))
    }

    private var incomeTotalCents: Int64 {
        incomes.reduce(0) { $0 + $1.amountCents }
    }

    private var incomeRows: [CategoryRow] {
        rows(from: incomes)
    }

    /// 结余 = 收入 − 支出
    private var surplusCents: Int64 {
        incomeTotalCents - totalCents
    }

    /// 储蓄率 = 结余 / 收入；没有收入时没有意义
    private var savingsRate: Int? {
        guard incomeTotalCents > 0 else { return nil }
        return Int((Double(surplusCents) / Double(incomeTotalCents) * 100).rounded())
    }

    private var rigidCents: Int64 {
        categoryRows
            .filter { $0.category?.categoryCode?.isFixed == true }
            .reduce(0) { $0 + $1.cents }
    }

    private var flexibleCents: Int64 {
        totalCents - rigidCents
    }

    private var rigidNames: [String] {
        categoryRows
            .filter { $0.category?.categoryCode?.isFixed == true }
            .map(\.id)
    }

    private var flexibleNames: [String] {
        categoryRows
            .filter { $0.category?.categoryCode?.isFixed != true }
            .map(\.id)
    }

    private var stableIncomeCents: Int64 {
        incomes
            .filter { $0.category?.categoryCode?.isFixed == true }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var stableIncomeNames: [String] {
        incomeRows
            .filter { $0.category?.categoryCode?.isFixed == true }
            .map(\.id)
    }

    private var floatingIncomeNames: [String] {
        incomeRows
            .filter { $0.category?.categoryCode?.isFixed != true }
            .map(\.id)
    }

    private struct MonthSurplus: Identifiable {
        let monthStart: Date
        let cents: Int64

        var id: Date { monthStart }
    }

    /// 含本月在内的最近 6 个月，和当前选中的期间无关
    private var lastSixMonths: [MonthSurplus] {
        let now = Date()
        let currentStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var result: [MonthSurplus] = []

        for offset in stride(from: 5, through: 0, by: -1) {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: currentStart),
                  let interval = calendar.dateInterval(of: .month, for: month) else { continue }
            let items = transactions.filter { $0.date >= interval.start && $0.date < interval.end }
            let income = items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
            let expense = items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
            result.append(MonthSurplus(monthStart: interval.start, cents: income - expense))
        }
        return result
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

    /// 一级分类：一个领域一片扇形
    private struct DomainSlice: Identifiable {
        let domain: CategoryDomain
        let cents: Int64
        let count: Int
        let rows: [CategoryRow]

        var id: String { domain.rawValue }
    }

    /// 固定的阅读顺序：吃、用、住、行、玩、健康、人情、其他
    private static let domainOrder: [CategoryDomain] = [
        .food, .goods, .housing, .transport, .play, .health, .social, .communication, .other
    ]

    private var domainSlices: [DomainSlice] {
        Dictionary(grouping: categoryRows) { $0.category?.domain ?? .other }
            .map { domain, rows in
                DomainSlice(domain: domain,
                            cents: rows.reduce(0) { $0 + $1.cents },
                            count: rows.reduce(0) { $0 + $1.count },
                            rows: rows.sorted { $0.cents > $1.cents })
            }
            .sorted {
                (Self.domainOrder.firstIndex(of: $0.domain) ?? 99)
                    < (Self.domainOrder.firstIndex(of: $1.domain) ?? 99)
            }
    }

    /// 选中的一级分类；没点过就是金额最大的那个
    private var activeDomain: DomainSlice? {
        domainSlices.first { $0.id == selectedDomain } ?? domainSlices.first
    }

    private var activeRows: [CategoryRow] { activeDomain?.rows ?? [] }

    private var domainSection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("支出分类")
                        .font(Typography.bodyStrong)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 12)
                    Text("共 \(categoryRows.reduce(0) { $0 + $1.count }) 笔")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                if categoryRows.isEmpty {
                    Text("这段时间还没有支出")
                        .font(Typography.label)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        domainLegend
                        domainPie
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(activeRows) { row in
                            categoryRow(
                                iconName: row.category?.iconName ?? "tag",
                                colorHex: row.category?.colorHex ?? "#9CA3AF",
                                name: row.id,
                                cents: row.cents,
                                count: row.count,
                                baseCents: activeDomain?.cents ?? totalCents
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let category = row.category { openCategory(category) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var domainPie: some View {
        let slices = domainSlices
        let total = max(1, slices.reduce(0) { $0 + $1.cents })
        let active = activeDomain

        return GeometryReader { geo in
            let size = geo.size

            ZStack {
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let outer = min(canvasSize.width, canvasSize.height) / 2
                    let lineWidth: CGFloat = 34
                    // 给选中那片的外移和加粗留足空间，不越出卡片
                    let radius = outer - 26
                    var startAngle = -90.0

                    for slice in slices {
                        let sweep = 360 * Double(slice.cents) / Double(total)
                        // 段与段之间留一条细缝，八片才不会糊成一圈
                        let inset = min(2.0, sweep * 0.2)
                        let isActive = active?.id == slice.id

                        // 选中的那片往外挪一点、加粗，其余压淡：一眼能看出点的是哪一块
                        var path = Path()
                        path.addArc(center: center,
                                    radius: radius + (isActive ? 7 : 0),
                                    startAngle: .degrees(startAngle + inset),
                                    endAngle: .degrees(startAngle + sweep - inset),
                                    clockwise: false)
                        context.stroke(
                            path,
                            with: .color(Color.domainColor(slice.domain).opacity(isActive ? 1 : 0.72)),
                            style: StrokeStyle(lineWidth: isActive ? lineWidth + 6 : lineWidth,
                                               lineCap: .butt)
                        )
                        startAngle += sweep
                    }
                }

                VStack(spacing: 2) {
                    Text(active?.domain.displayName ?? "支出")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(AmountFormat.string(cents: active?.cents ?? 0))
                        .font(Typography.numberSmall)
                        .foregroundStyle(Color.textPrimary)
                    Text(domainShare(active, total: total))
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        selectSlice(at: value.location, in: size, slices: slices, total: total)
                    }
            )
        }
        .frame(height: 196)
    }

    /// 点扇形：算出点落在哪一片，切换下钻的一级分类
    private func selectSlice(at point: CGPoint,
                             in size: CGSize,
                             slices: [DomainSlice],
                             total: Int64) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let outer = min(size.width, size.height) / 2
        // 只认圆环那一圈，圆心和图外都不响应
        guard distance > outer * 0.56, distance <= outer else { return }

        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }

        var cursor = 0.0
        for slice in slices {
            let sweep = 360 * Double(slice.cents) / Double(total)
            if degrees >= cursor, degrees < cursor + sweep {
                withAnimation(.snappy(duration: 0.25)) { selectedDomain = slice.id }
                return
            }
            cursor += sweep
        }
    }

    /// 竖排图例：颜色、名称、占比，同时也是切换入口
    private var domainLegend: some View {
        let total = max(1, totalCents)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(domainSlices) { slice in
                let active = activeDomain?.id == slice.id
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selectedDomain = slice.id }
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.domainColor(slice.domain))
                            .frame(width: active ? 8 : 7, height: active ? 8 : 7)
                        Text(slice.domain.displayName)
                            .font(active ? .footnote.weight(.semibold) : Typography.label)
                            .foregroundStyle(active ? Color.textPrimary : Color.textSecondary)
                            .frame(width: 40, alignment: .leading)
                        Text("\(Int((Double(slice.cents) / Double(total) * 100).rounded()))%")
                            .font(active ? .footnote.weight(.semibold) : Typography.label)
                            .foregroundStyle(active ? Color.textPrimary : Color.textSecondary)
                            .lineLimit(1)
                            .frame(width: 40, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 116)
    }

    private func domainShare(_ slice: DomainSlice?, total: Int64) -> String {
        guard let slice, total > 0 else { return "0%" }
        return "\(Int((Double(slice.cents) / Double(total) * 100).rounded()))%"
    }

    /// 一级分类的颜色：沿用各类里最有代表性的那个色
    private func categoryRow(iconName: String,
                             colorHex: String,
                             name: String,
                             cents: Int64,
                             count: Int,
                             baseCents: Int64? = nil) -> some View {
        // 进度条按「当前一级分类」的总额算，下钻后才看得出这一类里谁占得多
        let base = max(1, baseCents ?? totalCents)
        let ratio = CGFloat(Double(cents) / Double(base))
        return HStack(spacing: 8) {
            CategoryIcon(iconName: iconName, colorHex: colorHex, size: 24)

            Text(name)
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 66, alignment: .leading)

            Text("\(count) 笔")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            Spacer(minLength: 8)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.textSecondary.opacity(0.12))
                    .frame(width: 48, height: 5)
                Capsule()
                    .fill(Color.brand)
                    .frame(width: max(4, 48 * ratio), height: 5)
            }

            Text(AmountFormat.string(cents: cents))
                .font(Typography.numberSmall)
                .foregroundStyle(Color.textPrimary)
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
