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

/// 卡片容器：白底、圆角、内边距。页面里需要包一块内容时用它，不要各自写一套。
struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
            // 裁到卡片形状：删除色块伸到边缘时不会露出直角
            .clipShape(RoundedRectangle(cornerRadius: PageLayout.cardRadius))
    }
}

/// 账单卡片：容器 + 行列表。两个页面共用同一套样式。
struct TransactionCard: View {
    let transactions: [Transaction]
    var spacing: CGFloat = 14
    let onDelete: (Transaction) -> Void
    var onTap: ((Transaction) -> Void)?

    var body: some View {
        CardContainer {
            TransactionList(
                transactions: transactions,
                spacing: spacing,
                onDelete: onDelete,
                onTap: onTap,
                cardBleed: 18
            )
        }
    }
}

/// 带左滑删除的账单列表，两页共用。
struct TransactionList: View {
    let transactions: [Transaction]
    var spacing: CGFloat = 16
    let onDelete: (Transaction) -> Void
    var onTap: ((Transaction) -> Void)?
    /// 卡片内边距：首行与末行的删除红色块会多伸出一段，贴齐卡片边缘
    var cardBleed: CGFloat = 0

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, txn in
                let isFirst = index == 0
                let isLast = index == transactions.count - 1
                HoldToDeleteRow(
                    onDelete: { onDelete(txn) },
                    // 首行向上贴到卡片内边距，中间行各伸出半个行距让色块相接
                    topBleed: isFirst ? cardBleed : spacing / 2,
                    bottomBleed: isLast ? cardBleed : spacing / 2,
                    trailingBleed: cardBleed,
                    topRightRadius: isFirst ? PageLayout.cardRadius : 0,
                    bottomRightRadius: isLast ? PageLayout.cardRadius : 0
                ) {
                    TransactionRow(transaction: txn)
                        .onTapGesture { onTap?(txn) }
                }
            }
        }
    }
}
