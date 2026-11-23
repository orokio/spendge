import SwiftUI

enum OnboardingTarget: Hashable {
    case emotion
    case noSpend
    case recordFab
    case budget
}

struct OnboardingAnchorKey: SwiftUI.PreferenceKey {
    static var defaultValue: [OnboardingTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [OnboardingTarget: Anchor<CGRect>],
                       nextValue: () -> [OnboardingTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 给聚光灯标记一个被高亮的区域
    func onboardingAnchor(_ target: OnboardingTarget) -> some View {
        anchorPreference(key: OnboardingAnchorKey.self, value: .bounds) { [target: $0] }
    }

    @ViewBuilder
    func onboardingAnchor(_ target: OnboardingTarget, isActive: Bool) -> some View {
        if isActive {
            onboardingAnchor(target)
        } else {
            self
        }
    }
}

struct OnboardingStep {
    let title: String
    let detail: String
    let indexText: String
    /// 圆形目标（例如 FAB）用圆环，其余用圆角矩形
    var circular = false
}

/// 透明聚光灯：压暗全屏，在目标区域挖洞，旁边给出说明。
/// 点击屏幕任意位置进入下一步；气泡里也有「下一步」和「跳过」。
struct OnboardingSpotlight: View {
    let hole: CGRect
    let step: OnboardingStep
    let onNext: () -> Void
    let onSkip: () -> Void

    private let ringInset: CGFloat = 6
    private let tooltipWidth: CGFloat = 320
    private let estimatedTooltipHeight: CGFloat = 150

    var body: some View {
        GeometryReader { proxy in
            let expanded = hole.insetBy(dx: -ringInset, dy: -ringInset)
            let corner = step.circular ? expanded.height / 2 : 20
            let above = hole.midY > proxy.size.height * 0.5
            let rawY = above
                ? hole.minY - 16 - estimatedTooltipHeight / 2
                : hole.maxY + 16 + estimatedTooltipHeight / 2
            let y = min(max(rawY, estimatedTooltipHeight / 2 + 56),
                        proxy.size.height - estimatedTooltipHeight / 2 - 40)

            ZStack(alignment: .topLeading) {
                SpotlightMask(hole: expanded, cornerRadius: corner)
                    .fill(Color.textPrimary.opacity(0.38), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .onTapGesture(perform: onNext)

                // 洞口也吃点击：引导期间不让下方控件抢走这一步
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: expanded.width, height: expanded.height)
                    .contentShape(Rectangle())
                    .position(x: expanded.midX, y: expanded.midY)
                    .onTapGesture(perform: onNext)

                RoundedRectangle(cornerRadius: corner)
                    .stroke(Color.onAccent.opacity(0.9), lineWidth: 2)
                    .frame(width: expanded.width, height: expanded.height)
                    .position(x: expanded.midX, y: expanded.midY)
                    .allowsHitTesting(false)

                tooltip
                    .frame(width: min(tooltipWidth, proxy.size.width - 40))
                    .position(x: proxy.size.width / 2, y: y)
            }
        }
        .ignoresSafeArea()
    }

    private var tooltip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.indexText)
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)

            Text(step.title)
                .font(Typography.bodyStrong)
                .foregroundStyle(Color.textPrimary)

            Text(step.detail)
                .font(Typography.label)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button(action: onNext) {
                    Text("下一步")
                        .font(Typography.bodyStrong)
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("跳过")
                        .font(Typography.body)
                        .foregroundStyle(Color.textSecondary)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

private struct SpotlightMask: Shape {
    let hole: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(Path(roundedRect: hole, cornerRadius: cornerRadius))
        return path
    }
}
