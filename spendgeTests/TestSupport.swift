import Foundation
import SwiftData
import XCTest
@testable import spendge

/// 测试共用的内存库。
///
/// 整个测试进程只建一个容器：SwiftData 里同时存在两个指向同一组 Model 的
/// ModelContainer 会 trap，所以每个用例开始前用 reset() 把数据清干净，而不是各建各的。
@MainActor
enum TestStore {
    static let container = ModelContainerProvider.make(inMemory: true)

    static var context: ModelContext { container.mainContext }

    /// 清空所有表并重新写入种子数据（分类 + 默认账本）。
    static func reset() {
        let context = self.context
        deleteAll(GoalAchievement.self, in: context)
        deleteAll(TrophyUnlock.self, in: context)
        deleteAll(Goal.self, in: context)
        deleteAll(Transaction.self, in: context)
        deleteAll(DayConfirmation.self, in: context)
        deleteAll(Category.self, in: context)
        deleteAll(Ledger.self, in: context)
        try? context.save()
        DefaultData.seedIfNeeded(context: context)
        DefaultData.seedLedgerIfNeeded(context: context)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
            context.delete(item)
        }
    }

    // MARK: - 取种子数据

    static func category(_ code: CategoryCode) throws -> spendge.Category {
        let all = try CategoryService(context: context).categories()
        guard let match = all.first(where: { $0.categoryCode == code }) else {
            throw TestSetupError.missingCategory(code.rawValue)
        }
        return match
    }

    // MARK: - 造数据

    /// 本地时区的某天中午 12 点，避免跨时区/夏令时把日期挪到前后一天。
    static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components) ?? .now
    }
}

enum TestSetupError: Error {
    case missingCategory(String)
}
