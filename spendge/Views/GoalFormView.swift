import SwiftUI
import SwiftData

/// 新增 / 修改目标：选维度、选分类（只给该维度允许的）、填阈值。
struct GoalFormView: View {
    /// nil 表示新建
    let goal: Goal?
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @ObservedObject private var catalog = CategoryCatalog.shared

    @State private var title: String
    @State private var kind: GoalKind
    @State private var period: GoalPeriod
    @State private var categoryCode: String
    @State private var valueText: String
    @State private var isRecurring: Bool
    @State private var toast: String?
    @State private var errorMessage: String?
    /// 抽屉滑完再亮提示，避免它比面板先到
    @State private var hintReady = false
    /// 打开时不要自己抢焦点，等用户点了再弹键盘
    @FocusState private var nameFocused: Bool

    init(goal: Goal?, onClose: @escaping () -> Void) {
        // 备份恢复会删掉旧目标，视图可能还拿着已脱离上下文的引用
        let target = goal?.modelContext == nil ? nil : goal
        self.goal = target
        self.onClose = onClose
        let kind = target?.kind ?? .countLimit
        _title = State(initialValue: target?.title ?? "")
        _kind = State(initialValue: kind)
        _period = State(initialValue: target?.period ?? .month)
        _categoryCode = State(initialValue: target?.categoryCodes.first ?? "")
        let raw = target?.targetValue ?? 0
        _valueText = State(initialValue: target == nil ? "" : Self.text(kind: kind, value: raw))
        _isRecurring = State(initialValue: target?.isRecurring ?? false)
    }

    private static func text(kind: GoalKind, value: Int) -> String {
        kind == .budget ? String(value / 100) : String(value)
    }

    /// 当前维度允许的分类（白名单顺序）
    private var allowedCategories: [CategoryInfo] {
        goalKindCodes.compactMap { code in
            catalog.categories().first { $0.code == code.rawValue && !$0.isArchived }
        }
    }

    private var goalKindCodes: [CategoryCode] { kind.allowedCategoryCodes }

    private var parsedValue: Int? {
        // 允许 0：比如「本月奶茶 0 次」是完全合理的上限；空的输入框仍然不可保存
        guard let value = Int(valueText), value >= 0 else { return nil }
        switch kind {
        case .countLimit: return value
        case .budget: return value * 100
        case .shareCap: return min(value, 100)
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    private var effectiveCodes: [String] {
        categoryCode.isEmpty ? [] : [categoryCode]
    }

    /// 同维度 + 同分类 + 同周期已经存在时，不允许再建一条
    private var duplicate: Goal? {
        guard let existing = try? GoalService(context: context)
            .existingGoal(kind: kind, categoryCodes: effectiveCodes, period: period) else { return nil }
        if let goal, existing.id == goal.id { return nil }
        return existing
    }

    private var canSave: Bool {
        guard parsedValue != nil, duplicate == nil else { return false }
        return !categoryCode.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(goal == nil ? "新增目标" : "修改目标")
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .padding(.bottom, 4)

            row("名字") {
                TextField("给它起个名字", text: $title)
                    .font(Typography.body)
                    .focused($nameFocused)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    // 高度钉死：聚焦时 TextField 自己会缩 2pt，这里不让它影响外面
                    .frame(height: 37)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
            }

            row("维度") {
                HStack(spacing: 0) {
                    kindOption("次数", value: .countLimit)
                    kindOption("金额", value: .budget)
                    kindOption("占比", value: .shareCap)
                }
                .padding(3)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
            }

            // 分类横着排，省掉整列高度
            row("分类") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allowedCategories) { category in
                            let code = category.categoryCode?.rawValue ?? ""
                            let selected = categoryCode == code
                            Button {
                                categoryCode = code
                            } label: {
                                Text(category.displayName)
                                    .font(Typography.label)
                                    .foregroundStyle(selected ? Color.onAccent : Color.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selected ? Color.brand : Color.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if hintReady, duplicate != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("已经有一个同样的目标了")
                        .font(Typography.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.warning.opacity(0.12), in: Capsule())
                // 和下面输入框左边对齐，不压到标签那一列
                .padding(.leading, 76)
                .transition(.opacity)
            }

            // 上限和按钮挤在一行，弹框高度才和预算那层一致
            row("上限") {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("0", text: $valueText)
                            .keyboardType(.numberPad)
                            .font(Typography.number)
                            .foregroundStyle(Color.brand)
                            .frame(height: 23)
                        Text(kind.unitSuffix)
                            .font(Typography.label)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(height: 39)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))

                    Button {
                        guard canSave else { return }
                        save()
                    } label: {
                        Text("保存")
                            .font(Typography.bodyStrong)
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.brand, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        if goal == nil {
                            onClose()
                        } else {
                            togglePauseGoal()
                        }
                    } label: {
                        Text(actionTitle)
                            .font(Typography.bodyStrong)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                isRecurring.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isRecurring ? "checkmark.circle.fill" : "circle")
                        .font(Typography.body)
                        .foregroundStyle(isRecurring ? Color.brand : Color.secondary)
                    Text("循环应用到下个月")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 和上面输入框左边缘对齐，不压到标签列
            .padding(.leading, 76)
        }
        .padding(.horizontal, PageLayout.pageInset)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        // 键盘出现时不要压缩高度，否则抽屉会缩一下
        .fixedSize(horizontal: false, vertical: true)
        .toast($toast)
        .errorToast($errorMessage)
        .onAppear {
            // 打开时显式放掉焦点，键盘不自己弹出来
            nameFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)

            // 新建时默认选中第一个可选分类，避免进来一片空
            if goal == nil, categoryCode.isEmpty {
                categoryCode = allowedCategories.first?.categoryCode?.rawValue ?? ""
            }
            hintReady = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.easeOut(duration: 0.2)) { hintReady = true }
            }
            // 抽屉落位后再放一次焦点，防止动画期间系统又把光标塞进输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                nameFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
        }
    }

    /// 新增时是「取消」，编辑时是「暂停 / 恢复」
    private var actionTitle: String {
        guard let goal else { return "取消" }
        return goal.isActive ? "暂停" : "恢复"
    }

    /// 维度切换：和统计页的支出 / 收入用同一套胶囊
    private func kindOption(_ title: String, value: GoalKind) -> some View {
        let selected = kind == value
        return Button {
            guard kind != value else { return }
            withAnimation(.snappy(duration: 0.2)) {
                kind = value
                if !goalKindCodes.contains(where: { $0.rawValue == categoryCode }) {
                    categoryCode = allowedCategories.first?.categoryCode?.rawValue ?? ""
                }
            }
        } label: {
            Text(title)
                .font(selected ? Typography.bodyStrong : Typography.body)
                .foregroundStyle(selected ? Color.textPrimary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    selected ? Color.surfaceElevated : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }

    /// 左标签、右控件，一行一项
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            content()
        }
    }

    private var hintLabel: String {
        switch kind {
        case .countLimit: return "上限次数"
        case .budget: return "上限金额"
        case .shareCap: return "上限占比"
        }
    }

    private func togglePauseGoal() {
        guard let goal else { return }
        do {
            try FaultInjection.current.check(.goalWrite)
        } catch {
            errorMessage = ErrorText.message(for: error)
            return
        }
        goal.isActive.toggle()
        goal.updatedAt = .now
        do {
            try context.save()
        } catch {
            goal.isActive.toggle()
            errorMessage = ErrorText.message(for: error)
            return
        }
        onClose()
    }

    private func save() {
        guard let value = parsedValue else { return }
        let codes = effectiveCodes
        let finalTitle = trimmedTitle.isEmpty ? fallbackTitle() : trimmedTitle
        let service = GoalService(context: context)

        do {
            if let goal {
                try service.update(goal, title: finalTitle, kind: kind,
                                   categoryCodes: codes, period: .month, targetValue: value,
                                   isRecurring: isRecurring)
            } else {
                _ = try service.create(title: finalTitle, kind: kind,
                                       categoryCodes: codes, period: .month, targetValue: value,
                                       isRecurring: isRecurring)
            }
        } catch {
            errorMessage = ErrorText.message(for: error)
            return
        }
        onClose()
    }

    /// 没填名字时按参数拼一个
    private func fallbackTitle() -> String {
        let name = allowedCategories.first { $0.categoryCode?.rawValue == categoryCode }?.displayName ?? ""
        return "\(name) \(valueText) \(kind.unitSuffix)"
    }
}
