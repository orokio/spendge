#if DEBUG
import SwiftUI
import SwiftData

/// 开发者面板：故障注入、数据模拟、诊断。只在 DEBUG 构建存在。
struct DebugPanelView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var pendingScenario: DebugScenario?
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var faultRowsVersion = 0
    @State private var shareFile: SharedFile?

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private let implementedFaults: [FaultPoint] = [
        .transactionWrite, .goalWrite, .budgetWrite, .dayConfirmationWrite, .shareExport,
    ]

    var body: some View {
        SecondaryPage(onClose: onClose) {
            VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                header
                faultSection
                scenarioSection
                diagnosticSection
                closeSection
            }
        }
        .toast($toast)
        .errorToast($errorMessage)
        .sheet(item: $shareFile) { file in
            ShareSheet(url: file.url) { _ in shareFile = nil }
        }
        .confirmationDialog(
            pendingScenario?.title ?? "生成调试数据",
            isPresented: Binding(
                get: { pendingScenario != nil },
                set: { if !$0 { pendingScenario = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("会清空当前账本，继续", role: .destructive) { runPending() }
            Button("取消", role: .cancel) { pendingScenario = nil }
        } message: {
            Text(pendingScenario?.detail ?? "")
        }
    }

    // MARK: - 分区

    private var header: some View {
        Text("开发者")
            .font(Typography.pageTitle)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var faultSection: some View {
        section(title: "故障注入") {
            Toggle("全部写入失败", isOn: allWrites)
                .font(Typography.body)
                .tint(Color.brand)
                .padding(.horizontal, 16)
                .frame(height: 50)

            ForEach(Array(implementedFaults.enumerated()), id: \.element) { index, point in
                divider
                FaultToggleRow(point: point)
                    .id("\(point.rawValue)-\(faultRowsVersion)")
            }
        }
    }

    private var scenarioSection: some View {
        section(title: "数据模拟") {
            ForEach(Array(DebugScenario.allCases.enumerated()), id: \.element) { index, scenario in
                if index > 0 { divider }
                Button {
                    pendingScenario = scenario
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.title)
                                .font(Typography.body)
                                .foregroundStyle(Color.textPrimary)
                            Text(scenario.detail)
                                .font(Typography.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(Typography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var diagnosticSection: some View {
        section(title: "诊断") {
            Button {
                SelfCheck.run(context: context)
                Toast.show("自检已运行，结果写入 Documents/selfcheck.log", into: $toast, duration: 2.4)
            } label: {
                actionLabel(icon: "checkmark.seal", title: "运行 SelfCheck", detail: "49 项")
            }
            .buttonStyle(.plain)

            divider

            Button {
                shareLog()
            } label: {
                actionLabel(icon: "doc.text", title: "自检日志", detail: "导出")
            }
            .buttonStyle(.plain)
        }
    }

    private var closeSection: some View {
        Button {
            DebugMode.setUnlocked(false)
            onClose()
        } label: {
            HStack {
                Image(systemName: "xmark.circle")
                Text("关闭开发者模式")
                Spacer()
            }
            .font(Typography.body)
            .foregroundStyle(Color.danger)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 组件

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Typography.bodyStrong)
                .foregroundStyle(Color.textPrimary)

            VStack(spacing: 0, content: content)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
        }
    }

    private func actionLabel(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Typography.body)
                .foregroundStyle(Color.brand)
                .frame(width: 24)
            Text(title)
                .font(Typography.body)
            Spacer(minLength: 12)
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, 48)
    }

    // MARK: - 动作

    private var allWrites: Binding<Bool> {
        Binding(
            get: {
                FaultPoint.allCases.filter(\.isWrite)
                    .allSatisfy { UserDefaults.standard.bool(forKey: DebugKeys.fault($0)) }
            },
            set: { value in
                FaultPoint.allCases.filter(\.isWrite)
                    .forEach { UserDefaults.standard.set(value, forKey: DebugKeys.fault($0)) }
                faultRowsVersion += 1
            }
        )
    }

    private func shareLog() {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = directory.appendingPathComponent("selfcheck.log")
        guard FileManager.default.fileExists(atPath: url.path) else {
            toast = "还没有自检日志，先运行一次"
            return
        }
        shareFile = SharedFile(url: url)
    }

    private func runPending() {
        guard let scenario = pendingScenario else { return }
        pendingScenario = nil
        do {
            try DebugDataSeeder(context: context).run(scenario)
            Toast.show("已生成：\(scenario.title)", into: $toast, duration: 2.0)
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }
}

private struct FaultToggleRow: View {
    let point: FaultPoint
    @AppStorage private var isOn: Bool

    init(point: FaultPoint) {
        self.point = point
        _isOn = AppStorage(wrappedValue: false, DebugKeys.fault(point))
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(point.title)
                .font(Typography.body)
        }
        .tint(Color.brand)
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}
#endif
