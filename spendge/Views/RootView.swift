import SwiftUI
import SwiftData

/// 两个页面，无 Tab：今天 ←→ 回看。
/// 横向拖动切换；今天页右上角有一个显式入口，避免纯手势的发现性问题。
struct RootView: View {
    @State private var page: Int = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                TodayView(onOpenReview: { go(to: 1) })
                    .frame(width: geo.size.width)
                ReviewView(onBack: { go(to: 0) })
                    .frame(width: geo.size.width)
            }
            .offset(x: -CGFloat(page) * geo.size.width + dragOffset)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let horizontal = abs(value.translation.width) > abs(value.translation.height)
                        if horizontal {
                            if value.translation.width < -60 { page = 1 }
                            if value.translation.width > 60 { page = 0 }
                        }
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
            )
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: page)
        }
        .background {
            LinearGradient(
                stops: [
                    .init(color: Color.brand.opacity(0.22), location: 0),
                    .init(color: Color.brand.opacity(0.16), location: 0.12),
                    .init(color: Color.brand.opacity(0.09), location: 0.26),
                    .init(color: Color.brand.opacity(0.03), location: 0.40),
                    .init(color: Color.brand.opacity(0), location: 0.52),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    private func go(to index: Int) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            page = index
        }
    }
}
