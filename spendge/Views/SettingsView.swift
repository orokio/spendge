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

    @Environment(\.modelContext) private var context

    @AppStorage(PreferenceKey.stayAfterSave) private var stayAfterSave = true
    @State private var showPrivacyPolicy = false

    @State private var sharedFile: SharedFile?
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var pendingRestore: Data?
    @State private var notice: ConfirmRequest?
    @State private var showDebugPanel = false

    var body: some View {
        let _ = LaunchTrace.once("settings.body")
        ZStack {
            // NavigationStack 自带不透明底色，这里重新铺回渐变
            AppBackground()
                .ignoresSafeArea()

        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                Text("设置")
                    .font(Typography.pageTitle)
                    .padding(.top, 56)

                group([
                    Item(icon: "icloud", title: "iCloud 云同步", detail: "暂未接入", isOn: nil),
                ])

                group([
                    Item(icon: "square.and.pencil", title: "记下后留在记录页", detail: "", isOn: $stayAfterSave),
                ])

                dataGroup

                privacyGroup

                group([
                    Item(icon: "info.circle", title: "关于", detail: appVersionText),
                ])

                DebugSettingsEntry(isPresented: $showDebugPanel)

            }
            .padding(.horizontal, PageLayout.pageInset)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Analytics.record(.settingsOpened) }
        .toolbar(.hidden, for: .navigationBar)
        }
        .contentShape(Rectangle())
        .toast($toast)
        .errorToast($errorMessage)
        .overlay {
            ZStack {
                #if DEBUG
                if showDebugPanel {
                    DebugPanelView(onClose: closeDebugPanel)
                        .transition(.move(edge: .trailing))
                }
                #endif
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showDebugPanel)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(url: file.url) { completed in
                sharedFile = nil
                if completed {
                    Toast.show("已导出 \(file.url.lastPathComponent)", into: $toast, duration: 2.2)
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmDialog($notice)
    }

    private func closeDebugPanel() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showDebugPanel = false
        }
    }

    // MARK: - 隐私

    /// 关于页显示「1.0 (2)」：主版本 + 构建号，都从 Bundle 读，不写死
    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var privacyGroup: some View {
        VStack(spacing: 0) {
            actionRow(icon: "doc.text", title: "隐私政策", detail: "") {
                showPrivacyPolicy = true
            }
        }
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
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
            actionRow(icon: "doc.text.magnifyingglass", title: "诊断日志", detail: "仅本地") {
                exportDiagnostics()
            }
            divider
            actionRow(icon: "trash", title: "清除全部记录", detail: "", destructive: true) {
                notice = ConfirmRequest(
                    title: "清除全部记录？",
                    message: "会删除所有账单、预算、目标和「没花钱」确认，分类与账户保留。此操作无法撤销，建议先导出一份备份。",
                    confirmTitle: "清除",
                    onConfirm: { clearAllData() }
                )
            }
        }
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
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
                    .font(Typography.body)
                    .foregroundStyle(destructive ? Color.danger : Color.brand)
                    .frame(width: 24)
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(destructive ? Color.danger : Color.textPrimary)
                Spacer(minLength: 12)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(Typography.captionStrong)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 只导出本地诊断日志，供反馈问题时附上；不含金额与备注
    private func exportDiagnostics() {
        let url = Analytics.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            toast = "还没有诊断日志"
            return
        }
        sharedFile = SharedFile(url: url)
    }

    private func exportCSV() {
        do {
            let text = try BackupService(context: context).csv(scope: .all)
            Analytics.record(.backup, ["action": "export_csv", "result": "ok"])
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("海绵记账-\(Self.dateStamp()).csv")
            try text.data(using: .utf8)?.write(to: url)
            sharedFile = SharedFile(url: url)
        } catch {
            Analytics.record(.backup, ["action": "export_csv", "result": "fail", "code": Analytics.errorCode(error)])
            errorMessage = ErrorText.message(for: error)
        }
    }

    private func exportBackup() {
        do {
            let data = try BackupService(context: context).backupData()
            Analytics.record(.backup, ["action": "export_json", "result": "ok"])
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("海绵记账-备份-\(Self.dateStamp()).json")
            try data.write(to: url)
            sharedFile = SharedFile(url: url)
        } catch {
            Analytics.record(.backup, ["action": "export_json", "result": "fail", "code": Analytics.errorCode(error)])
            errorMessage = ErrorText.message(for: error)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "这个文件读不出来"
            return
        }
        guard data.count <= InputLimits.backupFileBytes else {
            errorMessage = "备份文件超过 20MB，不像是这个 App 导出的备份"
            return
        }

        let file: BackupFile
        do {
            file = try BackupService(context: context).validateBackupData(data)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        pendingRestore = data
        notice = ConfirmRequest(
            title: "从备份恢复？",
            message: "将恢复 \(file.transactions.count) 笔记录、\(file.budgets.count) 条预算、\(file.goals?.count ?? 0) 个目标，并替换当前全部数据。建议先导出一份当前备份。",
            confirmTitle: "覆盖恢复",
            onConfirm: {
                if let data = pendingRestore { performRestore(data) }
            },
            onCancel: { pendingRestore = nil }
        )
    }

    private func performRestore(_ data: Data) {
        do {
            let count = try BackupService(context: context).restore(from: data)
            Analytics.record(.backup, ["action": "restore", "result": "ok", "count": String(count)])
            pendingRestore = nil
            Toast.show("已恢复 \(count) 笔记录", into: $toast)
        } catch {
            Analytics.record(.backup, ["action": "restore", "result": "fail", "code": Analytics.errorCode(error)])
            pendingRestore = nil
            errorMessage = ErrorText.message(for: error)
        }
    }

    /// 清空用户数据，保留分类与账户（否则记录页没有可选项）
    private func clearAllData() {
        do {
            // 目标的集合属性在对象被删后再访问会触发未解析的 fault，
            // 先读一遍让 SwiftData 把值载进来，删完就不会崩
            let goals = try context.fetch(FetchDescriptor<Goal>())
            for goal in goals { _ = goal.categoryCodes }
            let goalAchievements = try context.fetch(FetchDescriptor<GoalAchievement>())
            let trophyUnlocks = try context.fetch(FetchDescriptor<TrophyUnlock>())

            // 目标单独存一次盘：删完立刻让列表变空，视图就不会在中间态
            // 去算一个已经失效的目标的进度
            for item in goalAchievements { context.delete(item) }
            for item in trophyUnlocks { context.delete(item) }
            for item in goals { context.delete(item) }
            try context.save()

            for item in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<Budget>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<DayConfirmation>()) { context.delete(item) }
            try context.save()
            Toast.show("已清空全部记录", into: $toast)
        } catch {
            errorMessage = ErrorText.message(for: error)
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
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(Typography.body)
                .foregroundStyle(Color.brand)
                .frame(width: 24)

            Text(item.title)
                .font(Typography.body)

            Spacer(minLength: 12)

            if let isOn = item.isOn {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(Color.brand)
            } else if !item.detail.isEmpty {
                Text(item.detail)
                    .font(Typography.label)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .contentShape(Rectangle())
    }
}
