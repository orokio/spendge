import SwiftData
import SwiftUI

/// 账单行：首页和回看页共用，保证两处的排版与间距一致。
struct TransactionRow: View {
    let transaction: Transaction
    var showsCategoryIcon: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            if showsCategoryIcon {
                CategoryIcon(
                    iconName: transaction.category?.iconName ?? "tag",
                    colorHex: transaction.category?.colorHex ?? "#9CA3AF",
                    size: 32
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.category?.name ?? "未分类")
                    .font(Typography.rowTitle)
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(AmountFormat.string(cents: signedCents, showsSign: true))
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(transaction.kind == .income ? Color.income : .primary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var signedCents: Int64 {
        transaction.kind == .expense ? -transaction.amountCents : transaction.amountCents
    }
}

/// 带左滑删除的账单列表，两页共用。
struct TransactionList: View {
    let transactions: [Transaction]
    var spacing: CGFloat = 16
    let onDelete: (Transaction) -> Void
    var onTap: ((Transaction) -> Void)?

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(transactions) { txn in
                HoldToDeleteRow {
                    onDelete(txn)
                } content: {
                    TransactionRow(transaction: txn)
                        .onTapGesture { onTap?(txn) }
                }
            }
        }
    }
}
