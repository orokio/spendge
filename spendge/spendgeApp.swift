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
            RootView()
                .task {
                    #if DEBUG
                    SelfCheck.run(context: container.mainContext)
                    #endif
                }
        }
        .modelContainer(container)
    }
}
