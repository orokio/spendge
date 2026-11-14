import SwiftUI
import UIKit

/// 长按删除：按住整行，红色块从右往左充满，充满即删除；中途松手取消。
///
/// 不用横向拖拽，所以不会和整页翻页、列表纵向滚动抢同一个手势。
struct HoldToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    /// 红色块充满所需时间（形状节奏）
    private let fillDuration: Double = 0.9
    /// 先静置一小会儿再开始变红：拖动列表时不会闪一下红
    private let gracePeriod: Double = 0.2
    /// 手指允许的抖动范围，超出即取消
    private let allowedDrift: CGFloat = 8

    /// 0…1，红色块占行宽的比例
    @State private var progress: CGFloat = 0
    @State private var fillTask: Task<Void, Never>?

    /// 按住多久算删除：静置 + 充满
    private var holdDuration: Double { gracePeriod + fillDuration }

    var body: some View {
        content
            .overlay(alignment: .trailing) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ZStack(alignment: .trailing) {
                            Color.red
                            Text("删除")
                                .font(Typography.bodyStrong)
                                .foregroundStyle(.white)
                                .padding(.trailing, 18)
                        }
                        .frame(width: geo.size.width * progress)
                        // 宽度还小的时候把文字裁掉，不要挤成一条
                        .clipped()
                    }
                }
                .allowsHitTesting(false)
            }
            .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: allowedDrift) {
                fillTask?.cancel()
                progress = 0
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                onDelete()
            } onPressingChanged: { isPressing in
                fillTask?.cancel()
                if isPressing {
                    // 先静置：手指还在轻微移动的（拖列表）不会看到红色
                    fillTask = Task {
                        try? await Task.sleep(for: .milliseconds(Int(gracePeriod * 1000)))
                        guard !Task.isCancelled else { return }
                        withAnimation(.linear(duration: fillDuration)) { progress = 1 }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
                }
            }
            .onDisappear { fillTask?.cancel() }
    }
}
