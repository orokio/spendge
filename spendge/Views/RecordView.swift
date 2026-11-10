import SwiftUI
import SwiftData

/// 记一笔：把输入变成选择。
/// 流程是「点分类 → 金额已填好 → 确认」，全程不出现键盘（备注除外）。
struct RecordView: View {
    @Binding var selectedTab: MainTabView.Tab

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)])
    private var allCategories: [Category]
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    @State private var kind: TransactionKind = .expense
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var inputYuan = 0
    @State private var suggestion: AmountSuggestion = .empty
    @State private var usedEstimate = false
    @State private var date = Date.now
    @State private var note = ""
    @State private var isImpulse = false
    @State private var showKeyboard = false
    @State private var showMore = false
    @State private var showDatePicker = false
    @State private var savedFlash = false

    private var categories: [Category] {
        allCategories.filter { $0.kind == kind && !$0.isArchived }
    }

    private var accounts: [Account] {
        allAccounts.filter { !$0.isArchived }
    }

    private var amountCents: Int64 { Int64(inputYuan) * 100 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    amountSection
                    categoryGrid
                    dateRow
                    if showMore { moreSection }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { saveButton }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(TransactionKind.expense)
                        Text("收入").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showMore ? "收起" : "更多") {
                        withAnimation(.easeInOut(duration: 0.2)) { showMore.toggle() }
                    }
                    .font(.subheadline)
                }
            }
            .task {
                if selectedCategory == nil { select(defaultCategory()) }
                if selectedAccount == nil { selectedAccount = accounts.first }
            }
            .onChange(of: kind) { _, _ in
                if selectedCategory?.kind != kind { select(categories.first) }
            }
            .sensoryFeedback(.success, trigger: savedFlash)
            .overlay(alignment: .top) {
                if savedFlash {
                    Text("已记下")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("选择日期")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showDatePicker = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 金额

    private var amountSection: some View {
        VStack(spacing: 12) {
            Group {
                if inputYuan > 0 {
                    Text(AmountFormat.string(cents: amountCents))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                } else {
                    Text(suggestion.style == .bucketsOnly ? "选一个大概的金额" : "点这里输入金额")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { showKeyboard.toggle() }
            }

            if !suggestion.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(suggestion.chips, id: \.self) { chip in
                        Button {
                            inputYuan = Int(chip / 100)
                            usedEstimate = suggestion.style == .bucketsOnly
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

            if showKeyboard { keypad }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            spacing: 8
        ) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { digit in
                keyButton(digit) { append(digit) }
            }
            keyButton("清零") { inputYuan = 0; usedEstimate = false }
            keyButton("0") { append("0") }
            keyButton("⌫") { inputYuan /= 10 }
        }
        .padding(.horizontal, 8)
    }

    private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        guard inputYuan < 100_000 else { return }
        inputYuan = inputYuan * 10 + (Int(digit) ?? 0)
        usedEstimate = false
    }

    // MARK: - 分类

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
            ForEach(categories) { category in
                Button {
                    select(category)
                } label: {
                    CategoryBadge(
                        category: category,
                        iconSize: 46,
                        isSelected: selectedCategory?.id == category.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 日期

    private var dateRow: some View {
        HStack(spacing: 8) {
            dateChip("今天", daysAgo: 0)
            dateChip("昨天", daysAgo: 1)
            Button {
                showDatePicker = true
            } label: {
                let isOther = !isQuickDate(0) && !isQuickDate(1)
                Text(isOther ? date.formatted(.dateTime.month().day()) : "更早")
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isOther ? Color.brand : Color(.secondarySystemGroupedBackground), in: Capsule())
                    .foregroundStyle(isOther ? .white : .primary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func dateChip(_ title: String, daysAgo: Int) -> some View {
        Button {
            date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        } label: {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isQuickDate(daysAgo) ? Color.brand : Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .foregroundStyle(isQuickDate(daysAgo) ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func isQuickDate(_ daysAgo: Int) -> Bool {
        let target = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return Calendar.current.isDate(date, inSameDayAs: target)
    }

    // MARK: - 更多

    private var moreSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
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
                    fieldCard(icon: selectedAccount?.iconName ?? "wallet.pass.fill", title: selectedAccount?.name ?? "账户")
                }

                Toggle(isOn: $isImpulse) {
                    Text("冲动了")
                        .font(.subheadline)
                }
                .tint(.brand)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                TextField("备注（可选）", text: $note)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func fieldCard(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 保存

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(usedEstimate ? "记下（约 \(AmountFormat.string(cents: amountCents))）" : "记下")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSave ? Color.brand : Color.gray.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .disabled(!canSave)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var canSave: Bool {
        amountCents > 0 && selectedCategory != nil && (selectedAccount ?? accounts.first) != nil
    }

    // MARK: - 动作

    /// 最近 30 天用得最多的分类；没有历史时取第一个。
    private func defaultCategory() -> Category? {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        let recent = (try? TransactionService(context: context).transactions(from: start, to: .now)) ?? []
        var counts: [UUID: Int] = [:]
        for txn in recent {
            guard let id = txn.category?.id, txn.kind == kind else { continue }
            counts[id, default: 0] += 1
        }
        guard !counts.isEmpty else { return categories.first }
        return categories.max { (counts[$0.id] ?? 0) < (counts[$1.id] ?? 0) }
    }

    private func select(_ category: Category?) {
        selectedCategory = category
        usedEstimate = false
        guard let category else {
            suggestion = .empty
            inputYuan = 0
            return
        }
        suggestion = (try? TransactionService(context: context).amountSuggestion(for: category)) ?? .empty
        inputYuan = Int((suggestion.prefillCents ?? 0) / 100)
    }

    private func save() {
        guard canSave, let category = selectedCategory, let account = selectedAccount ?? accounts.first else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? TransactionService(context: context).add(
            amountCents: amountCents,
            kind: kind,
            date: date,
            note: trimmed.isEmpty ? nil : trimmed,
            isApproximateAmount: usedEstimate,
            isImpulse: isImpulse ? true : nil,
            source: .manual,
            category: category,
            account: account
        )

        savedFlash = true
        note = ""
        isImpulse = false
        usedEstimate = false
        inputYuan = Int((suggestion.prefillCents ?? 0) / 100)
        showKeyboard = false

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            savedFlash = false
        }
    }
}
