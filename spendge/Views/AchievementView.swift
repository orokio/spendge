import SwiftUI
import SwiftData
import UIKit
import AudioToolbox

/// 奖杯墙：顶部收集进度 + 离解锁最近的一枚 + 按系列排的三列网格。
///
/// 三种状态靠形状与饱和度一起区分：实心 = 已解锁，半环 = 进行中，虚线空壳 = 还没影。
struct AchievementView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var unlocks: [TrophyUnlock]

    @State private var snapshot: AchievementSnapshot?
    @State private var selected: TrophyState?
    /// 关闭详情后的短暂冷却：避免同一触摸落到卡片上再次弹出
    @State private var suppressTaps = false
    @State private var shareFile: SharedFile?
    @State private var toast: String?
    @State private var shareError: String?

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var calendar: Calendar { .current }

    var body: some View {
        SecondaryPage(onClose: onClose, swipeBackEnabled: selected == nil && !suppressTaps) {
            VStack(alignment: .leading, spacing: PageLayout.stackedCardGap) {
                header
                progressCard
                if let nearest { heroCard(nearest) }
                VStack(alignment: .leading, spacing: PageLayout.stackedCardGap) {
                    ForEach(TrophySeries.allCases, id: \.self) { series in
                        if let section = section(for: series) {
                            sectionView(section)
                        }
                    }
                }
            }
            .allowsHitTesting(selected == nil && !suppressTaps)
        }
        .task { reload() }
        .onChange(of: unlocks.count) { _, _ in reload() }
        .overlay { detailOverlay }
        .sheet(item: $shareFile) { file in
            ShareSheet(url: file.url) { completed in
                shareFile = nil
                if completed { Toast.show("已分享奖杯", into: $toast) }
            }
        }
        .toast($toast)
        .errorToast($shareError)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("奖杯")
                .font(Typography.pageTitle)
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 12)

            if let snapshot {
                HStack(spacing: 6) {
                    Text("累计记录 \(snapshot.recordDays) 天")
                    Text("·")
                    Text("最长连续 \(snapshot.longestDayStreak) 天")
                }
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize()
            }
        }
    }

    private var progressCard: some View {
        let total = TrophyCatalog.all.count
        let unlocked = snapshot?.unlockedCount ?? 0
        return VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("已解锁")
                    .font(Typography.bodyStrong)
                    .foregroundStyle(Color.textPrimary)
                Text("\(unlocked)")
                    .font(Typography.numberLarge)
                    .foregroundStyle(Color.brand)
                Text("/ \(total)")
                    .font(Typography.label)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }

            HStack(spacing: 18) {
                ForEach(TrophyRarity.allCases, id: \.self) { rarity in
                    rarityStat(rarity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, PageLayout.cardTitleGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
    }

    private func rarityStat(_ rarity: TrophyRarity) -> some View {
        let items = TrophyCatalog.all.filter { $0.rarity == rarity }
        let got = items.filter { snapshot?.states[$0.id]?.isUnlocked == true }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(rarity.title)
                    .font(Typography.label)
                    .foregroundStyle(Color.textSecondary)
                Text("\(got)/\(items.count)")
                    .font(Typography.numberSmall)
                    .foregroundStyle(Color.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(rarity.tint)
                        .frame(width: proxy.size.width * Double(got) / Double(max(items.count, 1)))
                }
            }
            .frame(height: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 离解锁最近

    private var nearest: TrophyState? {
        guard let snapshot else { return nil }
        return snapshot.states.values
            .filter { !$0.isUnlocked && $0.progress.current > 0 }
            .sorted {
                if $0.progress.fraction == $1.progress.fraction {
                    return $0.progress.target - $0.progress.current < $1.progress.target - $1.progress.current
                }
                return $0.progress.fraction > $1.progress.fraction
            }
            .first
    }

    private func heroCard(_ state: TrophyState) -> some View {
        HStack(alignment: .center, spacing: 14) {
                TrophyBadge(spec: state.spec,
                            progress: state.progress,
                            unlocked: false,
                            size: 54)

                Text(state.spec.name)
                    .font(Typography.bodyStrong)
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("离你最近")
                        .font(Typography.caption)
                    Text("·")
                        .font(Typography.caption)
                    Text(state.progress.remainingText)
                        .font(Typography.label)
                }
                .foregroundStyle(Color.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
    }

    // MARK: - 网格

    private struct SectionModel {
        let series: TrophySeries
        let states: [TrophyState]
        let unlockedCount: Int
        /// 该系列下一个未解锁的达成条件，用来给方向，不暴露名字
        let nextCondition: String?
    }

    private var orderedStates: [TrophyState] {
        guard let snapshot else { return [] }
        return TrophyCatalog.all.compactMap { snapshot.states[$0.id] }
    }

    private func section(for series: TrophySeries) -> SectionModel? {
        guard let snapshot else { return nil }
        let states = TrophyCatalog.all
            .filter { $0.series == series }
            .compactMap { snapshot.states[$0.id] }
        guard !states.isEmpty else { return nil }
        return SectionModel(
            series: series,
            states: states,
            unlockedCount: states.filter(\.isUnlocked).count,
            nextCondition: states.first { !$0.isUnlocked }?.spec.condition
        )
    }

    private func sectionView(_ section: SectionModel) -> some View {
        return VStack(alignment: .leading, spacing: PageLayout.cardTitleGap) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.series.title)
                    .font(Typography.bodyStrong)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 12)

                if let condition = section.nextCondition {
                    Text("下一档 · " + condition)
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("已集齐")
                        .font(Typography.caption)
                        .foregroundStyle(Color.brand)
                }
            }

            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(section.states) { state in
                    if state.isUnlocked {
                        Button {
                            openDetail(state)
                        } label: {
                            TrophyCell(state: state)
                        }
                        .buttonStyle(.plain)
                    } else {
                        TrophyCell(state: state)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, PageLayout.cardTitleGap)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PageLayout.cardRadius))
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)
    }

    // MARK: - 数据

    private func reload() {
        snapshot = AchievementService(context: context).snapshot()
        // 打开页面时顺带补写一次解锁：目标、预算这类变化不一定走记账保存
        AchievementService(context: context).refreshUnlocks()
    }

    // MARK: - 详情浮层

    private var detailOverlay: some View {
        ZStack(alignment: .bottom) {
            if let selected {
                Color.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { closeDetail() }

                TrophyDetailSheet(state: selected) {
                    share(selected)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 28,
                                           topTrailingRadius: 28,
                                           style: .continuous)
                        .fill(Color.surfaceElevated)
                        .shadow(color: .black.opacity(0.12), radius: 18, y: -4)
                        .ignoresSafeArea(edges: .bottom)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            if value.translation.height > 100 { closeDetail() }
                        }
                )
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: selected?.id)
    }

    private func openDetail(_ state: TrophyState) {
        guard !suppressTaps else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            selected = state
        }
    }

    private func closeDetail() {
        suppressTaps = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            selected = nil
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            suppressTaps = false
        }
    }

    private func share(_ state: TrophyState) {
        do {
            try FaultInjection.current.check(.shareExport)
        } catch {
            shareError = ErrorText.message(for: error)
            return
        }
        guard let unlockedAt = state.unlockedAt else { return }
        let card = TrophyShareCard(spec: state.spec, unlockedAt: unlockedAt)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            shareError = "没有生成分享图片，请再试一次。"
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("海绵记账-奖杯.png")
        do {
            try data.write(to: url)
        } catch {
            shareError = ErrorText.message(for: error)
            return
        }

        closeDetail()
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            shareFile = SharedFile(url: url)
        }
    }
}

// MARK: - 单元格

private struct TrophyCell: View {
    let state: TrophyState

    var body: some View {
        VStack(spacing: 8) {
            TrophyBadge(spec: state.spec,
                        progress: state.progress,
                        unlocked: state.isUnlocked,
                        size: 62)
                .overlay(alignment: .bottomTrailing) {
                    if state.isUnlocked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.onAccent)
                            .frame(width: 16, height: 16)
                            .background(Color.brand, in: Circle())
                            .overlay(Circle().stroke(Color.surfaceElevated, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }

            if state.isUnlocked || state.isInProgress {
                Text(state.spec.name)
                    .font(Typography.captionStrong)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if state.isUnlocked, let date = state.unlockedAt {
                Text(Self.dateText(date))
                    .font(Typography.axisLabel)
                    .foregroundStyle(Color.textSecondary)
            } else if state.isInProgress {
                Text(state.progress.remainingText)
                    .font(Typography.axisLabel)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private static func dateText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
        }
        return date.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN")))
    }
}

// MARK: - 徽章

struct TrophyBadge: View {
    let spec: TrophySpec
    let progress: TrophyProgress
    let unlocked: Bool
    var size: CGFloat = 62

    private var isInProgress: Bool { !unlocked && progress.current > 0 }
    private var shape: TrophyShellShape { TrophyShellShape(shell: spec.rarity.shell) }

    // 描边随尺寸放大：62pt 时与之前一致，136pt 时不会显得细
    private var trackWidth: CGFloat { min(size * 0.048, 4.5) }
    private var progressWidth: CGFloat { min(size * 0.064, 6) }
    private var lockedWidth: CGFloat { min(size * 0.038, 3.5) }
    private var unlockedBorderWidth: CGFloat { min(size * 0.022, 3) }

    var body: some View {
        ZStack {
            if unlocked {
                shape
                    .fill(
                        LinearGradient(
                            colors: [spec.rarity.tint, spec.rarity.tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        shape.stroke(Color.onAccent.opacity(0.35), lineWidth: unlockedBorderWidth)
                    }
            } else if isInProgress {
                shape.fill(spec.rarity.tint.opacity(0.08))
                shape.stroke(Color.secondary.opacity(0.18), lineWidth: trackWidth)
                shape
                    .trim(from: 0, to: progress.fraction)
                    .stroke(spec.rarity.tint,
                            style: StrokeStyle(lineWidth: progressWidth, lineCap: .round))
                    .rotationEffect(.degrees(spec.rarity.shell == .circle ? -90 : 0))
            } else {
                shape.fill(Color.textSecondary.opacity(0.05))
                shape.stroke(Color.textSecondary.opacity(0.28),
                             style: StrokeStyle(lineWidth: lockedWidth, dash: [5, 4]))
            }

            symbol
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var symbol: some View {
        if unlocked {
            Image(systemName: resolvedSymbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(Color.onAccent)
        } else if isInProgress {
            Image(systemName: resolvedSymbol)
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(spec.rarity.tint.opacity(0.75))
        } else {
            Image(systemName: "questionmark")
                .font(.system(size: size * 0.30, weight: .semibold))
                .foregroundStyle(Color.textSecondary.opacity(0.35))
        }
    }

    private var resolvedSymbol: String {
        UIImage(systemName: spec.symbol) == nil ? "star.fill" : spec.symbol
    }
}

// MARK: - 详情

private struct TrophyDetailSheet: View {
    let state: TrophyState
    let onShare: () -> Void

    /// 达成条件与解锁日期合成一行，用逗号分隔
    private var detailText: String {
        guard let date = state.unlockedAt else { return state.spec.condition }
        let dateText = date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
        return state.spec.condition + "，" + dateText
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 2)

            Spacer(minLength: 0)

            VStack(spacing: 16) {
                TrophyBadge(spec: state.spec,
                            progress: state.progress,
                            unlocked: state.isUnlocked,
                            size: 120)

                HStack(alignment: .center, spacing: 8) {
                    Text(state.spec.rarity.title)
                        .font(Typography.label.weight(.medium))
                        .foregroundStyle(state.spec.rarity.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(state.spec.rarity.tint.opacity(0.12), in: Capsule())

                    Text(state.spec.name)
                        .font(Typography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                }

                Text(detailText)
                    .font(Typography.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            Button(action: onShare) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享这枚奖杯")
                }
                .font(Typography.bodyStrong)
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

// MARK: - 分享卡

private struct TrophyShareCard: View {
    let spec: TrophySpec
    let unlockedAt: Date

    var body: some View {
        VStack(spacing: 18) {
            TrophyBadge(spec: spec,
                        progress: TrophyProgress(current: 1, target: 1, unit: .times),
                        unlocked: true,
                        size: 132)

            VStack(spacing: 6) {
                Text("我解锁了")
                    .font(Typography.label)
                    .foregroundStyle(Color.textSecondary)
                Text(spec.name)
                    .font(Typography.numberLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(spec.condition + "，" + unlockedAt.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                    .font(Typography.label)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text("Spendge")
                .font(Typography.label.weight(.semibold))
                .foregroundStyle(Color.brand)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 28)
        .frame(width: 420)
        .background(Color.canvas)
    }
}

// MARK: - 解锁庆祝

struct TrophyCelebrationView: View {
    let trophies: [TrophySpec]
    let onFinish: () -> Void

    @State private var index = 0
    @State private var revealed = false

    private var current: TrophySpec { trophies[min(index, trophies.count - 1)] }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { advance() }

            VStack(spacing: 16) {
                TrophyBadge(spec: current,
                            progress: TrophyProgress(current: 1, target: 1, unit: .times),
                            unlocked: true,
                            size: 132)
                    .rotation3DEffect(.degrees(revealed ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .scaleEffect(revealed ? 1 : 0.72)
                    .shadow(color: current.rarity.tint.opacity(revealed ? 0.35 : 0), radius: 24, y: 8)

                VStack(spacing: 6) {
                    Text("解锁新奖杯")
                        .font(Typography.caption)
                        .foregroundStyle(Color.onAccent.opacity(0.7))
                    Text(current.name)
                        .font(Typography.hero)
                        .foregroundStyle(Color.onAccent)
                    Text(current.condition)
                        .font(Typography.label)
                        .foregroundStyle(Color.onAccent.opacity(0.85))
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 8)

                Button {
                    advance()
                } label: {
                    Text(trophies.count > 1 && index < trophies.count - 1 ? "下一枚" : "收下")
                        .font(Typography.bodyStrong)
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 28)
                        .frame(height: 44)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .opacity(revealed ? 1 : 0)
                .padding(.top, 8)
            }
            .padding(.horizontal, 32)
        }
        .onAppear { reveal() }
    }

    private func reveal() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(1104)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
            revealed = true
        }
    }

    private func advance() {
        if index + 1 < trophies.count {
            index += 1
            revealed = false
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                reveal()
            }
        } else {
            onFinish()
        }
    }
}
