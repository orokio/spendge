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
    private let container = ModelContainerProvider.make()
    /// 首帧淡入：不做延迟，只把静态启动屏上的 logo 交叉溶进界面
    @State private var launched = false

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
                    .opacity(launched ? 1 : 0)
                    .task {
                        #if DEBUG
                        // 只在显式带参数时跑：simctl launch <device> com.orokio.spendge -selfcheck
                        if ProcessInfo.processInfo.arguments.contains("-selfcheck") {
                            SelfCheck.run(context: container.mainContext)
                        }
                        // 上月勾了「循环应用」时，给本月补一条预算
                        try? BudgetService(context: container.mainContext).carryForwardIfNeeded()

                        // 启动时把已经走完的周期固化成达成记录（幂等）
                        try? GoalService(context: container.mainContext).materializeAchievements()

                        #endif
                    }

                // 与启动屏同一位置、同一尺寸，接着淡出——看起来是 logo 融进界面
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 230)
                    .opacity(launched ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.4)) {
                    launched = true
                }
            }
        }
        .modelContainer(container)
    }
}
