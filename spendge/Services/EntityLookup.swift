import Foundation
import SwiftData

/// 分类 / 账户不参与 iCloud 同步，账单与预算只存 code。
/// 展示时按 code 在本机解析成对象；按 ModelContext 缓存整张表，避免列表里每行查一次库。
@MainActor
enum EntityLookup {
    private static var categoryMaps: [ObjectIdentifier: [String: Category]] = [:]
    private static var accountMaps: [ObjectIdentifier: [String: Account]] = [:]

    static func category(code: String?, in context: ModelContext?) -> Category? {
        guard let code, let context else { return nil }
        if let map = categoryMaps[ObjectIdentifier(context)] { return map[code] }
        let all = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var map: [String: Category] = [:]
        for category in all {
            if let key = category.code, map[key] == nil { map[key] = category }
        }
        categoryMaps[ObjectIdentifier(context)] = map
        return map[code]
    }

    static func account(code: String?, in context: ModelContext?) -> Account? {
        guard let code, let context else { return nil }
        if let map = accountMaps[ObjectIdentifier(context)] { return map[code] }
        let all = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var map: [String: Account] = [:]
        for account in all where !account.code.isEmpty {
            if map[account.code] == nil { map[account.code] = account }
        }
        accountMaps[ObjectIdentifier(context)] = map
        return map[code]
    }

    /// 新增 / 删除分类或账户、或批量导入后调用，下次访问重新建表。
    static func invalidate(_ context: ModelContext) {
        categoryMaps[ObjectIdentifier(context)] = nil
        accountMaps[ObjectIdentifier(context)] = nil
    }

    static func invalidateAll() {
        categoryMaps.removeAll()
        accountMaps.removeAll()
    }
}
