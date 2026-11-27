import Foundation
import SwiftData

enum ModelContainerProvider {
    /// 创建应用主容器；首次创建时会写入预置数据。
    ///
    /// 迁移失败不再自动清库：现在库里有用户的真实数据，宁可启动失败也不能静默删掉。
    /// - Parameter cloudKitEnabled: 覆盖同步开关；只用于「重新同步」时临时建一个不带 CloudKit 的容器
    static func make(inMemory: Bool = false, cloudKitEnabled: Bool? = nil) -> ModelContainer {
        let schema = Schema([
            Ledger.self,
            Transaction.self,
            DayConfirmation.self,
            Goal.self,
            GoalAchievement.self,
            TrophyUnlock.self,
        ])
        // 模拟器没有 iCloud entitlement，开了会直接建库失败；真机才按设置启用 CloudKit。
        #if targetEnvironment(simulator)
        let cloudKit: ModelConfiguration.CloudKitDatabase = .none
        #else
        let syncAllowed = cloudKitEnabled ?? CloudSyncPreference.isEnabled
        let cloudKit: ModelConfiguration.CloudKitDatabase = syncAllowed ? .automatic : .none
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : cloudKit
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            DefaultData.seedLedgerIfNeeded(context: context)
            DefaultData.migrateLegacyCategoryCodes(context: context)
            DefaultData.dedupeRecords(context: context)
            DefaultData.purgeExpiredDeletions(context: context)
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// 预览 / 测试用内存容器（不落盘、无预置数据污染）。
    static var preview: ModelContainer { make(inMemory: true) }
}
