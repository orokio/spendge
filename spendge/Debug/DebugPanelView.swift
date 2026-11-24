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
    @State private var confirmingCrash = false
    private let implementedFaults: [FaultPoint] = [
        .transactionWrite, .goalWrite, .budgetWrite, .dayConfirmationWrite, .shareExport,
    ]

    var body: some View {
        SecondaryPage(onClose: onClose) {
            VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                header
                faultSection
                scenarioSection
                crashSection
                closeSection
            }
        }
        .toast($toast)
        .errorToast($errorMessage)
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
        .confirmationDialog("模拟崩溃？",
                            isPresented: $confirmingCrash,
                            titleVisibility: .visible) {
            Button("触发崩溃", role: .destructive) { simulateCrash() }
            Button("取消", role: .cancel) { confirmingCrash = false }
        } message: {
            Text("App 会立刻退出。重新打开后 Bugly 才会上报，几分钟后到后台看崩溃列表。")
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

    private var crashSection: some View {
        section(title: "崩溃验证") {
            Button {
                confirmingCrash = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.trianglebadge.exclamationmark")
                        .font(Typography.body)
                        .foregroundStyle(Color.danger)
                        .frame(width: 24)
                    Text("模拟一次崩溃")
                        .font(Typography.body)
                        .foregroundStyle(Color.danger)
                    Spacer(minLength: 8)
                    Text("会退出 App")
                        .font(Typography.label)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .contentShape(Rectangle())
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

    /// 给 Bugly 做端到端验证：等点击动画走完再触发，避免崩在半帧
    private func simulateCrash() {
        confirmingCrash = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            fatalError("Bugly 验证：手动触发的测试崩溃")
        }
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
