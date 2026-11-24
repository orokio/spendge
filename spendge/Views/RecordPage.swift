import SwiftUI
import SwiftData
import UIKit

/// 记一笔：整页。键盘常驻，分类在左侧竖列；记下后留在页面连着记，点「完成」或右滑返回。
struct RecordPage: View {
    let onClose: () -> Void
    /// 保存成功后回传这笔的日期，首页据此把柱图聚焦到那天
    var onSaved: ((Date) -> Void)?
    /// 非空表示在编辑这一笔：预填它的内容，保存走 update
    private let editing: Transaction?

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)])
    private var allCategories: [Category]
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse), SortDescriptor(\Transaction.createdAt, order: .reverse)]) private var recentTransactions: [Transaction]

    @State private var kind: TransactionKind = .expense
    @State private var selectedCategory: Category?
    /// 已输入的金额文本（"26"、"26.5"），小数最多一位
    @State private var amountText = ""
    @State private var amountEdited = false
    /// 最近用过的不同金额（全分类共享）
    @State private var date = Date.now
    @State private var note = ""
    @State private var voiceHint: String?
    @StateObject private var transcriber = SpeechTranscriber()
    /// 键盘高度：自己算，不用系统安全区（系统在收起时偶尔不归还高度）
    @State private var keyboardInset: CGFloat = 0
    @AppStorage(PreferenceKey.stayAfterSave) private var stayAfterSave = true
    @State private var noteEditing = false
    /// 用户手动点过分类：之后不再用备注自动改他的选择
    @State private var categoryPicked = false
    @State private var toast: String?
    @State private var saveError: String?
    /// 当前编辑的账单已有的退款记录（每单最多一条）
    @State private var existingRefund: Transaction?
    @State private var refundConfirm: ConfirmRequest?

    private let calendar = Calendar.current

    init(editing: Transaction? = nil,
         initialDate: Date = .now,
         onClose: @escaping () -> Void,
         onSaved: ((Date) -> Void)? = nil) {
        self.editing = editing
        self.onClose = onClose
        self.onSaved = onSaved
        _date = State(initialValue: initialDate)
        guard let transaction = editing else { return }
        _kind = State(initialValue: transaction.kind)
        _selectedCategory = State(initialValue: transaction.category)
        // 退款记录存负数，编辑时按正数展示
        _amountText = State(initialValue: Self.text(fromCents: abs(transaction.amountCents)))
        _amountEdited = State(initialValue: true)
        _date = State(initialValue: transaction.date)
        _note = State(initialValue: transaction.note ?? "")
    }

    /// 日期轴默认以今天为终点；编辑超过 7 天的老账单时以那一笔为终点，保证它可见
    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        var anchor = today
        if let recordDay = editing.map({ calendar.startOfDay(for: $0.date) }),
           let windowStart = calendar.date(byAdding: .day, value: -6, to: today),
           recordDay < windowStart {
            anchor = recordDay
        }
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: anchor)
        }
    }

    /// 2650 分 → "26.5"
    private static func text(fromCents cents: Int64) -> String {
        let yuan = cents / 100
        let jiao = (cents % 100) / 10
        return jiao == 0 ? String(yuan) : "\(yuan).\(jiao)"
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

    private var amountCents: Int64 {
        guard !amountText.isEmpty else { return 0 }
        let parts = amountText.split(separator: ".", omittingEmptySubsequences: false)
        let yuan = Int(parts.first ?? "0") ?? 0
        let jiao = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return Int64(yuan) * 100 + Int64(jiao) * 10
    }

    /// 展示用：整数部分加千分位，空显示 0，刚点小数点时补成 "0."
    private var amountDisplay: String {
        guard !amountText.isEmpty else { return "0" }
        let parts = amountText.split(separator: ".", omittingEmptySubsequences: false)
        let integer = groupedDigits(String(parts.first ?? ""))
        let base = integer.isEmpty ? "0" : integer
        guard parts.count > 1 else { return base }
        return base + "." + parts[1]
    }

    /// 1234567 → 1,234,567
    private func groupedDigits(_ digits: String) -> String {
        var result = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return String(result.reversed())
    }

    private var hasAmount: Bool { amountCents > 0 }

    private static var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        SecondaryPage(onClose: onClose,
                      scrollable: false,
                      backgroundColor: Color.surfaceElevated,
                      backgroundTap: { noteEditing = false }) {
            VStack(spacing: 0) {
                Text(editing == nil ? "记一笔" : "编辑")
                    .font(Typography.sectionTitle)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 0) {
                    kindSegment(.expense, title: "支出")
                    kindSegment(.income, title: "收入")
                }
                .padding(3)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.top, 12)

                // 剩余空间全交给两列，底部自然贴屏幕
                GeometryReader { inner in
                    HStack(alignment: .top, spacing: 16) {
                        tagRail
                            .padding(.top, 24)
                            .frame(height: inner.size.height)

                        VStack(spacing: 12) {
                            Text(dateLabel)
                                .font(Typography.label)
                                .foregroundStyle(Color.brand)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 24)

                            amountView
                            // 输入备注时收起数字键盘，把空间让给系统键盘和备注框
                            if !noteEditing {
                                keypad
                            }
                            // 固定占位：提示出现时不会把下面的备注顶动
                            Text(voiceHint ?? " ")
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 16)
                            noteField
                            HStack(alignment: .bottom, spacing: 10) {
                                if editing != nil, editing?.kind == .expense {
                                    refundButton
                                }
                                saveButton
                                micButton
                            }
                        }
                        .frame(height: inner.size.height, alignment: .top)
                    }
                    .padding(.horizontal, PageLayout.pageInset)
                }
                .padding(.top, 12)
            }
            .padding(.bottom, 26 + keyboardInset)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - end.origin.y)
            let safeBottom = Self.bottomSafeInset
            withAnimation(.easeOut(duration: 0.22)) {
                keyboardInset = max(0, overlap - safeBottom)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboardInset = 0 }
        }
        .toast($toast)
        .errorToast($saveError)
        .confirmDialog($refundConfirm)
        .onAppear {
            if let editing {
                existingRefund = try? TransactionService(context: context).refundRecord(of: editing)
            }
        }
        .onDisappear { transcriber.stop() }
        .task {
            bootstrap()
            transcriber.onFinish = { text in
                finishVoice(text)
            }
        }
        .onChange(of: transcriber.transcript) { _, text in
            // 每次都重新解析：识别结果会在结束时被修正一次，
            // 只在结束时解析会让备注和金额对不上。
            applyVoice(text)
        }
        .onChange(of: note) { _, newValue in
            guard newValue.count > InputLimits.noteLength else { return }
            note = String(newValue.prefix(InputLimits.noteLength))
            saveError = "备注最多 \(InputLimits.noteLength) 个字"
        }
        .onChange(of: noteEditing) { _, editing in
            // 备注写完收起键盘时，按「包含范围」帮他选分类
            if !editing { autoCategorizeFromNote() }
        }
    }

    // MARK: - 日期轴

    private func kindSegment(_ value: TransactionKind, title: String) -> some View {
        let selected = kind == value
        return Button {
            guard kind != value else { return }
            amountEdited = false
            kind = value
            // 支出与收入之间切换时，备注和语音提示都不再适用
            note = ""
            noteEditing = false
            voiceHint = nil
            categoryPicked = false
            select(categories.first)
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

    /// 记一笔时的日期：由首页聚焦的那天带过来，只展示不改
    private var dateLabel: String {
        let text = date.formatted(.dateTime.month(.abbreviated).day().weekday(.wide)
            .locale(Locale(identifier: "zh_CN")))
        return calendar.isDateInToday(date) ? "今天 · \(text)" : text
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
                            categoryPicked = true
                            select(category)
                        } label: {
                            Text(category.displayName)
                                .font(Typography.label)
                                // 英文分类名更长：允许两行并轻微缩小，避免被截成 …
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
                                .foregroundStyle(selected ? Color.onAccent : Color.textPrimary)
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
                colors: [Color.surfaceElevated.opacity(0), Color.surfaceElevated],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 金额

    /// 字号固定 46pt，位数多了按宽度自适应缩小，不再一档一档跳
    private let amountFontSize: CGFloat = 46

    private var amountView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("≈")
                .font(Typography.body)
                .foregroundStyle(.secondary)

            Text(amountDisplay)
                .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(hasAmount ? Color.brand : Color.secondary.opacity(0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 5
        ) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { digit in
                keyButton(digit) { append(digit) }
            }
            keyButton(".") { appendDot() }
            keyButton("0") { append("0") }
            keyButton("清零", small: true) { clearAmount() }
        }
        .frame(maxWidth: .infinity)
    }

    private func keyButton(_ label: String, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(small ? Typography.label : Typography.numberLarge)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        if let dotIndex = amountText.firstIndex(of: ".") {
            // 小数点后只允许一位（到毛）
            guard amountText.distance(from: dotIndex, to: amountText.endIndex) < 2 else { return }
            amountText.append(digit)
        } else {
            // 判断「加上这一位之后」的数值，避免多进一位；整数最多七位
            let next = (Int(amountText) ?? 0) * 10 + (Int(digit) ?? 0)
            guard next <= 9_999_999 else { return }
            amountText = String(next)
        }
        amountEdited = true
    }

    private func appendDot() {
        guard !amountText.contains(".") else { return }
        amountText = amountText.isEmpty ? "0." : amountText + "."
        amountEdited = true
    }

    private func clearAmount() {
        amountText = ""
        amountEdited = true
    }

    // MARK: - 备注 / 保存

    private var noteField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(Typography.label)
                .foregroundStyle(.secondary)
                .padding(.top, 3)

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("备注（可选）")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                NoteTextView(text: $note, isEditing: $noteEditing)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
        // 整块灰底都能点进输入，而不是只有第一行
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { noteEditing = true })
    }

    /// 语音入口：点一下开始，再点一下结束；说话内容实时写进备注。
    private var micButton: some View {
        Button {
            noteEditing = false
            transcriber.toggle()
        } label: {
            Image(systemName: transcriber.isListening ? "waveform" : "mic.fill")
                .font(Typography.number)
                .foregroundStyle(transcriber.isListening ? Color.onAccent : Color.brand)
                .frame(width: 48, height: 48)
                .background(
                    transcriber.isListening ? Color.brand : Color.brand.opacity(0.12),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }

    /// 退款：只在编辑已有支出时出现；退过款（包括正在编辑退款记录）后变成不可点的「已退款」
    private var refundButton: some View {
        let refunded = existingRefund != nil || editing?.refundOfID != nil
        return Button {
            guard let editing, !refunded else { return }
            refundConfirm = ConfirmRequest(
                title: "记录一笔退款？",
                message: "会为这笔账单生成一条全额退款记录，时间记在今天。删除原账单时，退款记录会一起删除。",
                confirmTitle: "退款",
                isDestructive: true,
                onConfirm: { performRefund(editing) }
            )
        } label: {
            Text(refunded ? "已退款" : "退款")
                .font(Typography.body)
                .frame(width: 74)
                .frame(height: 48)
                .background(Color.danger.opacity(refunded ? 0.10 : 0.20),
                            in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
                .foregroundStyle(refunded ? Color.textSecondary : Color.danger)
        }
        .buttonStyle(.plain)
        .disabled(refunded)
    }

    private func performRefund(_ original: Transaction) {
        do {
            let service = TransactionService(context: context)
            try service.addRefund(for: original)
            existingRefund = try service.refundRecord(of: original)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSaved?(Date.now)
            onClose()
        } catch {
            saveError = ErrorText.message(for: error)
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(editing == nil ? "记下" : "保存")
                .font(Typography.sectionTitle)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    canSave ? Color.brand : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius)
                )
                .foregroundStyle(canSave ? Color.onAccent : Color.secondary)
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
        loadRecentAmounts()
    }

    private func loadRecentAmounts() {
    }

    private func select(_ category: Category?) {
        selectedCategory = category
    }

    /// 备注里写了明确的东西（比如「PS Plus 会员」）就顺手把分类选好。
    /// 用户自己点过分类就不再插手。
    private func autoCategorizeFromNote() {
        guard !categoryPicked, editing == nil else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let matched = CategoryMatcher.match(trimmed, in: allCategories, kind: kind),
              matched.id != selectedCategory?.id else { return }
        select(matched)
    }

    /// 边听边填：备注与金额始终来自同一段文本。
    private func applyVoice(_ text: String) {
        guard !text.isEmpty else { return }
        note = text

        let parsed = VoiceParser.parse(text)

        // 认不出分类就落到「其他」，不留着上一次的选择让人误会
        let matched = CategoryMatcher.match(text, in: allCategories, kind: kind)
            ?? allCategories.first { $0.categoryCode == .otherExpense && $0.kind == kind }

        if let matched { select(matched) }

        // 金额：有正经分类就直接用；只落到「其他」时，必须句子里提到了钱
        if let yuan = parsed.yuan, parsed.categoryCode != nil || parsed.hasMoneyCue {
            amountText = String(yuan)
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
        let matched = CategoryMatcher.match(text, in: allCategories, kind: kind)

        if matched != nil, parsed.yuan != nil {
            showHint("已按你说的填好")
        } else if matched != nil {
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

        // 编辑：改完就返回，不做连续记账
        if let editing {
            do {
                try TransactionService(context: context).update(
                    editing,
                    amountCents: amountCents,
                    kind: kind,
                    date: date,
                    note: trimmed,
                    category: category,
                    account: account
                )
            } catch {
                saveError = ErrorText.message(for: error)
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSaved?(date)
            onClose()
            return
        }

        do {
            _ = try TransactionService(context: context).add(
                amountCents: amountCents,
                kind: kind,
                date: date,
                note: trimmed.isEmpty ? nil : trimmed,
                source: .manual,
                category: category,
                account: account
            )
        } catch {
            saveError = ErrorText.message(for: error)
            return
        }

        onSaved?(date)

        // 偏好：记完就回去（默认留在页面连着记）
        if !stayAfterSave {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSaved?(date)
            onClose()
            return
        }

        // 留在页面上连着记：给一句确认，然后清空这笔的内容，分类和日期保留
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Toast.show("已记下 \(AmountFormat.string(cents: amountCents)) · \(category.displayName)", into: $toast)
        amountText = ""
        amountEdited = false
        note = ""
        noteEditing = false
        voiceHint = nil
        loadRecentAmounts()
    }

}