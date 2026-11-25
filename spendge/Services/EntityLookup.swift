import Foundation
import SwiftData

/// 账单与预算只存 code，展示时按 code 在本机解析分类。
/// 展示时按 code 在本机解析成对象；按 ModelContext 缓存整张表，避免列表里每行查一次库。
@MainActor
enum EntityLookup {
    private static var categoryMaps: [ObjectIdentifier: [String: Category]] = [:]

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

    /// 新增 / 删除分类、或批量导入后调用，下次访问重新建表。
    static func invalidate(_ context: ModelContext) {
        categoryMaps[ObjectIdentifier(context)] = nil
    }

    static func invalidateAll() {
        categoryMaps.removeAll()
    }
}
