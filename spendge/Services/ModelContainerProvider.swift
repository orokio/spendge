import Foundation
import SwiftData

enum ModelContainerProvider {
    /// 创建应用主容器；首次创建时会写入预置数据。
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Account.self,
            Category.self,
            Transaction.self,
            Budget.self,
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
}
