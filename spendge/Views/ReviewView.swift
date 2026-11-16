import SwiftUI
import SwiftData

/// 统计：按月 / 按年看钱花在哪。一个下拉选期间，没有图表。
struct ReviewView: View {
    let onEdit: (Transaction) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    /// 当前查看的期间：某个月，或某一整年
    @State private var period: Period = .month(Date())
    @State private var showPicker = false

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
                insightCard
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

        // 1. 结构：某一类占 40% 以上
        if let top = categoryRows.first, totalCents > 0 {
            let share = Int((Double(top.cents) / Double(totalCents) * 100).rounded())
            if share >= 40 {
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
        let mainFont = Font.system(size: 20, weight: .semibold, design: .rounded)

        return VStack(alignment: .leading, spacing: 14) {
            (Text(text.before).font(mainFont).foregroundColor(Color.textPrimary)
             + Text(text.highlight)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundColor(Color.brand)
             + Text(text.after).font(mainFont).foregroundColor(Color.textPrimary))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            Text(text.sub)
                .font(Typography.body)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.brand.opacity(0.12), Color.brand.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: PageLayout.cardRadius)
        )
    }

    // MARK: - 钱花在哪

    private var domainSection: some View {
        CardContainer {
                if categoryRows.isEmpty {
                    Text("这段时间还没有支出")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(categoryRows) { row in
                            VStack(spacing: 9) {
                                HStack(spacing: 6) {
                                    CategoryIcon(
                                        iconName: row.category?.iconName ?? "tag",
                                        colorHex: row.category?.colorHex ?? "#9CA3AF",
                                        size: 24
                                    )
                                    Text(row.id)
                                        .font(Typography.rowTitle)
                                        .padding(.leading, 4)

                                    Spacer(minLength: 8)

                                    // 百分比与笔数：小字灰色；金额在最后，字号略大
                                    Text(percentText(row.cents))
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(row.count) 笔")
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                    Text(AmountFormat.string(cents: row.cents))
                                        .font(Typography.numberSmall)
                                        .foregroundStyle(Color.textPrimary)
                                        .padding(.leading, 8)
                                }

                                GeometryReader { geo in
                                    let ratio = totalCents > 0
                                        ? CGFloat(Double(row.cents) / Double(totalCents)) : 0
                                    Capsule()
                                        .fill(Color.brand.opacity(0.55))
                                        .frame(width: max(6, geo.size.width * ratio))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 5)
                            }
                        }

                        HStack(spacing: 8) {
                            Spacer()
                            Text("合计")
                                .font(Typography.label)
                                .foregroundStyle(.secondary)
                            Text(AmountFormat.string(cents: totalCents))
                                .font(Typography.numberSmall)
                        }
                    }
                }
        }
    }

    private func percentText(_ cents: Int64) -> String {
        guard totalCents > 0 else { return "" }
        return "\(Int((Double(cents) / Double(totalCents) * 100).rounded()))%"
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
