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
                    .task {
                        #if DEBUG
                        SelfCheck.run(context: container.mainContext)
                        #endif
                    }
            }
        }
        .modelContainer(container)
    }
}
