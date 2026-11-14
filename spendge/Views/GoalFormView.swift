import SwiftUI
import SwiftData

/// 新增 / 修改目标：选维度、选分类（只给该维度允许的）、填阈值。
struct GoalFormView: View {
    /// nil 表示新建
    let goal: Goal?
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Category.sortOrder)]) private var categories: [Category]

    @State private var dragOffset: CGFloat = 0
    @State private var title: String
    @State private var kind: GoalKind
    @State private var period: GoalPeriod
    @State private var categoryCode: String
    @State private var valueText: String
    @State private var toast: String?
    @State private var showDeleteConfirm = false

    init(goal: Goal?, onClose: @escaping () -> Void) {
        self.goal = goal
        self.onClose = onClose
        let kind = goal?.kind ?? .countLimit
        _title = State(initialValue: goal?.title ?? "")
        _kind = State(initialValue: kind)
        _period = State(initialValue: goal?.period ?? .month)
        _categoryCode = State(initialValue: goal?.categoryCodes.first ?? "")
        let raw = goal?.targetValue ?? 0
        _valueText = State(initialValue: goal == nil ? "" : Self.text(kind: kind, value: raw))
    }

    private static func text(kind: GoalKind, value: Int) -> String {
        kind == .categorySum ? String(value / 100) : String(value)
    }

    /// 当前维度允许的分类（白名单顺序）
    private var allowedCategories: [Category] {
        goalKindCodes.compactMap { code in
            categories.first { $0.categoryCode == code && !$0.isArchived }
        }
    }

    private var goalKindCodes: [CategoryCode] { kind.allowedCategoryCodes }

    private var needsCategory: Bool { !goalKindCodes.isEmpty }

    private var parsedValue: Int? {
        guard let value = Int(valueText), value > 0 else { return nil }
        switch kind {
        case .countLimit: return value
        case .categorySum: return value * 100
        case .shareCap: return min(value, 100)
        case .netInflow: return value * 100
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    private var effectiveCodes: [String] {
        needsCategory && !categoryCode.isEmpty ? [categoryCode] : []
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
        return !needsCategory || !categoryCode.isEmpty
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(goal == nil ? "新增目标" : "修改目标")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .padding(.top, 56)

                    field("名字") {
                        TextField("给这个目标起个名字", text: $title)
                            .font(.body)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                    }

                    field("维度") {
                        Picker("", selection: $kind) {
                            Text("次数").tag(GoalKind.countLimit)
                            Text("金额").tag(GoalKind.categorySum)
                            Text("占比").tag(GoalKind.shareCap)
                            Text("结余").tag(GoalKind.netInflow)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: kind) { _, _ in
                            if !goalKindCodes.contains(where: { $0.rawValue == categoryCode }) {
                                categoryCode = allowedCategories.first?.categoryCode?.rawValue ?? ""
                            }
                        }
                    }

                    // 分类竖列在左，上限与保存按钮在右
                    HStack(alignment: .top, spacing: 16) {
                        if needsCategory {
                            categoryRail
                        } else {
                            // 结余的范围就是全部，给一个不可选的占位，避免左侧空掉
                            Text("全部")
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .frame(width: 96, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(Color.brand, in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            field("周期") {
                                // 目前只支持月度，先做成不可改的展示
                                HStack(spacing: 6) {
                                    Text("月度")
                                        .font(.subheadline)
                                    Text("暂不可更改")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                            }

                            field(hintLabel) {
                                HStack(spacing: 8) {
                                    TextField("0", text: $valueText)
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.brand)
                                    Text(kind.unitSuffix)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                            }

                            // 保存为主，右侧是取消（新建）或删除（修改）
                            HStack(spacing: 10) {
                                Button {
                                    save()
                                } label: {
                                    Text("保存")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.vertical, 14)
                                        .frame(maxWidth: .infinity)
                                        .background(canSave ? Color.brand : Color.secondary.opacity(0.25), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(!canSave)

                                Button {
                                    if goal == nil {
                                        onClose()
                                    } else {
                                        showDeleteConfirm = true
                                    }
                                } label: {
                                    Text(goal == nil ? "取消" : "删除")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(goal == nil ? Color.secondary : Color.red)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 14)
                                        .background(Color.surfaceElevated, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if duplicate != nil {
                                Text("已经有这个目标了，回到列表里改它。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .offset(x: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard value.translation.width > 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if value.translation.width > 120 {
                        onClose()
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .toast($toast)
        .onAppear {
            // 新建时默认选中第一个可选分类，避免进来一片空
            if goal == nil, needsCategory, categoryCode.isEmpty {
                categoryCode = allowedCategories.first?.categoryCode?.rawValue ?? ""
            }
        }
        .alert("删除这个目标？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let goal {
                    try? GoalService(context: context).delete(goal)
                }
                onClose()
            }
        } message: {
            Text("已经达成的记录会保留。")
        }
    }

    private var hintLabel: String {
        switch kind {
        case .countLimit: return "上限是多少次"
        case .categorySum: return "上限是多少元"
        case .shareCap: return "占比不超过（%）"
        case .netInflow: return "至少结余多少元"
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// 左侧竖列：和记录页同一套样式
    private var categoryRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 9) {
                ForEach(allowedCategories) { category in
                    let code = category.categoryCode?.rawValue ?? ""
                    let selected = categoryCode == code
                    Button {
                        categoryCode = code
                    } label: {
                        Text(category.displayName)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                selected ? Color.brand : Color.surface,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 96, height: 300, alignment: .top)
    }

    private func save() {
        guard let value = parsedValue else { return }
        let codes = effectiveCodes
        let finalTitle = trimmedTitle.isEmpty ? fallbackTitle() : trimmedTitle
        let service = GoalService(context: context)

        if let goal {
            try? service.update(goal, title: finalTitle, kind: kind,
                                categoryCodes: codes, period: .month, targetValue: value)
        } else {
            _ = try? service.create(title: finalTitle, kind: kind,
                                    categoryCodes: codes, period: .month, targetValue: value)
        }
        onClose()
    }

    /// 没填名字时按参数拼一个
    private func fallbackTitle() -> String {
        let name = allowedCategories.first { $0.categoryCode?.rawValue == categoryCode }?.displayName ?? ""
        return "\(name) \(valueText) \(kind.unitSuffix)"
    }
}
