import SwiftUI
import SwiftData

/// 三个页面用底部导航切换：今天 · 回看 · 设置。
/// 记录页与编辑页仍然挂在根上全屏呈现，右滑即可关闭。
struct RootView: View {
    private enum Tab: Hashable {
        case today, review, settings
    }

    @State private var tab: Tab = .today

    /// 记录页挂在根上全屏呈现，不跟着页面切换走
    @State private var showRecord = false
    /// 正在编辑的那一笔；非空时弹出编辑页
    @State private var editingTransaction: Transaction?

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

            SettingsView()
                .background(AppBackground())
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(Tab.settings)
        }
        .tint(Color.brand)
        .overlay {
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
