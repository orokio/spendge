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
                .foregroundStyle(Color.onAccent)
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

/// 失败提示：同一位置、同一形状，换成红色底；3 秒后自动收起。
struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let current = message {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(current)
                        .multilineTextAlignment(.leading)
                }
                .font(Typography.label.weight(.medium))
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.danger, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 6)
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: current) {
                    try? await Task.sleep(for: .seconds(3.2))
                    guard message == current else { return }
                    withAnimation(.easeIn(duration: 0.25)) {
                        message = nil
                    }
                }
            }
        }
    }
}

enum ErrorText {
    /// 业务错误直接用给用户看的中文；系统错误不暴露细节。
    static func message(for error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        return "没有成功，请再试一次"
    }
}

extension View {
    /// 顶部提示：绑定非空即显示，1.8 秒后自动消失
    func toast(_ text: Binding<String?>) -> some View {
        modifier(ToastModifier(text: text))
    }

    /// 失败提示：红色胶囊，3 秒后自动消失
    func errorToast(_ message: Binding<String?>) -> some View {
        modifier(ErrorToastModifier(message: message))
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
