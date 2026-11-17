import SwiftUI
import UIKit

/// 长按删除：按住行的右半边，红色块从右往左充满，充满即删除；中途松手取消。
///
/// 红色块直接复用卡片的圆角形状，再按进度从右侧裁出来，
/// 所以边缘一定和卡片严丝合缝，不会因为圆角曲线不同而错位。
struct HoldToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    /// 卡片圆角，必须和卡片的 cornerRadius 一致
    var cornerRadius: CGFloat = 0
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

    private var holdDuration: Double { gracePeriod + fillDuration }

    var body: some View {
        content
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.red)
                        Text("删除")
                            .font(Typography.bodyStrong)
                            .foregroundStyle(.white)
                            .padding(.trailing, 18)
                    }
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: geo.size.width * progress)
                    }
                }
                .allowsHitTesting(false)
            }
            // 只有右半边响应长按；左半边不接管点击，留给内容自己的「编辑」
            .overlay {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: geo.size.width / 2)
                            .allowsHitTesting(false)
                        Color.clear
                            .contentShape(Rectangle())
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
                    }
                }
            }
            .onDisappear { fillTask?.cancel() }
    }
}
