import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 设置：云同步、开关、数据导出等。
/// 同步与开关仍是占位；数据组已接实现（CSV 导出 / JSON 备份 / 恢复）。
struct SettingsView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        var isOn: Binding<Bool>?
    }

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var isConfirm = false
        var confirmTitle = "继续"
        var onConfirm: (() -> Void)?
    }

    @Environment(\.modelContext) private var context

    @AppStorage(PreferenceKey.stayAfterSave) private var stayAfterSave = true

    @State private var showLanguagePicker = false
    @State private var sharedFile: SharedFile?
    @State private var toast: String?
    @State private var showImporter = false
    @State private var pendingRestore: Data?
    @State private var notice: Notice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                Text("我的")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .padding(.top, 56)

                VStack(spacing: 0) {
                    actionRow(icon: "globe", title: "语言", detail: currentLanguageName) {
                        showLanguagePicker = true
                    }
                }
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))

                group([
                    Item(icon: "icloud", title: "iCloud 云同步", detail: "暂未接入", isOn: nil),
                ])

                group([
                    Item(icon: "square.and.pencil", title: "记下后留在记录页", detail: "", isOn: $stayAfterSave),
                ])

                dataGroup

                group([
                    Item(icon: "info.circle", title: "关于", detail: "0.1"),
                ])

            }
            .padding(.horizontal, PageLayout.pageInset)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .toast($toast)
        .sheet(isPresented: $showLanguagePicker) {
            languageSheet
                .presentationDetents([.fraction(1.0 / 3.0)])
                .presentationCornerRadius(24)
                .presentationBackground(Color.surfaceElevated)
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(url: file.url) { completed in
                sharedFile = nil
                if completed {
                    Toast.show(
                        String(format: String(localized: "toast.exported"), file.url.lastPathComponent),
                        into: $toast,
                        duration: 2.2
                    )
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert(item: $notice) { notice in
            if notice.isConfirm {
                return Alert(
                    title: Text(LocalizedStringKey(notice.title)),
                    message: Text(LocalizedStringKey(notice.message)),
                    primaryButton: .destructive(Text(LocalizedStringKey(notice.confirmTitle))) {
                        notice.onConfirm?()
                    },
                    secondaryButton: .cancel(Text("取消")) { pendingRestore = nil }
                )
            }
            return Alert(
                title: Text(LocalizedStringKey(notice.title)),
                message: Text(LocalizedStringKey(notice.message)),
                dismissButton: .default(Text("好"))
            )
        }
    }

    // MARK: - 语言

    private var currentLanguageCode: String {
        Locale.preferredLanguages.first ?? "zh-Hans"
    }

    private var currentLanguageName: String {
        currentLanguageCode.hasPrefix("zh") ? "中文" : "English"
    }

    private var languageSheet: some View {
        VStack(spacing: 0) {
            languageOption(code: "zh-Hans", name: "中文")
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 0.5)
            languageOption(code: "en", name: "English")
        }
        .padding(.horizontal, PageLayout.pageInset)
        .padding(.top, 20)
    }

    private func languageOption(code: String, name: String) -> some View {
        let selected = currentLanguageCode.hasPrefix(code.hasPrefix("zh") ? "zh" : "en")
        return Button {
            showLanguagePicker = false
            switchLanguage(to: code, name: name)
        } label: {
            HStack {
                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brand)
                }
            }
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 写 AppleLanguages，重启后整包生效（String(localized:) 读的是 Bundle 语言）
    private func switchLanguage(to code: String, name: String) {
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        notice = Notice(
            title: String(format: String(localized: "settings.switched"), name),
            message: String(localized: "重启 App 后生效。"),
            isConfirm: false
        )
    }

    // MARK: - 数据

    private var dataGroup: some View {
        VStack(spacing: 0) {
            actionRow(icon: "tablecells", title: "导出账单", detail: "CSV") {
                exportCSV()
            }
            divider
            actionRow(icon: "shippingbox", title: "导出备份", detail: "JSON") {
                exportBackup()
            }
            divider
            actionRow(icon: "arrow.down.doc", title: "从备份恢复", detail: "") {
                showImporter = true
            }
            divider
            actionRow(icon: "trash", title: "清除全部记录", detail: "", destructive: true) {
                notice = Notice(
                    title: "清除全部记录？",
                    message: "会删除所有账单、预算和「没花钱」确认，分类与账户保留。此操作无法撤销，建议先导出一份备份。",
                    isConfirm: true,
                    confirmTitle: "清除",
                    onConfirm: { clearAllData() }
                )
            }
        }
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, 48)
    }

    private func actionRow(icon: String, title: String, detail: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(destructive ? Color.red : Color.brand)
                    .frame(width: 24)
                Text(LocalizedStringKey(title))
                    .font(.subheadline)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                Spacer(minLength: 12)
                if !detail.isEmpty {
                    Text(LocalizedStringKey(detail))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func exportCSV() {
        do {
            let text = try BackupService(context: context).csv(scope: .all)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("海绵记账-\(Self.dateStamp()).csv")
            try text.data(using: .utf8)?.write(to: url)
            sharedFile = SharedFile(url: url)
        } catch {
            notice = Notice(title: "导出失败", message: "\(error)")
        }
    }

    private func exportBackup() {
        do {
            let data = try BackupService(context: context).backupData()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("海绵记账-备份-\(Self.dateStamp()).json")
            try data.write(to: url)
            sharedFile = SharedFile(url: url)
        } catch {
            notice = Notice(title: "备份失败", message: "\(error)")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            notice = Notice(title: "读取失败", message: "这个文件读不出来")
            return
        }
        pendingRestore = data
        notice = Notice(
            title: "从备份恢复？",
            message: "会用备份里的内容替换当前所有记录、预算和「没花钱」确认。建议先导出一份当前备份。",
            isConfirm: true,
            confirmTitle: "覆盖恢复",
            onConfirm: {
                if let data = pendingRestore { performRestore(data) }
            }
        )
    }

    private func performRestore(_ data: Data) {
        do {
            let count = try BackupService(context: context).restore(from: data)
            pendingRestore = nil
            Toast.show(String(format: String(localized: "toast.restored"), count), into: $toast)
        } catch {
            pendingRestore = nil
            notice = Notice(title: "恢复失败", message: "\(error)")
        }
    }

    /// 清空用户数据，保留分类与账户（否则记录页没有可选项）
    private func clearAllData() {
        do {
            for item in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<Budget>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<DayConfirmation>()) { context.delete(item) }
            try context.save()
            Toast.show("已清空全部记录", into: $toast)
        } catch {
            notice = Notice(title: "清除失败", message: "(error)")
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: .now)
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
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.brand)
                .frame(width: 24)

            Text(LocalizedStringKey(item.title))
                .font(.subheadline)

            Spacer(minLength: 12)

            if let isOn = item.isOn {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(Color.brand)
            } else if !item.detail.isEmpty {
                Text(LocalizedStringKey(item.detail))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .contentShape(Rectangle())
    }
}

/// 系统分享面板：导出 CSV / JSON 后直接调起
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // 分享面板关掉后回调：用户真的存/发出去了才提示
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
