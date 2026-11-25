import Foundation
import SwiftData

enum ModelContainerProvider {
    /// 创建应用主容器；首次创建时会写入预置数据。
    ///
    /// 迁移失败不再自动清库：现在库里有用户的真实数据，宁可启动失败也不能静默删掉。
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Category.self,
            Ledger.self,
            Transaction.self,
            Budget.self,
            DayConfirmation.self,
            Goal.self,
            GoalAchievement.self,
            TrophyUnlock.self,
        ])
        // 模拟器没有 iCloud entitlement，开了会直接建库失败；真机才按设置启用 CloudKit。
        #if targetEnvironment(simulator)
        let cloudKit: ModelConfiguration.CloudKitDatabase = .none
        #else
        let syncAllowed = CloudSyncPreference.isEnabled && Entitlements.can(.iCloudSync)
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
            DefaultData.migrateCategoriesIfNeeded(context: context)
            DefaultData.seedIfNeeded(context: context)
            DefaultData.seedLedgerIfNeeded(context: context)
            DefaultData.backfillLedgerID(context: context)
            DefaultData.backfillGoalMonths(context: context)
            DefaultData.backfillCodes(context: context)
            DefaultData.normalizeEntityIdentity(context: context)
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
