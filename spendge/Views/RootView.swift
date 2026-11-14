import SwiftUI
import SwiftData

/// 四个页面用底部导航切换：今天 · 回看 · 目标 · 我的。
/// 记录页与编辑页仍然挂在根上全屏呈现，右滑即可关闭。
struct RootView: View {
    private enum Tab: Hashable {
        case today, review, goal, settings
    }

    @State private var tab: Tab = .today

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
            TodayView(onOpenRecord: openRecord, onEdit: openEdit)
                .background(AppBackground())
                .tabItem { Label("今天", systemImage: "sun.max") }
                .tag(Tab.today)

            ReviewView(onEdit: openEdit)
                .background(AppBackground())
                .tabItem { Label("回看", systemImage: "chart.bar.xaxis") }
                .tag(Tab.review)

            GoalView(onOpenHistory: openGoalHistory, onOpenPicker: openGoalRules)
                .background(AppBackground())
                .tabItem { Label("目标", systemImage: "target") }
                .tag(Tab.goal)

            SettingsView()
                .background(AppBackground())
            .tabItem { Label("设置", systemImage: "gearshape") }
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
                RecordPage(onClose: closeRecord)
                    // 转场期间冻结内部布局，页面整体作为一个图层滑入
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }

            if let editingTransaction {
                RecordPage(editing: editingTransaction, onClose: closeEdit)
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(3)
            }
        }
    }

    private func openRecord() {
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
