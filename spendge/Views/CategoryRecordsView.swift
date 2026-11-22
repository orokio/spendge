import SwiftUI
import SwiftData

/// 从统计页的二级分类下钻时带过来的范围：分类 + 当前期间。
struct CategoryScope {
    let category: Category
    /// 期间标题，如「2026年11月」
    let title: String
    let start: Date
    let end: Date
}

/// 分类明细：只列当前期间、这个分类下的流水。
/// 行样式与首页流水一致，支持点击编辑、右半边长按删除；删掉最后一笔自动退回。
struct CategoryRecordsView: View {
    let scope: CategoryScope
    let onEdit: (Transaction) -> Void
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var dragOffset: CGFloat = 0

    private var calendar: Calendar { .current }

    private var records: [Transaction] {
        allTransactions.filter {
            $0.category?.id == scope.category.id
                && $0.date >= scope.start
                && $0.date < scope.end
        }
    }

    private var groups: [(day: Date, items: [Transaction])] {
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        return grouped.keys
            .sorted(by: >)
            .map { day in (day, (grouped[day] ?? []).sorted { $0.date < $1.date }) }
    }

    private var totalCents: Int64 {
        records.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    BackButton(action: onClose)

                    header

                    if groups.isEmpty {
                        Text("这个分类在这段时间没有记录了")
                            .font(Typography.body)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(groups, id: \.day) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 10) {
                                        Text(dayTitle(group.day))
                                            .font(Typography.label)
                                            .foregroundStyle(Color.textSecondary)

                                        CategoryDashedLine()
                                            .stroke(Color.textSecondary.opacity(0.22),
                                                    style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                            .frame(height: 1)
                                    }

                                    TransactionCard(
                                        transactions: group.items,
                                        onDelete: { txn in
                                            try? TransactionService(context: context).delete(txn)
                                        },
                                        onTap: onEdit
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, PageLayout.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .offset(x: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard value.translation.width > 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if value.translation.width > 120 {
                        onClose()
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onChange(of: records.count) { oldValue, newValue in
            // 删掉或改走最后一笔时，页面自动退回
            if oldValue > 0, newValue == 0 { onClose() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(scope.category.name)
                .font(Typography.pageTitle)
                .foregroundStyle(Color.textPrimary)

            Text("\(scope.title) · \(records.count) 笔 · \(AmountFormat.string(cents: totalCents))")
                .font(Typography.label)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 2)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let month = calendar.component(.month, from: day)
        let number = calendar.component(.day, from: day)
        let weekday = day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
        return "\(month)月\(number)日 \(weekday)"
    }
}

/// 日期之间的虚分割线
private struct CategoryDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}
