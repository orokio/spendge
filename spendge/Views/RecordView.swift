import SwiftUI
import SwiftData

struct RecordView: View {
    @Binding var selectedTab: MainTabView.Tab

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)])
    private var allCategories: [Category]
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    @State private var kind: TransactionKind = .expense
    @State private var digits = ""
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var date = Date.now
    @State private var note = ""
    @State private var savedFlash = false

    private var categories: [Category] {
        allCategories.filter { $0.kind == kind && !$0.isArchived }
    }

    private var accounts: [Account] {
        allAccounts.filter { !$0.isArchived }
    }

    private var amountCents: Int64 {
        Int64(digits) ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amountDisplay

                Picker("类型", selection: $kind) {
                    Text("支出").tag(TransactionKind.expense)
                    Text("收入").tag(TransactionKind.income)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 20) {
                        categoryGrid
                        detailSection
                        noteField
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                }

                keypad
                saveButton
            }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if selectedCategory == nil { selectedCategory = categories.first }
                if selectedAccount == nil { selectedAccount = accounts.first }
            }
            .onChange(of: kind) { _, _ in
                selectedCategory = categories.first
            }
            .sensoryFeedback(.success, trigger: savedFlash)
        }
    }

    private var amountDisplay: some View {
        VStack(spacing: 6) {
            Text(AmountFormat.string(cents: amountCents))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .foregroundStyle(kind == .expense ? Color.primary : Color.income)
            Text(kind == .expense ? "支出金额" : "收入金额")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            ForEach(categories) { category in
                Button {
                    selectedCategory = category
                } label: {
                    CategoryBadge(
                        category: category,
                        iconSize: 48,
                        isSelected: selectedCategory?.id == category.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detailSection: some View {
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
                fieldCard(
                    icon: selectedAccount?.iconName ?? "wallet.pass.fill",
                    title: selectedAccount?.name ?? "选择账户"
                )
            }

            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(.brand)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 52)
    }

    private var noteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
            TextField("备注（可选）", text: $note)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func fieldCard(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 键盘

    private enum KeyRole {
        case digit
        case clear
        case delete
    }

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 10
        ) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { digit in
                keyButton(digit)
            }
            keyButton("清零", role: .clear)
            keyButton("0")
            keyButton("⌫", role: .delete)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func keyButton(_ label: String, role: KeyRole = .digit) -> some View {
        Button {
            switch role {
            case .digit:
                if digits.count < 8 { digits += label }
            case .clear:
                digits = ""
            case .delete:
                if !digits.isEmpty { digits.removeLast() }
            }
        } label: {
            Text(label)
                .font(role == .digit ? .title2.weight(.medium) : .subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(role == .clear ? Color.red.opacity(0.8) : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 保存

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("保存")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    amountCents > 0 ? Color.brand : Color.gray.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .disabled(amountCents == 0)
    }

    private func save() {
        guard amountCents > 0, let account = selectedAccount ?? accounts.first else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? TransactionService(context: context).add(
            amountCents: amountCents,
            kind: kind,
            date: date,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            category: selectedCategory,
            account: account
        )
        savedFlash.toggle()
        digits = ""
        note = ""
        selectedTab = .transactions
    }
}
