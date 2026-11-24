import SwiftUI
import SwiftData

/// 四个页面用底部导航切换：今天 · 统计 · 目标 · 设置。
/// 记录页与编辑页仍然挂在根上全屏呈现，右滑即可关闭。
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTransactions: [Transaction]
    @Query private var allGoals: [Goal]
    @Query private var allBudgets: [Budget]
    @Query private var allConfirmations: [DayConfirmation]
    @AppStorage(PreferenceKey.onboardingHomeSeen) private var onboardingHomeSeen = false
    @AppStorage(PreferenceKey.onboardingBudgetSeen) private var onboardingBudgetSeen = false
    @AppStorage(PreferenceKey.privacyChoice) private var privacyChoice = ""
    @AppStorage(PreferenceKey.privacyVersionSeen) private var privacyVersionSeen = 0
    @State private var showPrivacyPolicy = false

    private enum Tab: Hashable {
        case today, review, goal, settings
    }

    /// 首页三步聚光灯
    private enum HomeOnboardingStep: Int, CaseIterable {
        case emotion, noSpend, record

        var target: OnboardingTarget {
            switch self {
            case .emotion: return .emotion
            case .noSpend: return .noSpend
            case .record: return .recordFab
            }
        }

        var step: OnboardingStep {
            switch self {
            case .emotion:
                return OnboardingStep(title: "顶部这句话",
                                      detail: "它会随着你的记录变化，不用自己写。",
                                      indexText: "1 / 3")
            case .noSpend:
                return OnboardingStep(title: "今天没花钱",
                                      detail: "真的没花钱，点一下确认，别让这天空着。",
                                      indexText: "2 / 3")
            case .record:
                return OnboardingStep(title: "记一笔",
                                      detail: "以后记一笔就从这里开始。",
                                      indexText: "3 / 3",
                                      circular: true)
            }
        }
    }

    private struct ActiveOnboardingStep {
        let target: OnboardingTarget
        let info: OnboardingStep
    }

    @State private var homeOnboardingStep = 0
    @State private var onboardingAnchors: [OnboardingTarget: Anchor<CGRect>] = [:]

    @State private var tab: Tab = .today
    /// 每个 tab 自己的一套二级页，切走隐藏、切回还在，互不覆盖
    private struct TabPages {
        var showRecord = false
        var recordDate = Date()
        var editing: Transaction?
        var categoryScope: CategoryScope?
        var showTrophies = false
    }

    /// 首页要聚焦的日期：启动/回前台为今天，记完一笔为那笔的日期
    @State private var focusedDay: Date?
    @State private var todayPages = TabPages()
    @State private var reviewPages = TabPages()
    @State private var goalPages = TabPages()
    /// 本次要庆祝的新奖杯
    @State private var celebration: [TrophySpec] = []
    /// 记录页还开着时先攒着，等它收起再庆祝
    @State private var pendingCelebration: [TrophySpec] = []
    /// 选择目标整页

    var body: some View {
        TabView(selection: $tab) {
            TodayView(onOpenRecord: openRecord(at:), onEdit: openEdit, focus: focusedDay)
                .background(AppBackground())
                .overlay { secondaryPages($todayPages) }
                .tabItem { Label { Text("记账").foregroundStyle(tab == .today ? Color.brand : Color.textSecondary) } icon: { brandIcon("SpongeMark", selected: tab == .today) } }
                .tag(Tab.today)

            ReviewView(onEdit: openEdit, onOpenCategory: openCategoryDetail)
                .background(AppBackground())
                .overlay { secondaryPages($reviewPages) }
                .tabItem { Label { Text("统计").foregroundStyle(tab == .review ? Color.brand : Color.textSecondary) } icon: { tabIcon("chart.bar.xaxis", selected: tab == .review) } }
                .tag(Tab.review)

            GoalView(onOpenTrophies: openTrophies)
                .background(AppBackground())
                .overlay { secondaryPages($goalPages) }
                .tabItem { Label { Text("目标").foregroundStyle(tab == .goal ? Color.brand : Color.textSecondary) } icon: { tabIcon("trophy", selected: tab == .goal) } }
                .tag(Tab.goal)

            SettingsView()
                .background(AppBackground())
                .tabItem { Label { Text("设置").foregroundStyle(tab == .settings ? Color.brand : Color.textSecondary) } icon: { tabIcon("gearshape", selected: tab == .settings) } }
                .tag(Tab.settings)
        }
        .tint(Color.brand)
        .onAppear { LaunchTrace.mark("root.appear") }
        .task {
            LaunchTrace.mark("task.start")
            refreshTrophies(celebrate: false)
            LaunchTrace.mark("trophies.done")
            CrashReporter.startIfAuthorized()
            UmengReporter.startIfAuthorized()
            LaunchTrace.mark("bugly.done")
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - LaunchTrace.start) * 1000)
            Analytics.record(.appLaunch, ["ms": Analytics.durationBand(milliseconds: elapsed)])
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .onChange(of: tab) { _, _ in
            resetSecondaryPages()
            refreshTrophies(celebrate: false)
        }
        .onPreferenceChange(OnboardingAnchorKey.self) { onboardingAnchors = $0 }
        // 四个 tab 页里只有目标抽屉有输入框，整体不避让键盘，抽屉就不会被压矮
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay {
            if !celebration.isEmpty {
                TrophyCelebrationView(trophies: celebration) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        celebration = []
                    }
                }
                .transition(.opacity)
                .zIndex(13)
            }
        }
        .overlay {
            GeometryReader { proxy in
                if let step = activeOnboardingStep,
                   let anchor = onboardingAnchors[step.target] {
                    OnboardingSpotlight(hole: proxy[anchor],
                                        step: step.info,
                                        onNext: advanceOnboarding,
                                        onSkip: skipOnboarding)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .zIndex(14)
        }
        .overlay {
            if needsPrivacyDecision {
                PrivacyConsentView(
                    onAccept: acceptPrivacy,
                    onOpenPolicy: { showPrivacyPolicy = true }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
    }

    private var isLedgerEmpty: Bool {
        allTransactions.isEmpty && allGoals.isEmpty && allBudgets.isEmpty && allConfirmations.isEmpty
    }

    /// 配了 Bugly 时，先让用户做隐私选择，再出引导
    private var needsPrivacyDecision: Bool {
        CrashReporter.isConfigured && privacyVersionSeen < PrivacyConsent.version
    }

    private var privacyReadyForOnboarding: Bool { !needsPrivacyDecision }

    private func acceptPrivacy() {
        privacyChoice = "granted"
        privacyVersionSeen = PrivacyConsent.version
        CrashReporter.startIfAuthorized()
        UmengReporter.startIfAuthorized()
    }

    /// 首页三步按顺序；走完后切到目标页看预算
    private var activeOnboardingStep: ActiveOnboardingStep? {
        if !onboardingHomeSeen, isLedgerEmpty, tab == .today, privacyReadyForOnboarding {
            let step = HomeOnboardingStep(rawValue: homeOnboardingStep) ?? .emotion
            return ActiveOnboardingStep(target: step.target, info: step.step)
        }

        if onboardingHomeSeen, !onboardingBudgetSeen, tab == .goal {
            return ActiveOnboardingStep(
                target: .budget,
                info: OnboardingStep(title: "本月预算",
                                     detail: "点这里设一个数，也可以顺手定一个目标。",
                                     indexText: "1 / 1")
            )
        }

        return nil
    }

    private func advanceOnboarding() {
        guard let step = activeOnboardingStep else { return }

        if step.target == .budget {
            Analytics.record(.onboarding, ["step": "budget", "action": "finish"])
            withAnimation(.easeOut(duration: 0.2)) {
                onboardingBudgetSeen = true
            }
            return
        }
        let stepIndex = String(homeOnboardingStep + 1)
        if homeOnboardingStep + 1 < HomeOnboardingStep.allCases.count {
            Analytics.record(.onboarding, ["step": stepIndex, "action": "next"])
            withAnimation(.easeInOut(duration: 0.18)) {
                homeOnboardingStep += 1
            }
        } else {
            Analytics.record(.onboarding, ["step": stepIndex, "action": "finish"])
            withAnimation(.easeOut(duration: 0.2)) {
                onboardingHomeSeen = true
            }
            homeOnboardingStep = 0
        }
    }

    private func skipOnboarding() {
        Analytics.record(.onboarding, ["step": String(homeOnboardingStep + 1), "action": "skip"])
        withAnimation(.easeOut(duration: 0.2)) {
            onboardingHomeSeen = true
            onboardingBudgetSeen = true
        }
        homeOnboardingStep = 0
    }

    /// 二级页：每个 tab 各自一套，互不覆盖；底部导航保留
    @ViewBuilder
    private func secondaryPages(_ pages: Binding<TabPages>) -> some View {
        ZStack {
            if let scope = pages.wrappedValue.categoryScope {
                CategoryRecordsView(scope: scope, onEdit: openEdit, onClose: { closeCategoryDetail(in: pages) })
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }

            if pages.wrappedValue.showTrophies {
                AchievementView(onClose: { closeTrophies(in: pages) })
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }

            if pages.wrappedValue.showRecord {
                RecordPage(initialDate: pages.wrappedValue.recordDate,
                           onClose: { closeRecord(in: pages) },
                           onSaved: { date in
                               focusedDay = date
                               refreshTrophies(celebrate: true)
                           })
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }

            if let transaction = pages.wrappedValue.editing {
                RecordPage(editing: transaction, onClose: { closeEdit(in: pages) }, onSaved: { _ in })
                    .geometryGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(3)
            }
        }
    }

    /// 底栏图标：先把符号画成位图再交给系统，系统就无法再把它染成黑色
    private func tabIcon(_ name: String, selected: Bool) -> Image {
        let tint = selected ? UIColor(Color.brand) : UIColor(Color.textSecondary)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        // 选中态优先用实心版本，和品牌标记的「充满」质感一致
        let filledName = name + ".fill"
        let resolved = selected && UIImage(systemName: filledName) != nil ? filledName : name
        guard let symbol = UIImage(systemName: resolved, withConfiguration: config) ?? UIImage(systemName: name, withConfiguration: config) else {
            return Image(systemName: name)
        }
        let size = CGSize(width: 26, height: 26)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            symbol.withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (size.width - symbol.size.width) / 2,
                                 y: (size.height - symbol.size.height) / 2,
                                 width: symbol.size.width, height: symbol.size.height))
        }
        return Image(uiImage: rendered.withRenderingMode(.alwaysOriginal))
    }

    /// 品牌标记（海绵）：把位图按当前状态染色后交给系统，避免被系统重新着色
    private func brandIcon(_ asset: String, selected: Bool) -> Image {
        guard let base = UIImage(named: asset) else { return Image(asset) }
        let tint = selected ? UIColor(Color.brand) : UIColor(Color.textSecondary)
        let side: CGFloat = 24
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = min(side / base.size.width, side / base.size.height)
            let width = base.size.width * scale
            let height = base.size.height * scale
            base.withTintColor(tint, renderingMode: .alwaysTemplate)
                .draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2,
                                 width: width, height: height))
        }
        return Image(uiImage: rendered.withRenderingMode(.alwaysOriginal))
    }

    private func pages(for target: Tab) -> Binding<TabPages> {
        switch target {
        case .today: return $todayPages
        case .review: return $reviewPages
        case .goal: return $goalPages
        case .settings: return .constant(TabPages())
        }
    }

    private var isRecordOpen: Bool { todayPages.showRecord || reviewPages.showRecord }

    /// 切 tab 一律回到根页：不保留任何二级页，也不排队庆祝
    private func resetSecondaryPages() {
        todayPages = TabPages()
        reviewPages = TabPages()
        goalPages = TabPages()
        pendingCelebration = []
    }

    private func openRecord(at date: Date) {
        todayPages.recordDate = date
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            todayPages.showRecord = true
        }
    }

    private func closeRecord(in pages: Binding<TabPages>) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            pages.wrappedValue.showRecord = false
        }
        guard !pendingCelebration.isEmpty else { return }
        let queued = pendingCelebration
        pendingCelebration = []
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                celebration = queued
            }
        }
    }

    /// 记下后检查奖杯：新拿到的等记录页收起再庆祝，避免压住还在输入的面板
    private func refreshTrophies(celebrate: Bool) {
        let newly = AchievementService(context: context).refreshUnlocks()
        guard celebrate, !newly.isEmpty else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(520))
            if isRecordOpen {
                pendingCelebration = newly
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    celebration = newly
                }
            }
        }
    }

    private func openTrophies() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            goalPages.showTrophies = true
        }
    }

    private func closeTrophies(in pages: Binding<TabPages>) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            pages.wrappedValue.showTrophies = false
        }
    }

    private func openCategoryDetail(_ scope: CategoryScope) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            reviewPages.categoryScope = scope
        }
    }

    private func closeCategoryDetail(in pages: Binding<TabPages>) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            pages.wrappedValue.categoryScope = nil
        }
    }

    private func openEdit(_ transaction: Transaction) {
        let target = pages(for: tab)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            target.wrappedValue.editing = transaction
        }
    }

    private func closeEdit(in pages: Binding<TabPages>) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            pages.wrappedValue.editing = nil
        }
    }
}

