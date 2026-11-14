import SwiftUI

/// 顶部浮出的轻提示：与记录页「已记下」同一套样式，全 App 共用。
struct ToastModifier: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let text {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(text)
                }
                .font(Typography.label.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.brand, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 6)
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

extension View {
    /// 顶部提示：绑定非空即显示，1.8 秒后自动消失
    func toast(_ text: Binding<String?>) -> some View {
        modifier(ToastModifier(text: text))
    }
}

@MainActor
enum Toast {
    /// 显示一条提示并自动收起
    static func show(_ text: String, into binding: Binding<String?>, duration: Double = 1.8) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            binding.wrappedValue = text
        }
        Task {
            try? await Task.sleep(for: .seconds(duration))
            guard binding.wrappedValue == text else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                binding.wrappedValue = nil
            }
        }
    }
}
