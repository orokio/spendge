import SwiftUI
import UIKit

/// 二级页统一容器：背景、返回按钮、顶部/底部留白、右滑返回都在这里。
/// 滚动页（奖杯、分类明细、开发者）用默认模式；记一笔这种固定高度的编辑器用 scrollable: false。
struct SecondaryPage<Content: View>: View {
    let onClose: () -> Void
    /// true = 内容放进 ScrollView；false = 内容自己占满剩余高度
    var scrollable = true
    var swipeBackEnabled = true
    /// nil 用全局渐变底；记录页传白色底
    var backgroundColor: Color?
    /// 点背景时的动作（记录页用来收键盘）
    var backgroundTap: (() -> Void)?
    @ViewBuilder var content: Content

    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let backgroundColor {
                    backgroundColor
                } else {
                    AppBackground()
                }
            }
            .ignoresSafeArea()
            .onTapGesture { backgroundTap?() }

            if scrollable {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BackButton(action: onClose)
                        Spacer()
                            .frame(height: PageLayout.backToTitleGap)
                        content
                    }
                    .padding(.horizontal, PageLayout.pageInset)
                    .padding(.top, PageLayout.pageTopInset)
                    .padding(.bottom, PageLayout.tabBarClearance)
                }
                .scrollIndicators(.hidden)
            } else {
                content
                    .padding(.top, PageLayout.pageTopInset + PageLayout.backButtonSize + PageLayout.backToTitleGap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .overlay(alignment: .topLeading) {
            if !scrollable {
                BackButton(action: onClose)
                    .padding(.leading, PageLayout.pageInset)
                    .padding(.top, PageLayout.pageTopInset)
            }
        }
        .offset(x: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard swipeBackEnabled, !isDismissing,
                          value.translation.width > 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    guard swipeBackEnabled, !isDismissing else { return }
                    if value.translation.width > 120 {
                        // 先滑出屏幕，再交给路由移除，避免转场和位移叠加成「二次收缩」
                        isDismissing = true
                        withAnimation(.easeOut(duration: 0.24)) {
                            dragOffset = UIScreen.main.bounds.width
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            onClose()
                        }
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onAppear { resetSwipeState() }
        .onDisappear { resetSwipeState() }
    }

    /// 侧滑状态不跨次保留：页面被复用时也能回到初始位置
    private func resetSwipeState() {
        dragOffset = 0
        isDismissing = false
    }
}
