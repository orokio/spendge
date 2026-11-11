import Foundation
import SwiftData

enum ModelContainerProvider {
    /// 创建应用主容器；首次创建时会写入预置数据。
    ///
    /// 迁移策略：**先尝试就地迁移，失败才清库**。
    /// 之前按版本号无条件删除 store，会导致覆盖安装时用户数据丢失。
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Account.self,
            Category.self,
            Transaction.self,
            Budget.self,
            DayConfirmation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            let context = ModelContext(container)
            DefaultData.seedIfNeeded(context: context)
            return container
        }

        #if DEBUG
        if !inMemory {
            // 迁移失败：结构不兼容，清库重来（开发期兜底）
            removeStoreFiles()
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                let context = ModelContext(container)
                DefaultData.seedIfNeeded(context: context)
                return container
            }
        }
        #endif

        fatalError("Failed to create ModelContainer")
    }

    /// 预览 / 测试用内存容器（不落盘、无预置数据污染）。
    static var preview: ModelContainer { make(inMemory: true) }

    #if DEBUG
    private static func removeStoreFiles() {
        let fileManager = FileManager.default
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? fileManager.removeItem(at: directory.appending(path: name))
        }
    }
    #endif
}
