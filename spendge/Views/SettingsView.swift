import SwiftUI

/// 设置：云同步、开关、数据导出等。当前只是占位，开关和入口都还没接实现。
struct SettingsView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        var isOn: Binding<Bool>?
    }

    @State private var cloudSync = false
    @State private var localVoice = true
    @State private var stayAfterSave = true
    @State private var dailyReminder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("设置")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .padding(.top, 56)

                group([
                    Item(icon: "icloud", title: "iCloud 云同步", detail: cloudSync ? "已开启" : "未开启",
                         isOn: Binding(get: { cloudSync }, set: { _ in cloudSync.toggle() })),
                    Item(icon: "clock.arrow.circlepath", title: "上次同步", detail: "—"),
                ])

                group([
                    Item(icon: "mic", title: "语音识别优先本地", detail: "", isOn: $localVoice),
                    Item(icon: "square.and.pencil", title: "记下后留在记录页", detail: "", isOn: $stayAfterSave),
                    Item(icon: "bell", title: "每日提醒", detail: "", isOn: $dailyReminder),
                ])

                group([
                    Item(icon: "square.and.arrow.up", title: "导出账单", detail: "CSV"),
                    Item(icon: "externaldrive", title: "备份与恢复", detail: ""),
                ])

                group([
                    Item(icon: "info.circle", title: "关于", detail: "0.1"),
                ])

                Text("以上入口暂未接入实现")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 底部留白也算页面：不留形状的话那块透明区域点不中，翻页手势起不来
        .contentShape(Rectangle())
    }

    private func group(_ items: [Item]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 0.5)
                        .padding(.leading, 48)
                }
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.brand)
                .frame(width: 24)

            Text(item.title)
                .font(.subheadline)

            Spacer(minLength: 12)

            if let isOn = item.isOn {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(Color.brand)
                    .disabled(true)   // 占位：还不影响真实行为
            } else if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if item.isOn == nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .contentShape(Rectangle())
    }
}
