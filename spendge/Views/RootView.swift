import SwiftUI
import SwiftData

/// 两个页面，无 Tab：今天 ←→ 回看。
/// 整页横向拖动切换；今天页右下角有一个显式入口，避免纯手势的发现性问题。
struct RootView: View {
    /// 0 设置 · 1 今天 · 2 回看
    @State private var page: Int = 1
    @State private var dragOffset: CGFloat = 0

    /// 记录页挂在根上全屏呈现，不跟着翻页偏移走
    @State private var showRecord = false
    /// 正在编辑的那一笔；非空时弹出编辑页
    @State private var editingTransaction: Transaction?
    /// 翻页手势进行中（含结束后的回弹），期间不响应 ＋ 号和月份按钮
    @State private var isPaging = false
    @State private var pagingTask: Task<Void, Never>?
    /// 本次拖动是否真的在翻页，避免松手时误判
    @State private var pageDragActive = false
    /// 页面内的横向控件（柱状图）优先于翻页
    @State private var gate = InteractionGate()

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                SettingsView()
                    .frame(width: geo.size.width, height: geo.size.height)

                TodayView(
                    paging: isPaging,
                    onOpenRecord: openRecord,
                    onOpenReview: { go(to: 2) },
                    onEdit: openEdit
                )
                .frame(width: geo.size.width, height: geo.size.height)

                ReviewView(paging: isPaging, onBack: { go(to: 1) }, onEdit: openEdit)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .offset(x: -CGFloat(page) * geo.size.width + dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onChanged { value in
                        // 横向占绝对优势才算翻页，纵向留给列表滚动
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.8 else { return }
                        // 横向控件（柱状图）正在滚动：这次不翻页。
                        // 注意要把 pageDragActive 也撤掉，否则松手时仍会按位移翻页
                        guard !gate.blockingPageSwipe else {
                            pageDragActive = false
                            dragOffset = 0
                            return
                        }
                        pageDragActive = true
                        beginPaging()
                        let width = value.translation.width
                        // 首尾页不往空白处滑，避免滑到头还回弹一下
                        if page == 0, width > 0 { dragOffset = 0; return }
                        if page == 2, width < 0 { dragOffset = 0; return }
                        dragOffset = width
                    }
                    .onEnded { value in
                        let wasPaging = pageDragActive
                        pageDragActive = false
                        guard wasPaging else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragOffset = 0 }
                            return
                        }
                        if abs(value.translation.width) > abs(value.translation.height) {
                            if value.translation.width < -60 { page = min(page + 1, 2) }
                            if value.translation.width > 60 { page = max(page - 1, 0) }
                        }
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                        endPaging()
                    }
            )
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: page)
        }
        .background(Color.clear)
        .environment(gate)
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

    private func go(to index: Int) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            page = index
        }
    }

    private func openRecord() {
        guard !isPaging else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showRecord = true
        }
    }

    private func openEdit(_ transaction: Transaction) {
        guard !isPaging else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            editingTransaction = transaction
        }
    }

    private func closeEdit() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            editingTransaction = nil
        }
    }

    private func closeRecord() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showRecord = false
        }
    }

    private func beginPaging() {
        pagingTask?.cancel()
        if !isPaging { isPaging = true }
    }

    /// 回弹动画结束后再放开 ＋ 号和月份按钮
    private func endPaging() {
        pagingTask?.cancel()
        pagingTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            isPaging = false
        }
    }
}
