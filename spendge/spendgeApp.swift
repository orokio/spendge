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
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                LinearGradient(
                    stops: [
                        .init(color: Color.brand.opacity(0.20), location: 0),
                        .init(color: Color.brand.opacity(0.15), location: 0.10),
                        .init(color: Color.brand.opacity(0.09), location: 0.24),
                        .init(color: Color.brand.opacity(0.04), location: 0.40),
                        .init(color: Color.brand.opacity(0.012), location: 0.58),
                        .init(color: Color.brand.opacity(0), location: 0.74),
                    ],
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
