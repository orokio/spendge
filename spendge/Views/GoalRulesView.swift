import SwiftUI
import SwiftData

/// 管理目标：目标就是规则本身，每条都能改参数。
/// 三个预设只是空列表时的快捷添加，添加后就是一条普通规则。
struct GoalRulesView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Goal.sortOrder), SortDescriptor(\Goal.createdAt)])
    private var allGoals: [Goal]
    @Query private var budgets: [Budget]

    @State private var dragOffset: CGFloat = 0
    @State private var showForm = false
    @State private var formTarget: Goal?
    @State private var showBudgetEditor = false

    private var calendar: Calendar { .current }
    private var goals: [Goal] { allGoals.filter(\.isActive) }

    private var monthBudget: Budget? {
        let comps = calendar.dateComponents([.year, .month], from: .now)
        return budgets.first {
            $0.category == nil && $0.year == comps.year && $0.month == comps.month
        }
    }

    private var monthTitle: String {
        (calendar.dateInterval(of: .month, for: .now)?.start ?? .now)
            .formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    Text("目标管理")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .padding(.top, 56)

                    if goals.isEmpty {
                        presetSection
                    } else {
                        rulesSection
                    }

                    addButton
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)

            if showForm {
                GoalFormView(goal: formTarget) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        showForm = false
                    }
                }
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .offset(x: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard value.translation.width > 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if value.translation.width > 120 {
                        onClose()
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
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

    // MARK: - 规则列表

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                    Button {
                        formTarget = goal
                        showForm = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(goal.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(summary(for: goal))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < goals.count - 1 { divider }
                }
            }
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - 空列表：快捷添加

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: PageLayout.blockGap) {
            // 左右排：标题在左，副标题在右
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
                    showBudgetEditor = true
                }
            }
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func presetRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                    Text(subtitle)
                        .font(.caption2)
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

    // MARK: - 新增

    private var addButton: some View {
        Button {
            formTarget = nil
            showForm = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("新增目标")
                    .font(.subheadline)
            }
            .foregroundStyle(Color.brand)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
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

    // MARK: - 动作

    private func summary(for goal: Goal) -> String {
        let scope = goal.categoryCodes.isEmpty
            ? "全部"
            : (categoryName(for: goal.categoryCodes.first) ?? "")
        let direction = goal.isAtMost ? "不超过" : "至少"
        let value = goal.kind == .categorySum ? String(goal.targetValue / 100) : String(goal.targetValue)
        return "本月 · \(scope) · \(direction) \(value) \(goal.kind.unitSuffix)"
    }

    private func categoryName(for code: String?) -> String? {
        guard let code else { return nil }
        let descriptor = FetchDescriptor<Category>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first { $0.categoryCode?.rawValue == code }?.displayName
    }

    private func createTakeoutBudgetGoal() {
        _ = try? GoalService(context: context).create(
            title: "本月外卖 ≤ 800 元",
            kind: .categorySum,
            categoryCodes: [CategoryCode.takeout.rawValue],
            period: .month, targetValue: 80_000
        )
    }

    private func createDrinkLimitGoal() {
        _ = try? GoalService(context: context).create(
            title: "本月奶茶 ≤ 4 次",
            kind: .countLimit,
            categoryCodes: [CategoryCode.drink.rawValue],
            period: .month, targetValue: 4
        )
    }

    private func saveBudget(_ cents: Int64) {
        let comps = calendar.dateComponents([.year, .month], from: .now)
        try? BudgetService(context: context).setBudget(
            category: nil, amountCents: cents,
            year: comps.year ?? 2026, month: comps.month ?? 1
        )
    }

    private func clearBudget() {
        guard let budget = monthBudget else { return }
        try? BudgetService(context: context).deleteBudget(budget)
    }
}
