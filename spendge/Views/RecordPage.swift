import SwiftUI
import SwiftData

/// 记一笔：整页。键盘常驻，分类在左侧竖列；记下即返回，右滑也能返回。
struct RecordPage: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)])
    private var allCategories: [Category]
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var recentTransactions: [Transaction]

    @State private var kind: TransactionKind = .expense
    @State private var selectedCategory: Category?
    @State private var inputYuan = 0
    @State private var amountEdited = false
    @State private var suggestion: AmountSuggestion = .empty
    @State private var usedEstimate = false
    @State private var date = Date.now
    @State private var note = ""
    @State private var voiceHint: String?
    @State private var showChips = false
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var dragOffset: CGFloat = 0
    @FocusState private var noteFocused: Bool

    private let calendar = Calendar.current

    private var days: [Date] {
        (0..<14).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now))
        }
    }

    private var accounts: [Account] {
        allAccounts.filter { !$0.isArchived }
    }

    /// 固定顺序：sortOrder 决定位置，每 10 个为一组，组间画一条短横线。
    private var categories: [Category] {
        allCategories
            .filter { $0.kind == kind && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var railRows: [RailRow] {
        var rows: [RailRow] = []
        var lastGroup: Int?
        for category in categories {
            let group = category.sortOrder / 10
            if let lastGroup, lastGroup != group {
                rows.append(.divider)
            }
            rows.append(.category(category))
            lastGroup = group
        }
        return rows
    }

    private enum RailRow: Identifiable {
        case category(Category)
        case divider

        var id: String {
            switch self {
            case .category(let category): return category.id.uuidString
            case .divider: return "divider-(UUID().uuidString)"
            }
        }
    }

    private var amountCents: Int64 { Int64(inputYuan) * 100 }

    var body: some View {
        VStack(spacing: 0) {
            Text("记一笔")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            HStack(spacing: 0) {
                kindSegment(.expense, title: "支出")
                kindSegment(.income, title: "收入")
            }
            .padding(3)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            dateAxis
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // 剩余空间全交给两列，底部自然贴屏幕
            GeometryReader { inner in
                HStack(alignment: .top, spacing: 16) {
                    tagRail
                        .frame(height: inner.size.height)

                    VStack(spacing: 12) {
                        amountView
                            .padding(.top, 24)
                        chipRow
                            .padding(.top, 10)
                        // 输入备注时收起数字键盘，把位置让给系统键盘和备注框
                        if noteFocused {
                            HStack {
                                Spacer()
                                Button {
                                    noteFocused = false
                                } label: {
                                    Text("完成")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.brand)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.brand.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(height: 44)
                        } else {
                            keypad
                        }
                        if let voiceHint {
                            Text(voiceHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        noteField
                        HStack(spacing: 10) {
                            saveButton
                            micButton
                        }
                    }
                    .frame(height: inner.size.height, alignment: .top)
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
        }
        .padding(.bottom, 8)
        .background(
            Color(.systemBackground)
                .ignoresSafeArea()
                .onTapGesture { noteFocused = false }
        )
        .offset(x: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = max(0, value.translation.width)
                }
                .onEnded { value in
                    if value.translation.width > 90 {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragOffset = 0 }
                    }
                }
        )
        .task {
            bootstrap()
            // 滑入动画结束后再露出常用金额，避免在滑入过程中突然出现
            try? await Task.sleep(for: .milliseconds(360))
            withAnimation(.easeIn(duration: 0.15)) { showChips = true }
            transcriber.onFinish = { text in
                finishVoice(text)
            }
        }
        .onChange(of: transcriber.transcript) { _, text in
            // 每次都重新解析：识别结果会在结束时被修正一次，
            // 只在结束时解析会让备注和金额对不上。
            applyVoice(text)
        }
    }

    // MARK: - 日期轴

    private func kindSegment(_ value: TransactionKind, title: String) -> some View {
        let selected = kind == value
        return Button {
            guard kind != value else { return }
            amountEdited = false
            kind = value
            select(categories.first)
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    selected ? Color(.systemBackground) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }

    private var dateAxis: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        dayCell(day)
                            .id(day)
                    }
                }
                .padding(.vertical, 1)
                .padding(.trailing, 2)
            }
            .onAppear { proxy.scrollTo(days.last, anchor: .trailing) }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: day)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { date = day }
        } label: {
            VStack(spacing: 3) {
                Text(weekdayLabel(day))
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white : .primary)
            }
            .frame(width: 36, height: 44)
            .background(
                selected ? Color.brand : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private func weekdayLabel(_ day: Date) -> String {
        let index = calendar.component(.weekday, from: day)
        return ["日", "一", "二", "三", "四", "五", "六"][index - 1]
    }

    // MARK: - 分类（左侧竖列）

    private var tagRail: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 9) {
                ForEach(Array(railRows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .divider:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 28, height: 1)
                            .padding(.vertical, 5)
                    case .category(let category):
                        let selected = selectedCategory?.id == category.id
                        Button {
                            select(category)
                        } label: {
                            Text(category.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(
                                    selected ? Color.brand : Color(.systemGray6),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 96)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            // 底部渐隐：暗示还可以往下滚
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 金额

    /// 位数越多字号越小，保持字重和比例，不做整体缩放。
    private var amountFontSize: CGFloat {
        switch String(inputYuan).count {
        case 0...5: return 46
        case 6: return 40
        case 7: return 34
        default: return 30
        }
    }

    private var amountView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("≈")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text(inputYuan > 0 ? "\(inputYuan)" : "0")
                .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(inputYuan > 0 ? Color.brand : Color.secondary.opacity(0.3))
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 固定高度：常用金额是异步算出来的，占位可以避免出现时把键盘顶下去。
    private var chipRow: some View {
        HStack(spacing: 6) {
            if showChips, !suggestion.chips.isEmpty {
                Text("常用")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
            }
            ForEach(showChips ? Array(suggestion.chips.prefix(4)) : [], id: \.self) { chip in
                Button {
                    inputYuan = Int(chip / 100)
                    usedEstimate = suggestion.style == .bucketsOnly
                    amountEdited = true
                } label: {
                    Text("\(chip / 100)")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            inputYuan * 100 == chip ? Color.brand : Color(.systemGray6),
                            in: Capsule()
                        )
                        .foregroundStyle(inputYuan * 100 == chip ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 26, alignment: .leading)
    }

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 5
        ) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { digit in
                keyButton(digit) { append(digit) }
            }
            keyButton("清零", small: true) { inputYuan = 0; usedEstimate = false; amountEdited = true }
            keyButton("0") { append("0") }
            keyButton("⌫") { inputYuan /= 10; amountEdited = true }
        }
        .frame(maxWidth: .infinity)
    }

    private func keyButton(_ label: String, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(small ? .footnote.weight(.medium) : .title3.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        // 判断「加上这一位之后」的数值，避免多进一位
        let next = inputYuan * 10 + (Int(digit) ?? 0)
        guard next < 100_000_000 else { return }
        inputYuan = next
        usedEstimate = false
        amountEdited = true
    }

    // MARK: - 备注 / 保存

    private var noteField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            TextField("备注（可选）", text: $note, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...8)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 语音入口：点一下开始，再点一下结束；说话内容实时写进备注。
    private var micButton: some View {
        Button {
            noteFocused = false
            transcriber.toggle()
        } label: {
            Image(systemName: transcriber.isListening ? "waveform" : "mic.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(transcriber.isListening ? Color.white : Color.brand)
                .frame(width: 48, height: 48)
                .background(
                    transcriber.isListening ? Color.brand : Color.brand.opacity(0.12),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("记下")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    canSave ? Color.brand : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(canSave ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private var canSave: Bool {
        amountCents > 0 && selectedCategory != nil && !accounts.isEmpty
    }

    // MARK: - 动作

    private func bootstrap() {
        if selectedCategory == nil { select(categories.first) }
    }

    private func select(_ category: Category?) {
        selectedCategory = category
        guard let category else {
            suggestion = .empty
            if !amountEdited { inputYuan = 0 }
            return
        }
        suggestion = (try? TransactionService(context: context).amountSuggestion(for: category)) ?? .empty
        if !amountEdited {
            inputYuan = Int((suggestion.prefillCents ?? 0) / 100)
            usedEstimate = false
        }
    }

    /// 边听边填：备注与金额始终来自同一段文本。
    private func applyVoice(_ text: String) {
        guard !text.isEmpty else { return }
        note = text

        let parsed = VoiceParser.parse(text)

        // 认不出分类就落到「其他」，不留着上一次的选择让人误会
        let matched = parsed.categoryCode.flatMap { code in
            allCategories.first { $0.categoryCode == code && $0.kind == kind }
        } ?? allCategories.first { $0.categoryCode == .otherExpense && $0.kind == kind }

        if let matched { select(matched) }

        // 金额：有正经分类就直接用；只落到「其他」时，必须句子里提到了钱
        if let yuan = parsed.yuan, parsed.categoryCode != nil || parsed.hasMoneyCue {
            inputYuan = yuan
            amountEdited = true
        }
    }

    /// 说完给一句明确的反馈：填了什么、没填什么。
    private func finishVoice(_ text: String) {
        guard !text.isEmpty else {
            showHint("没听到内容，再说一次")
            return
        }
        let parsed = VoiceParser.parse(text)

        if parsed.categoryCode != nil, parsed.yuan != nil {
            showHint("已按你说的填好")
        } else if parsed.categoryCode != nil {
            showHint("分类填好了，金额确认一下")
        } else if parsed.yuan != nil {
            showHint("金额填好了，分类先放「其他」")
        } else {
            showHint("没听出来，分类先放「其他」，改一下")
        }
    }

    private func showHint(_ text: String) {
        voiceHint = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if voiceHint == text { voiceHint = nil }
        }
    }

    private func save() {
        guard canSave, let category = selectedCategory, let account = accounts.first else { return }

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? TransactionService(context: context).add(
            amountCents: amountCents,
            kind: kind,
            date: date,
            note: trimmed.isEmpty ? nil : trimmed,
            isApproximateAmount: usedEstimate,
            source: .manual,
            category: category,
            account: account
        )
        onClose()
    }
}