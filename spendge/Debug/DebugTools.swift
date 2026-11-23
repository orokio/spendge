import SwiftUI

/// 设置页里的开发者入口。Release 构建不渲染任何内容。
struct DebugSettingsEntry: View {
    @Binding var isPresented: Bool

    var body: some View {
        #if DEBUG
        if DebugMode.isUnlocked {
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hammer")
                        .font(Typography.body)
                        .foregroundStyle(Color.brand)
                        .frame(width: 24)
                    Text("开发者")
                        .font(Typography.body)

                    Spacer(minLength: 12)

                    Text("故障注入与数据模拟")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        #endif
    }
}

extension View {
    /// 只在 DEBUG 响应连点解锁
    @ViewBuilder
    func debugUnlockTap(_ onUnlock: @escaping () -> Void) -> some View {
        #if DEBUG
        onTapGesture {
            if DebugMode.registerTap() {
                onUnlock()
            }
        }
        #else
        self
        #endif
    }
}
