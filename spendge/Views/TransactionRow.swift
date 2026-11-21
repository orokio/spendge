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

            // 固定高度：没有备注时分类名垂直居中，行高与有备注时一致
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.category?.name ?? "未分类")
                    .font(Typography.bodyMedium)
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: 40)

            Spacer(minLength: 8)

            // 明细保留角分，不被汇总用的取整规则抹掉
            Text(AmountFormat.string(cents: signedCents, showsSign: true, exact: true))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(transaction.kind == .income ? Color.income : Color.textPrimary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var signedCents: Int64 {
        transaction.kind == .expense ? -transaction.amountCents : transaction.amountCents
    }
}

/// 卡片容器：白底、圆角、内边距。页面里需要包一块内容时用它，不要各自写一套。
struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
            .clipShape(RoundedRectangle(cornerRadius: PageLayout.cardRadius))
    }
}

/// 账单列表：每行是一张独立的小卡片，行间留空隙。
struct TransactionList: View {
    let transactions: [Transaction]
    var spacing: CGFloat = 10
    let onDelete: (Transaction) -> Void
    var onTap: ((Transaction) -> Void)?

    private let rowRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(transactions) { txn in
                HoldToDeleteRow(
                    onDelete: { onDelete(txn) },
                    cornerRadius: rowRadius
                ) {
                    TransactionRow(transaction: txn)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
                        .onTapGesture { onTap?(txn) }
                }
            }
        }
    }
}

/// 账单卡片：行列表本身已经是一张张卡片，这里只保留同名入口。
struct TransactionCard: View {
    let transactions: [Transaction]
    var spacing: CGFloat = 10
    let onDelete: (Transaction) -> Void
    var onTap: ((Transaction) -> Void)?

    var body: some View {
        TransactionList(
            transactions: transactions,
            spacing: spacing,
            onDelete: onDelete,
            onTap: onTap
        )
    }
}
