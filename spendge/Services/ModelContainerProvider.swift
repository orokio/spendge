import Foundation
import SwiftData

enum ModelContainerProvider {
    /// 创建应用主容器；首次创建时会写入预置数据。
    static func make(inMemory: Bool = false) -> ModelContainer {
        #if DEBUG
        if !inMemory { removeStoreIfSchemaChanged() }
        #endif
        let schema = Schema([
            Account.self,
            Category.self,
            Transaction.self,
            Budget.self,
            DayConfirmation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            DefaultData.seedIfNeeded(context: context)
            return container
        } catch {
            // 数据层初始化失败属于致命错误
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// 预览 / 测试用内存容器（不落盘、无预置数据污染）。
    static var preview: ModelContainer { make(inMemory: true) }

    #if DEBUG
    /// 开发期：种子版本变化时直接删库文件，完全不走迁移。
    /// 在容器创建之前执行——迁移一旦失败会在创建阶段 trap，事后补救已经来不及。
    private static func removeStoreIfSchemaChanged() {
        let key = "spendge.seedVersion"
        let current = 7
        guard UserDefaults.standard.integer(forKey: key) != current else { return }

        let fileManager = FileManager.default
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? fileManager.removeItem(at: directory.appending(path: name))
        }
        UserDefaults.standard.set(current, forKey: key)
    }
    #endif
}
