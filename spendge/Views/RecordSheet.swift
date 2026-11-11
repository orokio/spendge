import SwiftUI
import SwiftData

/// 记一笔：半屏面板。
/// 键盘常驻，分类做成左侧竖向标签列——输入金额不再多一步。
struct RecordSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
    @State private var detent: PresentationDetent = .fraction(0.73)
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
            .padding(.top, 34)
            .onChange(of: kind) { _, _ in
                amountEdited = false
                select(categories.first)
            }

            ScrollView {
                VStack(spacing: 12) {
                    dateAxis
                    amountView
                    if !suggestion.chips.isEmpty { chipRow }

                    HStack(alignment: .top, spacing: 14) {
                        tagRail
                        keypad
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 10) {
                noteField
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.fraction(0.73), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { noteFocused = false }
            }
        }
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
            VStack(spacing: 6) {
                ForEach(categories) { category in
                    let selected = selectedCategory?.id == category.id
                    Button {
                        select(category)
                    } label: {
                        Text(category.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
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
        .frame(width: 96)
        .frame(maxHeight: 216)
    }

    // MARK: - 金额

    private var amountView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("≈")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text(inputYuan > 0 ? "\(inputYuan)" : "0")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(inputYuan > 0 ? Color.brand : Color.secondary.opacity(0.3))
                .contentTransition(.numericText())

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(suggestion.chips.prefix(4), id: \.self) { chip in
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
                            inputYuan * 100 == chip ? Color.brand : Color(.secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                        .foregroundStyle(inputYuan * 100 == chip ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
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
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        guard inputYuan < 100_000 else { return }
        inputYuan = inputYuan * 10 + (Int(digit) ?? 0)
        usedEstimate = false
        amountEdited = true
    }

    // MARK: - 备注 / 保存

    private var noteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("备注（可选）", text: $note)
                .font(.subheadline)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
        dismiss()
    }
}
