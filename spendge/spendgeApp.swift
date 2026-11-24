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
    private let container: ModelContainer

    init() {
        LaunchTrace.mark("app.init")
        container = ModelContainerProvider.make()
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
                        try? BudgetService(context: container.mainContext).carryForwardIfNeeded()
                        try? GoalService(context: container.mainContext).carryForwardIfNeeded()

                        // 启动时把已经走完的周期固化成达成记录（幂等）
                        try? GoalService(context: container.mainContext).materializeAchievements()
                    }
            }
        }
        .modelContainer(container)
    }
}
