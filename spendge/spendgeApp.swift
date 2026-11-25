//
//  spendgeApp.swift
//  spendge
//
//  Created by leon on 2026/8/5.
//

import SwiftUI
import SwiftData

@main
struct spendgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container: ModelContainer
    @State private var importRefreshWork: DispatchWorkItem?

    init() {
        LaunchTrace.mark("app.init")
        _container = State(initialValue: ModelContainerProvider.make())
        LaunchTrace.mark("container.ready")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.canvas
                    .ignoresSafeArea()

                // 顶部渐变的颜色与位置都来自主题 token
                LinearGradient(
                    stops: Palette.current.gradientStops.map {
                        Gradient.Stop(color: $0.color, location: $0.location)
                    },
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                RootView()
                    // 全站正文用近黑（#1F2937），不用系统纯黑
                    .foregroundStyle(Color.textPrimary)
                    .task {
                        // 上月勾了「循环应用」时，给本月补一条预算 / 目标（Release 也要跑）
                        try? GoalService(context: container.mainContext).carryForwardIfNeeded()

                        // 启动时把已经走完的周期固化成达成记录（幂等）
                        try? GoalService(context: container.mainContext).materializeAchievements()

                        // 同步事件在 App 存活期间就要收，设置页不可见也要更新「上次同步」
                        CloudSyncMonitor.shared.start()
                        StoreService.shared.start()
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudDataImported)) { _ in
                // 导入事件会连续来几条，合并成一次刷新
                importRefreshWork?.cancel()
                let work = DispatchWorkItem {
                    EntityLookup.invalidateAll()
                    let context = container.mainContext
                    _ = try? context.fetch(FetchDescriptor<Transaction>())
                    _ = try? context.fetch(FetchDescriptor<Goal>())
                    _ = try? context.fetch(FetchDescriptor<GoalAchievement>())
                    _ = try? context.fetch(FetchDescriptor<DayConfirmation>())
                    _ = try? context.fetch(FetchDescriptor<TrophyUnlock>())
                    _ = try? context.fetch(FetchDescriptor<Category>())
                    DefaultData.dedupeRecords(context: context)
                    LaunchTrace.mark("cloud.import.refreshed")
                }
                importRefreshWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPreferenceChanged)) { _ in
                // 同一份 store 换成另一种 CloudKit 配置；异步重建，避免在视图更新中换容器
                DispatchQueue.main.async {
                    container = ModelContainerProvider.make()
                    LaunchTrace.mark("container.rebuilt")
                }
            }
        }
        .modelContainer(container)
    }
}
