import SwiftUI
import SwiftData

/// 四个页面用底部导航切换：今天 · 统计 · 目标 · 设置。
/// 记录页与编辑页仍然挂在根上全屏呈现，右滑即可关闭。
struct RootView: View {
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
    /// 选择目标整页
    @State private var showGoalRules = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView(onOpenRecord: openRecord(at:), onEdit: openEdit, focus: focusedDay)
                .background(AppBackground())
                .tabItem { Label { Text("今天").foregroundStyle(tab == .today ? Color.brand : Color.textSecondary) } icon: { tabIcon("sun.max", selected: tab == .today) } }
                .tag(Tab.today)

            ReviewView(onEdit: openEdit)
                .background(AppBackground())
                .tabItem { Label { Text("统计").foregroundStyle(tab == .review ? Color.brand : Color.textSecondary) } icon: { tabIcon("chart.bar.xaxis", selected: tab == .review) } }
                .tag(Tab.review)

            GoalView(onOpenHistory: openGoalHistory, onOpenPicker: openGoalRules)
                .background(AppBackground())
                .tabItem { Label { Text("目标").foregroundStyle(tab == .goal ? Color.brand : Color.textSecondary) } icon: { tabIcon("target", selected: tab == .goal) } }
                .tag(Tab.goal)

            SettingsView()
                .background(AppBackground())
                .tabItem { Label { Text("设置").foregroundStyle(tab == .settings ? Color.brand : Color.textSecondary) } icon: { tabIcon("gearshape", selected: tab == .settings) } }
                .tag(Tab.settings)
        }
        .tint(Color.brand)
        .overlay {
            if showGoalRules {
                GoalRulesView(onClose: closeGoalRules)
                    .transition(.move(edge: .trailing))
                    .zIndex(12)
            }

            if showGoalHistory {
                GoalHistoryView(onClose: closeGoalHistory)
                    .transition(.move(edge: .trailing))
                    .zIndex(11)
            }

            if showRecord {
                RecordPage(initialDate: recordDate, onClose: closeRecord, onSaved: { focusedDay = $0 })
                    // 转场期间冻结内部布局，页面整体作为一个图层滑入
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }

            if let editingTransaction {
                RecordPage(editing: editingTransaction, onClose: closeEdit, onSaved: { focusedDay = $0 })
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
        guard let symbol = UIImage(systemName: name, withConfiguration: config) else {
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
    }

    private func openGoalRules() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showGoalRules = true
        }
    }

    private func closeGoalRules() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showGoalRules = false
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
