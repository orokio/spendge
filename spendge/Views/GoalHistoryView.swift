import SwiftUI
import SwiftData

/// 已达成：只放已经固化的达成记录。
/// 目标被删除后记录仍在，所以这里能一直看到「我做到了多少」。
struct GoalHistoryView: View {
    let onClose: () -> Void

    @Query(sort: [SortDescriptor(\GoalAchievement.periodStart, order: .reverse)])
    private var achievements: [GoalAchievement]

    @State private var dragOffset: CGFloat = 0
    @State private var shareFile: SharedFile?
    @State private var toast: String?

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct Group: Identifiable {
        let id: UUID
        let title: String
        let achieved: Int
        let total: Int
    }

    private var groups: [Group] {
        Dictionary(grouping: achievements, by: \.goalID)
            .map { goalID, records in
                Group(
                    id: goalID,
                    title: records.last?.title ?? "",
                    achieved: records.filter(\.achieved).count,
                    total: records.count
                )
            }
            .sorted { $0.achieved == $1.achieved ? $0.title < $1.title : $0.achieved > $1.achieved }
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("我的奖杯")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Spacer()
                        if !groups.isEmpty {
                            Button {
                                share()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Color.brand)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 56)

                    if groups.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("还没有达成的记录")
                                .font(.headline)
                            Text("每个目标月底结算一次，达成后会记在这里。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: PageLayout.blockGap) {
                            ForEach(groups) { group in
                                card(group)
                            }
                        }
                    }
                }
                .padding(.horizontal, PageLayout.pageInset)
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
        .toast($toast)
        .sheet(item: $shareFile) { file in
            ShareSheet(url: file.url) { completed in
                shareFile = nil
                if completed {
                    Toast.show("已导出成就图片", into: $toast)
                }
            }
        }
    }

    private func card(_ group: Group) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("共 \(group.total) 期")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("累计 \(group.achieved) 次")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.brand)
                .fixedSize()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - 分享

    private func share() {
        let card = AchievementShareCard(rows: groups.map {
            AchievementShareCard.Row(title: $0.title, achieved: $0.achieved, total: $0.total)
        })
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage,
              let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("海绵记账-成就.png")
        try? data.write(to: url)
        shareFile = SharedFile(url: url)
    }
}

/// 分享用的成就卡（离屏渲染）
private struct AchievementShareCard: View {
    struct Row {
        let title: String
        let achieved: Int
        let total: Int
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("我达成的")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.brand)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.headline)
                    Spacer(minLength: 16)
                    Text("累计 \(row.achieved) 次")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.brand)
                }
            }

            Text("spendge")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 420, alignment: .leading)
        .background(Color.canvas)
    }
}
