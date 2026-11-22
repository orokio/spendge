import SwiftUI
import SwiftData

/// 四个页面用底部导航切换：今天 · 统计 · 目标 · 设置。
/// 记录页与编辑页仍然挂在根上全屏呈现，右滑即可关闭。
struct RootView: View {
    @Environment(\.modelContext) private var context

    private enum Tab: Hashable {
        case today, review, goal, settings
    }

    @State private var tab: Tab = .today
    /// 首页要聚焦的日期：启动/回前台为今天，记完一笔为那笔的日期
    @State private var focusedDay: Date?
    /// 记一笔时带过去的日期
    @State private var recordDate = Date()

    /// 记录页挂在根上全屏呈现，不跟着页面切换走
    @State private var showRecord = false
    /// 正在编辑的那一笔；非空时弹出编辑页
    @State private var editingTransaction: Transaction?
    /// 「我的目标」整页
    @State private var showGoalHistory = false
    /// 奖杯墙整页
    @State private var showTrophies = false
    /// 本次要庆祝的新奖杯
    @State private var celebration: [TrophySpec] = []
    /// 记录页还开着时先攒着，等它收起再庆祝
    @State private var pendingCelebration: [TrophySpec] = []
    /// 统计页下钻的分类明细
    @State private var categoryScope: CategoryScope?
    /// 选择目标整页

    var body: some View {
        TabView(selection: $tab) {
            TodayView(onOpenRecord: openRecord(at:), onEdit: openEdit, focus: focusedDay)
                .background(AppBackground())
                .tabItem { Label { Text("记账").foregroundStyle(tab == .today ? Color.brand : Color.textSecondary) } icon: { brandIcon("SpongeMark", selected: tab == .today) } }
                .tag(Tab.today)

            ReviewView(onEdit: openEdit, onOpenCategory: openCategoryDetail)
                .background(AppBackground())
                .tabItem { Label { Text("统计").foregroundStyle(tab == .review ? Color.brand : Color.textSecondary) } icon: { tabIcon("chart.bar.xaxis", selected: tab == .review) } }
                .tag(Tab.review)

            GoalView(onOpenTrophies: openTrophies)
                .background(AppBackground())
                .tabItem { Label { Text("目标").foregroundStyle(tab == .goal ? Color.brand : Color.textSecondary) } icon: { tabIcon("trophy", selected: tab == .goal) } }
                .tag(Tab.goal)

            SettingsView()
                .background(AppBackground())
                .tabItem { Label { Text("设置").foregroundStyle(tab == .settings ? Color.brand : Color.textSecondary) } icon: { tabIcon("gearshape", selected: tab == .settings) } }
                .tag(Tab.settings)
        }
        .tint(Color.brand)
        .task { refreshTrophies(celebrate: false) }
        .onChange(of: tab) { _, _ in refreshTrophies(celebrate: false) }
        // 四个 tab 页里只有目标抽屉有输入框，整体不避让键盘，抽屉就不会被压矮
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay {
            if let categoryScope {
                CategoryRecordsView(scope: categoryScope, onEdit: openEdit, onClose: closeCategoryDetail)
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }

            if showTrophies {
                AchievementView(onClose: closeTrophies, onOpenGoalHistory: openGoalHistory)
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }

            if showGoalHistory {
                GoalHistoryView(onClose: closeGoalHistory)
                    .transition(.move(edge: .trailing))
                    .zIndex(11)
            }

            if !celebration.isEmpty {
                TrophyCelebrationView(trophies: celebration) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        celebration = []
                    }
                }
                .transition(.opacity)
                .zIndex(13)
            }

            if showRecord {
                RecordPage(initialDate: recordDate, onClose: closeRecord, onSaved: { date in
                    focusedDay = date
                    refreshTrophies(celebrate: true)
                })
                    // 转场期间冻结内部布局，页面整体作为一个图层滑入
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }

            if let editingTransaction {
                RecordPage(editing: editingTransaction, onClose: closeEdit, onSaved: { _ in })
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(3)
            }
        }
    }

    /// 底栏图标：先把符号画成位图再交给系统，系统就无法再把它染成黑色
    private func tabIcon(_ name: String, selected: Bool) -> Image {
        let tint = selected ? UIColor(Color.brand) : UIColor(Color.textSecondary)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        // 选中态优先用实心版本，和品牌标记的「充满」质感一致
        let filledName = name + ".fill"
        let resolved = selected && UIImage(systemName: filledName) != nil ? filledName : name
        guard let symbol = UIImage(systemName: resolved, withConfiguration: config) ?? UIImage(systemName: name, withConfiguration: config) else {
            return Image(systemName: name)
        }
        let size = CGSize(width: 26, height: 26)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            symbol.withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (size.width - symbol.size.width) / 2,
                                 y: (size.height - symbol.size.height) / 2,
                                 width: symbol.size.width, height: symbol.size.height))
        }
        return Image(uiImage: rendered.withRenderingMode(.alwaysOriginal))
    }

    /// 品牌标记（海绵）：把位图按当前状态染色后交给系统，避免被系统重新着色
    private func brandIcon(_ asset: String, selected: Bool) -> Image {
        guard let base = UIImage(named: asset) else { return Image(asset) }
        let tint = selected ? UIColor(Color.brand) : UIColor(Color.textSecondary)
        let side: CGFloat = 24
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = min(side / base.size.width, side / base.size.height)
            let width = base.size.width * scale
            let height = base.size.height * scale
            base.withTintColor(tint, renderingMode: .alwaysTemplate)
                .draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2,
                                 width: width, height: height))
        }
        return Image(uiImage: rendered.withRenderingMode(.alwaysOriginal))
    }

    private func openRecord(at date: Date) {
        recordDate = date
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showRecord = true
        }
    }

    private func closeRecord() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showRecord = false
        }
        guard !pendingCelebration.isEmpty else { return }
        let queued = pendingCelebration
        pendingCelebration = []
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                celebration = queued
            }
        }
    }

    /// 记下后检查奖杯：新拿到的等记录页收起再庆祝，避免压住还在输入的面板
    private func refreshTrophies(celebrate: Bool) {
        let newly = AchievementService(context: context).refreshUnlocks()
        guard celebrate, !newly.isEmpty else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(520))
            if showRecord {
                pendingCelebration = newly
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    celebration = newly
                }
            }
        }
    }

    private func openTrophies() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showTrophies = true
        }
    }

    private func closeTrophies() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showTrophies = false
        }
    }

    private func openGoalHistory() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showGoalHistory = true
        }
    }

    private func closeGoalHistory() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showGoalHistory = false
        }
    }

    private func openCategoryDetail(_ scope: CategoryScope) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            categoryScope = scope
        }
    }

    private func closeCategoryDetail() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            categoryScope = nil
        }
    }

    private func openEdit(_ transaction: Transaction) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            editingTransaction = transaction
        }
    }

    private func closeEdit() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            editingTransaction = nil
        }
    }
}
