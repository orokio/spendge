import SwiftUI
import SwiftData

/// 目标页：预算卡 + 进行中的目标 + 已暂停的目标。
/// 新增、编辑、暂停都在半层里完成，不再跳整页管理。
struct GoalView: View {
    let onOpenTrophies: () -> Void
    /// 是否停留在目标 tab；离开时收起抽屉，避免状态留着
    let isActive: Bool

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Goal> { $0.deletedAt == nil },
           sort: [SortDescriptor<Goal>(\Goal.sortOrder),
                  SortDescriptor<Goal>(\Goal.createdAt)])
    private var allGoals: [Goal]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil }) private var allTransactions: [Transaction]
    @Query(filter: #Predicate<GoalAchievement> { $0.deletedAt == nil },
           sort: [SortDescriptor<GoalAchievement>(\GoalAchievement.periodStart, order: .reverse)])
    private var achievements: [GoalAchievement]

    /// 正在查看的月份：默认当月，可回看历史
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var showMonthPicker = false
    @State private var showUnlock = false
    @State private var showBudgetEditor = false
    @State private var errorMessage: String?
    @State private var showGoalForm = false
    @State private var formTarget: Goal?

    private var calendar: Calendar { .current }
    /// 每个月一份目标：只看该月自己的那些
    private var goals: [Goal] {
        allGoals.filter { !$0.isBudget && $0.isActive && calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month) }
    }
    private var pausedGoals: [Goal] {
        allGoals.filter { !$0.isBudget && !$0.isActive && calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month) }
    }

    var body: some View {
        let _ = LaunchTrace.once("goal.body")
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    header
                    budgetCard

                    if isCurrentMonth {
                        if goals.isEmpty && pausedGoals.isEmpty {
                            presetSection
                        } else {
                            if !goals.isEmpty { activeSection }
                            if !pausedGoals.isEmpty { pausedSection }
                        }
                    } else {
                        historySection
                    }
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.top, 56)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // 预算也是同一套顶部抽屉
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if showBudgetEditor {
                    Color.scrim
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { closeBudget() }

                    BudgetEditorSheet(
                        monthTitle: monthTitle,
                        initialCents: monthBudget.map { Int64($0.targetValue) },
                        initialRecurring: monthBudget?.isRecurring ?? false,
                        onSave: { cents, recurring in
                            if saveBudget(cents, recurring) { closeBudget() }
                        },
                        onClear: {
                            if clearBudget() { closeBudget() }
                        }
                    )
                    .background {
                        UnevenRoundedRectangle(bottomLeadingRadius: 28,
                                               bottomTrailingRadius: 28,
                                               style: .continuous)
                            .fill(Color.surfaceElevated)
                            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                            .ignoresSafeArea(.container, edges: .top)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .ignoresSafeArea(.keyboard)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showBudgetEditor)
        }
        // 两个抽屉共用同一个容器：目标表单和预算编辑
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                TopDrawer(isPresented: $showGoalForm) {
                    GoalFormView(goal: formTarget) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            showGoalForm = false
                        }
                    }
                }

                TopDrawer(isPresented: $showBudgetEditor) {
                    BudgetEditorSheet(
                        monthTitle: monthTitle,
                        initialCents: monthBudget.map { Int64($0.targetValue) },
                        initialRecurring: monthBudget?.isRecurring ?? false,
                        onSave: { cents, recurring in
                            if saveBudget(cents, recurring) { closeBudget() }
                        },
                        onClear: {
                            if clearBudget() { closeBudget() }
                        }
                    )
                }
            }
        }
        .unlockPrompt($showUnlock)
        .onReceive(NotificationCenter.default.publisher(for: .dataRestored)) { _ in
            dismissDrawers()
        }
        .onChange(of: isActive) { _, active in
            if !active { dismissDrawers() }
        }
        .sheet(isPresented: $showMonthPicker) {
            PeriodPickerSheet(options: monthOptions.map { .month($0) },
                              selected: .month(monthStart),
                              onUnlock: Entitlements.can(.fullHistory) ? nil : {
                                  showMonthPicker = false
                                  showUnlock = true
                              }) { picked in
                if case .month(let date) = picked {
                    selectedMonth = date
                }
                showMonthPicker = false
            }
            .presentationDetents([.fraction(0.45)])
            .presentationCornerRadius(24)
            .presentationBackground(Color.surfaceElevated)
        }
        .errorToast($errorMessage)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                showMonthPicker = true
            } label: {
                HStack(spacing: 5) {
                    Text(monthTitle)
                        .font(Typography.pageTitle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            Button {
                onOpenTrophies()
            } label: {
                Image(systemName: "trophy")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 预算

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
    }

    private var monthEnd: Date {
        calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(selectedMonth, equalTo: .now, toGranularity: .month)
    }

    private var monthBudget: Goal? {
        allGoals.first {
            $0.isBudget && calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month)
        }
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    private var monthExpenseCents: Int64 {
        return allTransactions
            .filter { $0.kind == .expense && $0.date >= monthStart && $0.date < monthEnd }
            .reduce(into: Int64(0)) { $0 += $1.amountCents }
    }

    /// 本月还剩几天（不含今天）
    private var daysLeft: Int {
        let end = calendar.dateInterval(of: .month, for: .now)?.end ?? .now
        let comps = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: end)
        return max(0, comps.day ?? 0)
    }

    /// 本月已经过了几天（含今天）
    private var daysPassed: Int {
        max(1, calendar.component(.day, from: .now))
    }

    private var budgetCard: some View {
        Button {
            guard isCurrentMonth else { return }
            openBudget()
        } label: {
            VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
                HStack {
                    Text(isCurrentMonth ? "本月预算" : "当月预算")
                        .font(Typography.bodyStrong)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(monthTitle)
                        if isCurrentMonth {
                            Text("·")
                            Text("还剩 \(daysLeft) 天")
                        } else {
                            Text("·")
                            Text("已结束")
                        }
                    }
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                }

                if let budget = monthBudget, budget.targetValue > 0 {
                    let limit = Int64(budget.targetValue)
                    let spent = monthExpenseCents
                    let remaining = limit - spent
                    let overBudget = spent > limit

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("已花")
                            .font(Typography.label)
                            .foregroundStyle(.secondary)
                        Text(AmountFormat.string(cents: spent))
                            .font(Typography.numberLarge)
                            .foregroundStyle(overBudget ? Color.danger : Color.brand)
                        Text("/ \(AmountFormat.string(cents: Int64(budget.targetValue)))")
                            .font(Typography.label)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        let progress = Double(spent) / Double(max(1, budget.targetValue))
                        let ratio = max(0, min(1, progress))
                        // 绿 → 黄（用到八成）→ 红（超了）
                        let barColor: Color = progress > 1
                            ? Color.danger
                            : (progress >= 0.8 ? Color.warning : Color.brand)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                            Capsule()
                                .fill(barColor)
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 8)

                    budgetTags(budgetCents: limit, remaining: remaining)
                } else {
                    Text("设置一个数，用来对照这个月花到哪儿了")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, PageLayout.cardTitleGap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onboardingAnchor(.budget)
    }

    /// 进度条下的三个数：日均可用、实际日均、额度比
    private func budgetTags(budgetCents: Int64, remaining: Int64) -> some View {
        let perDayLeft = max(0, remaining) / Int64(max(1, daysLeft))
        let perDaySpent = monthExpenseCents / Int64(max(1, daysPassed))
        // 额度比 = 实际日均比「日均可用」超了多少，正数是超，负数是省
        let overPercent: Int? = perDayLeft > 0
            ? Int(((Double(perDaySpent - perDayLeft) / Double(perDayLeft)) * 100).rounded())
            : nil

        let ratioTint: Color
        if let overPercent {
            ratioTint = overPercent > 0 ? Color.danger : (overPercent < 0 ? Color.brand : Color.textSecondary)
        } else {
            ratioTint = Color.textSecondary
        }

        return HStack(spacing: 0) {
            budgetCell(title: "日均可用", value: AmountFormat.string(cents: perDayLeft), tint: Color.textPrimary)
            budgetSeparator
            budgetCell(title: "实际日均", value: AmountFormat.string(cents: perDaySpent), tint: Color.textPrimary)
            budgetSeparator
            budgetCell(title: "额度比",
                       value: overPercent.map { $0 > 0 ? "+\($0)%" : "\($0)%" } ?? "—",
                       tint: ratioTint)
        }
        .padding(.vertical, 11)
        .background(Color.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func budgetCell(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Typography.numberSmall)
                .foregroundStyle(tint)
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var budgetSeparator: some View {
        Rectangle()
            .fill(Color.brand.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    // MARK: - 进行中

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            HStack(alignment: .firstTextBaseline) {
                Text("进行中")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 12)
                if isCurrentMonth {
                    Button {
                        if !Entitlements.can(.unlimitedGoals),
                           goals.count >= Entitlements.freeGoalLimit {
                            showUnlock = true
                        } else {
                            openForm(nil)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("新增")
                                .font(Typography.label)
                        }
                        .foregroundStyle(Color.brand)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(goals) { goal in
                goalRow(goal)
            }
        }
    }

    /// 历史月份：用达成记录渲染，目标被删了也还能看到当时的结果
    /// 历史月份：展示那个月自己的目标对象（每月一份），结果看达成状态
    private var historySection: some View {
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            Text("已完成")
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.textPrimary)

            if goals.isEmpty && pausedGoals.isEmpty {
                Text("这个月还没有目标记录")
                    .font(Typography.label)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(goals + pausedGoals) { goal in
                    historyCard(goal)
                }
            }
        }
    }

    private func historyCard(_ goal: Goal) -> some View {
        let progress = progress(for: goal)
        return GoalCard(goal: goal,
                        progress: progress,
                        streak: 0,
                        status: progress.map { status(for: $0, closed: true) })
    }

    private var pausedSection: some View {
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            Text("已暂停")
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.textSecondary)

            ForEach(pausedGoals) { goal in
                Button {
                    guard isCurrentMonth else { return }
                    openForm(goal)
                } label: {
                    GoalCard(goal: goal,
                             progress: progress(for: goal),
                             streak: streakMonths(for: goal),
                             status: nil,
                             isPaused: true)
                }
                .buttonStyle(.plain)
                .disabled(!isCurrentMonth)
            }
        }
    }

    /// 左侧点击进操作层，右半边长按删除
    private func goalRow(_ goal: Goal) -> some View {
        let p = progress(for: goal)
        return         HoldToDeleteRow(onDelete: { if isCurrentMonth { delete(goal) } },
                               cornerRadius: PageLayout.cardRadius) {
            Button {
                guard isCurrentMonth else { return }
                openForm(goal)
            } label: {
                GoalCard(goal: goal,
                         progress: p,
                         streak: streakMonths(for: goal),
                         status: p.map { status(for: $0) })
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 空态：备选目标

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            SectionHeader(title: "先定一个目标") {
                Text("目标不是任务，只是你想往哪走")
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            VStack(spacing: 0) {
                presetRow(title: "本月奶茶 ≤ 4 次", subtitle: "高频小额，最好管") {
                    createDrinkLimitGoal()
                }
                divider
                presetRow(title: "本月外卖 ≤ 800 元", subtitle: "超过就少吃几顿") {
                    createTakeoutBudgetGoal()
                }
                divider
                presetRow(title: "本月预算 ¥3,000", subtitle: "和花销对照着看") {
                    openBudget()
                }
            }
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
        }
    }

    private func presetRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: - 判定

    /// 拿「用了多少」和「过了多少时间」比：同一个 50%，月初和月底完全不同
    /// closed=true 用于历史月：整月都过完了，按“月底”这个时间点判断
    private func status(for progress: GoalProgress, closed: Bool = false) -> GoalStatus {
        if progress.target == 0 {
            return progress.current == 0 ? .perfect : .over
        }

        let usage = Double(progress.current) / Double(progress.target)
        if usage > 1 { return .over }
        if progress.current == 0 { return .perfect }

        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let passed = closed ? dayCount : daysPassed
        let timeProgress = Double(passed) / Double(dayCount)

        if usage <= timeProgress { return .healthy }
        if usage > timeProgress + 0.2 || usage > 0.8 { return .warning }
        return .healthy
    }

    // MARK: - 动作

    private func progress(for goal: Goal) -> GoalProgress? {
        let asOf = isCurrentMonth ? Date.now : monthEnd.addingTimeInterval(-1)
        return try? GoalService(context: context).progress(for: goal, asOf: asOf)
    }

    /// 可选月份：从最早有数据的那个月到当月，和统计页同一口径
    private var monthOptions: [Date] {
        let current = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let transactionDates = allTransactions.map(\.date)
        let goalDates = allGoals.map(\.createdAt)
        let achievementDates = achievements.map(\.periodStart)
        let earliest = (transactionDates + goalDates + achievementDates)
            .min()
            .flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? current

        // 免费版只看近 3 个月
        let lowerBound: Date = Entitlements.can(.fullHistory)
            ? earliest
            : calendar.date(byAdding: .month, value: -(Entitlements.freeHistoryMonths - 1), to: current) ?? current

        var result: [Date] = []
        var cursor = current
        while cursor >= max(earliest, lowerBound) {
            result.append(cursor)
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result
    }

    /// 最近连续达成的周期数：从最新一条往前数，断了就停
    private func streakMonths(for goal: Goal) -> Int {
        let done = achievements
            .filter { $0.goalID == goal.id && $0.achieved && $0.periodRawValue == goal.periodRawValue }
            .map(\.periodStart)
            .sorted(by: >)
        guard !done.isEmpty else { return 0 }

        var count = 1
        for index in 1..<done.count {
            let expected = calendar.date(byAdding: .month, value: -1, to: done[index - 1])
                ?? done[index - 1]
            guard calendar.isDate(done[index], equalTo: expected, toGranularity: .month) else { break }
            count += 1
        }
        return count
    }

    private func dismissDrawers() {
        showGoalForm = false
        formTarget = nil
        showBudgetEditor = false
    }

    private func openBudget() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showBudgetEditor = true
        }
    }

    private func closeBudget() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showBudgetEditor = false
        }
    }

    private func openForm(_ goal: Goal?) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            formTarget = goal
            showGoalForm = true
        }
    }

    private func togglePause(_ goal: Goal) {
        do {
            try FaultInjection.current.check(.goalWrite)
        } catch {
            errorMessage = ErrorText.message(for: error)
            return
        }
        goal.isActive.toggle()
        goal.updatedAt = .now
        do {
            try context.save()
        } catch {
            goal.isActive.toggle()
            errorMessage = ErrorText.message(for: error)
        }
    }

    private func delete(_ goal: Goal) {
        do {
            try GoalService(context: context).delete(goal)
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    private func createTakeoutBudgetGoal() {
        do {
            _ = try GoalService(context: context).create(
                title: "本月外卖 ≤ 800 元",
                kind: .budget,
                categoryCodes: [CategoryCode.takeout.rawValue],
                period: .month, targetValue: 80_000
            )
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    private func createDrinkLimitGoal() {
        do {
            _ = try GoalService(context: context).create(
                title: "本月奶茶 ≤ 4 次",
                kind: .countLimit,
                categoryCodes: [CategoryCode.drink.rawValue],
                period: .month, targetValue: 4
            )
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    @discardableResult
    private func saveBudget(_ cents: Int64, _ recurring: Bool) -> Bool {
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        do {
            try GoalService(context: context).setBudget(
                amountCents: cents,
                year: comps.year ?? 2026,
                month: comps.month ?? 1,
                isRecurring: recurring
            )
            return true
        } catch {
            errorMessage = ErrorText.message(for: error)
            return false
        }
    }

    @discardableResult
    private func clearBudget() -> Bool {
        guard let budget = monthBudget else { return true }
        do {
            try GoalService(context: context).deleteBudget(budget)
            return true
        } catch {
            errorMessage = ErrorText.message(for: error)
            return false
        }
    }
}

/// 目标状态：消费进度对照时间进度
enum GoalStatus {
    case perfect
    case healthy
    case warning
    case over

    var label: String {
        switch self {
        case .perfect: return "完美保持"
        case .healthy: return "健康"
        case .warning: return "快超了"
        case .over: return "已超出"
        }
    }

    var color: Color {
        switch self {
        case .perfect, .healthy: return Color.brand
        case .warning: return Color.warning
        case .over: return Color.danger
        }
    }
}

/// 一张目标卡：左边进度环，右边标题、状态徽章和一句说明
private struct GoalCard: View {
    let goal: Goal
    let progress: GoalProgress?
    /// 连续达成的周期数，用在「一次都不」型目标的文案里
    let streak: Int
    let status: GoalStatus?
    var isPaused = false

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            if let progress {
                GoalRing(progress: progress, tint: status?.color ?? Color.brand)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(goal.title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let status {
                        Text(status.label)
                            .font(Typography.captionStrong)
                            .foregroundStyle(status.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(status.color.opacity(0.12), in: Capsule())
                    }
                }

                if let progress {
                    Text(detailText(progress))
                        .font(Typography.label)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
        .opacity(isPaused ? 0.6 : 1)
    }

    private func detailText(_ progress: GoalProgress) -> String {
        // 「一次都不」型：不说还差多少，说已经保持了多久
        if progress.target == 0 {
            if progress.current > 0 { return "做了 \(progress.current) 次" }
            return streak > 0 ? "连续 \(streak) 个月做到" : "一次没做"
        }

        guard progress.current <= progress.target else {
            let over = progress.current - progress.target
            switch progress.unit {
            case .count: return "超出 \(over) 次"
            case .cents: return "超出 \(AmountFormat.string(cents: Int64(over)))"
            case .percent: return "超出 \(over) 个百分点"
            }
        }

        switch progress.unit {
        case .count: return "还剩 \(progress.remaining) 次"
        case .cents: return "还剩 \(AmountFormat.string(cents: Int64(progress.remaining)))"
        case .percent: return "还剩 \(progress.remaining)%"
        }
    }
}

/// 44pt 的进度环：次数目标中心给分数，金额目标给百分比，0 目标达标时放一个火苗
private struct GoalRing: View {
    let progress: GoalProgress
    var tint: Color = Color.brand
    private let diameter: CGFloat = 44
    private let lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fillFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            center
        }
        .frame(width: diameter, height: diameter)
    }

    /// 环画的是「已经用掉多少」：3/4 就是四分之三圈，和中心的分数对得上
    private var fillFraction: Double {
        if progress.target == 0 {
            return progress.current == 0 ? 1 : 0
        }
        return max(0, min(1, progress.fraction))
    }

    @ViewBuilder
    private var center: some View {
        if progress.target == 0 {
            if progress.current == 0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
            } else {
                Text("\(progress.current)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.warning)
            }
        } else if progress.unit == .count {
            Text("\(min(progress.current, progress.target))/\(progress.target)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(centerTint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } else {
            Text("\(usedPercent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(centerTint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    /// 真实用掉的比例：超了就是 120%，不压到 100%
    private var usedPercent: Int {
        guard progress.target > 0 else { return 0 }
        return Int((Double(progress.current) / Double(progress.target) * 100).rounded())
    }

    private var centerTint: Color {
        progress.current > progress.target ? Color.danger : Color.textPrimary
    }
}
