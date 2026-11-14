import SwiftUI
import SwiftData

/// 目标页：只放「正在执行的」目标进度。
/// 选目标（新增 = 管理）和已达成记录各自一页，三者不重复列同一份数据。
struct GoalView: View {
    let onOpenHistory: () -> Void
    let onOpenPicker: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Goal.sortOrder), SortDescriptor(\Goal.createdAt)])
    private var allGoals: [Goal]
    @Query private var budgets: [Budget]
    @Query private var allTransactions: [Transaction]
    @Query(sort: [SortDescriptor(\GoalAchievement.periodStart, order: .reverse)])
    private var achievements: [GoalAchievement]

    @State private var showBudgetEditor = false

    private var calendar: Calendar { .current }
    private var goals: [Goal] { allGoals.filter(\.isActive) }
    private var achievedTotal: Int { achievements.filter(\.achieved).count }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    Text("目标")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .padding(.top, 56)

                    budgetCard

                    if !goals.isEmpty {
                        VStack(spacing: PageLayout.blockGap) {
                            ForEach(goals) { goal in
                                GoalCard(goal: goal, progress: progress(for: goal))
                            }
                        }
                    }
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .trailing, spacing: 10) {
                achievementButton
                newGoalButton
            }
            .padding(.trailing, PageLayout.pageInset)
            .padding(.bottom, 26)
        }
        .sheet(isPresented: $showBudgetEditor) {
            BudgetEditorSheet(
                monthTitle: monthTitle,
                initialCents: monthBudget?.amountCents,
                onSave: saveBudget,
                onClear: clearBudget
            )
            .presentationDetents([.fraction(1.0 / 3.0)])
            .presentationCornerRadius(24)
            .presentationBackground(Color.surfaceElevated)
        }
    }

    // MARK: - 预算

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    private var monthBudget: Budget? {
        let comps = calendar.dateComponents([.year, .month], from: monthStart)
        return budgets.first {
            $0.category == nil && $0.year == comps.year && $0.month == comps.month
        }
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    private var monthExpenseCents: Int64 {
        let end = calendar.dateInterval(of: .month, for: .now)?.end ?? .now
        return allTransactions
            .filter { $0.kind == .expense && $0.date >= monthStart && $0.date < end }
            .reduce(into: Int64(0)) { $0 += $1.amountCents }
    }

    private var budgetCard: some View {
        Button {
            showBudgetEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("预算")
                        .font(.headline)
                    Spacer()
                    Text(monthTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let budget = monthBudget, budget.amountCents > 0 {
                    let remaining = budget.amountCents - monthExpenseCents
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("还剩 \(AmountFormat.string(cents: max(0, remaining)))")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.brand)
                        Text("/ \(AmountFormat.string(cents: budget.amountCents))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: max(0, 1 - Double(monthExpenseCents) / Double(budget.amountCents)))
                        .tint(Color.brand)
                } else {
                    Text("设置一个数，用来对照这个月花到哪儿了")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 入口

    /// 已达成入口：有记录时才出现，避免空页面
    @ViewBuilder
    private var achievementButton: some View {
        if achievedTotal > 0 {
            Button {
                onOpenHistory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trophy")
                        .font(.system(size: 13, weight: .medium))
                    Text("已达成 \(achievedTotal) 次")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .foregroundStyle(Color.secondary)
                .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    /// 新增 / 管理目标的入口：右下角胶囊
    private var newGoalButton: some View {
        Button {
            onOpenPicker()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                Text("目标管理")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .foregroundStyle(Color.secondary)
            .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 动作

    private func progress(for goal: Goal) -> GoalProgress? {
        try? GoalService(context: context).progress(for: goal)
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
}

/// 一张目标卡：标题、期间、点阵 + 分数。不承担编辑。
private struct GoalCard: View {
    let goal: Goal
    let progress: GoalProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progress {
                HStack(spacing: 12) {
                    if progress.unit == .cents || progress.unit == .percent {
                        ProgressView(value: max(0, 1 - progress.fraction))
                            .tint(Color.brand)
                            .frame(maxWidth: .infinity)
                    } else {
                        dots(progress)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("\(valueText(progress)) / \(limitText(progress))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(progress.isReached && !progress.isAtMost ? Color.brand : Color.secondary)
                        .fixedSize()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
    }

    private func valueText(_ progress: GoalProgress) -> String {
        switch progress.unit {
        case .cents: return AmountFormat.string(cents: Int64(progress.current))
        case .percent: return "\(progress.current)%"
        case .count: return "\(min(progress.current, progress.target))"
        }
    }

    private func limitText(_ progress: GoalProgress) -> String {
        switch progress.unit {
        case .cents: return AmountFormat.string(cents: Int64(progress.target))
        case .percent: return "\(progress.target)%"
        case .count: return "\(progress.target)"
        }
    }

    private func dots(_ progress: GoalProgress) -> some View {
        let total = min(progress.target, 12)
        let filled = min(progress.current, total)
        return HStack(spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color.brand : Color.secondary.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
        }
    }
}
