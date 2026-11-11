import SwiftUI
import SwiftData

/// 记一笔：半屏面板。上半屏仍是今天的流水，所以「记的时候看得见今天」。
struct RecordSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)])
    private var allCategories: [Category]
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var recentTransactions: [Transaction]

    @State private var kind: TransactionKind = .expense
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var inputYuan = 0
    @State private var amountEdited = false
    @State private var suggestion: AmountSuggestion = .empty
    @State private var usedEstimate = false
    @State private var date = Date.now
    @State private var note = ""
    @State private var showKeypad = false
    @State private var detent: PresentationDetent = .medium

    private let calendar = Calendar.current

    /// 最近 14 天，今天在最右。
    private var days: [Date] {
        (0..<14).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now))
        }
    }

    private var accounts: [Account] {
        allAccounts.filter { !$0.isArchived }
    }

    /// 最近 30 天用得最多的分类排在前面。
    private var categories: [Category] {
        let start = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
        var counts: [UUID: Int] = [:]
        for txn in recentTransactions where txn.date >= start {
            guard let id = txn.category?.id else { continue }
            counts[id, default: 0] += 1
        }
        return allCategories
            .filter { $0.kind == kind && !$0.isArchived }
            .sorted { lhs, rhs in
                let l = counts[lhs.id] ?? 0
                let r = counts[rhs.id] ?? 0
                return l == r ? lhs.sortOrder < rhs.sortOrder : l > r
            }
    }

    private var amountCents: Int64 { Int64(inputYuan) * 100 }

    var body: some View {
        VStack(spacing: 0) {
            Picker("类型", selection: $kind) {
                Text("支出").tag(TransactionKind.expense)
                Text("收入").tag(TransactionKind.income)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .onChange(of: kind) { _, _ in
                amountEdited = false
                select(categories.first)
            }

            ScrollView {
                VStack(spacing: 16) {
                    dateAxis
                    amountBlock
                    categoryFlow
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 10) {
                noteField
                if accounts.count > 1 { accountPicker }
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task { bootstrap() }
    }

    // MARK: - 日期轴

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
            VStack(spacing: 4) {
                Text(weekdayLabel(day))
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(selected ? .white : .primary)
            }
            .frame(width: 38, height: 46)
            .background(
                selected ? Color.brand : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 13)
            )
        }
        .buttonStyle(.plain)
    }

    private func weekdayLabel(_ day: Date) -> String {
        let index = calendar.component(.weekday, from: day)
        return ["日", "一", "二", "三", "四", "五", "六"][index - 1]
    }

    // MARK: - 金额

    private var amountBlock: some View {
        VStack(spacing: 12) {
            Button {
                toggleKeypad()
            } label: {
                if inputYuan > 0 {
                    Text(AmountFormat.string(cents: amountCents))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                } else {
                    Text(suggestion.style == .bucketsOnly ? "选一个大概的金额" : "点这里输入金额")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(alignment: .bottom) {
                // 让「可以点」有形状可依
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, 40)
            }

            if !suggestion.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(suggestion.chips, id: \.self) { chip in
                        Button {
                            inputYuan = Int(chip / 100)
                            usedEstimate = suggestion.style == .bucketsOnly
                            amountEdited = true
                        } label: {
                            Text("¥\(chip / 100)")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    inputYuan * 100 == chip ? Color.brand : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(inputYuan * 100 == chip ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if showKeypad { keypad }
        }
    }

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            spacing: 8
        ) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { digit in
                keyButton(digit) { append(digit) }
            }
            keyButton("清零") { inputYuan = 0; usedEstimate = false; amountEdited = true }
            keyButton("0") { append("0") }
            keyButton("⌫") { inputYuan /= 10; amountEdited = true }
        }
    }

    private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        guard inputYuan < 100_000 else { return }
        inputYuan = inputYuan * 10 + (Int(digit) ?? 0)
        usedEstimate = false
        amountEdited = true
    }

    // MARK: - 分类

    private var categoryFlow: some View {
        FlowLayout(spacing: 8) {
            ForEach(categories) { category in
                let selected = selectedCategory?.id == category.id
                Button {
                    select(category)
                } label: {
                    Text(category.name)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    .background(
                        selected ? Color.brand : Color(.secondarySystemGroupedBackground),
                        in: Capsule()
                    )
                    .foregroundStyle(selected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 备注 / 账户

    private var noteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("备注（可选）", text: $note)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var accountPicker: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    selectedAccount = account
                } label: {
                    if account.id == selectedAccount?.id {
                        Label(account.name, systemImage: "checkmark")
                    } else {
                        Text(account.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedAccount?.name ?? "账户")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 保存

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(usedEstimate ? "记下（约 \(AmountFormat.string(cents: amountCents))）" : "记下")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
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
        amountCents > 0 && selectedCategory != nil && (selectedAccount ?? accounts.first) != nil
    }

    // MARK: - 动作

    private func bootstrap() {
        if selectedCategory == nil { select(categories.first) }
        if selectedAccount == nil { selectedAccount = accounts.first }
    }

    /// 切换分类时保留用户已经输入的金额，只在他没有手动改过时才应用预填。
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

    private func toggleKeypad() {
        detent = .large
        withAnimation(.easeInOut(duration: 0.18)) { showKeypad.toggle() }
    }

    private func save() {
        guard canSave,
              let category = selectedCategory,
              let account = selectedAccount ?? accounts.first else { return }

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
        dismiss()
    }
}
