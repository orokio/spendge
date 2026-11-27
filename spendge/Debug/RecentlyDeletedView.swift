#if DEBUG
import SwiftUI
import SwiftData

/// 开发者排查用：列出被软删除的账单，可以恢复。
/// 只在 DEBUG 编译，入口由开发者面板的开关控制。
struct RecentlyDeletedView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Transaction> { $0.deletedAt != nil },
           sort: \.deletedAt, order: .reverse)
    private var deletedTransactions: [Transaction]

    @State private var toast: String?

    var body: some View {
        SecondaryPage(onClose: onClose) {
            VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                header
                list
            }
        }
        .toast($toast)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近删除")
                .font(Typography.pageTitle)
                .foregroundStyle(Color.textPrimary)
            Text("共 \(deletedTransactions.count) 笔，30 天后自动清理")
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if deletedTransactions.isEmpty {
                Text("没有已删除的账单")
                    .font(Typography.label)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
            } else {
                ForEach(Array(deletedTransactions.enumerated()), id: \.element.id) { index, txn in
                    if index > 0 { divider }
                    row(txn)
                }
            }
        }
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.moduleRadius))
    }

    private func row(_ txn: Transaction) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CategoryCatalog.shared.category(code: txn.categoryCode)?.name ?? "未识别分类")
                    .font(Typography.body)
                    .foregroundStyle(Color.textPrimary)
                Text("\(AmountFormat.string(cents: txn.amountCents, showsSign: true, exact: true)) · 删除于 \(shortTime(txn.deletedAt))")
                    .font(Typography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 8)
            Button("恢复") {
                txn.deletedAt = nil
                txn.updatedAt = .now
                try? context.save()
                toast = "已恢复一笔"
            }
            .font(Typography.label)
            .foregroundStyle(Color.brand)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func shortTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
#endif
