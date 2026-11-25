import Combine
import Foundation

/// 分类是服务端下发的参考数据，不属于用户数据，不建表、不参与 CloudKit。
struct CategoryInfo: Codable, Identifiable, Equatable {
    let code: String
    var name: String
    var iconName: String
    var colorHex: String
    var kindRawValue: String
    var domainRawValue: String
    var scope: String
    var sortOrder: Int
    var isArchived: Bool
    /// 可用于哪些目标类型（值域是 GoalKind.rawValue）；空表示不能设目标
    var goalKinds: [String]? = nil

    var id: String { code }

    /// 目标表单按这个判断可选分类；服务端还没下发 goalKinds 时退回内置默认表
    func allowsGoal(_ kind: GoalKind) -> Bool {
        if let goalKinds { return goalKinds.contains(kind.rawValue) }
        guard let code = CategoryCode(rawValue: code) else { return false }
        return DefaultData.categoryGoalKinds[code]?.contains(kind) == true
    }

    var kind: TransactionKind { TransactionKind(rawValue: kindRawValue) ?? .expense }
    var domain: CategoryDomain { CategoryDomain(rawValue: domainRawValue) ?? .other }
    var categoryCode: CategoryCode? { CategoryCode(rawValue: code) }
    var displayName: String { name }
}

/// 分类目录：默认配置来自代码，可被服务端下发覆盖，缓存到本地文件。
@MainActor
final class CategoryCatalog: ObservableObject {
    static let shared = CategoryCatalog()

    @Published private(set) var version: Int
    @Published private(set) var categories: [CategoryInfo]

    /// 本地缓存结构版本：字段语义变了就 +1，旧缓存直接丢弃重拉，避免残留合并结果
    private static let cacheSchema = 2

    private struct Cache: Codable {
        var schema: Int?
        var version: Int
        var categories: [CategoryInfo]
    }

    private let cacheURL: URL?

    private init() {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("category-catalog.json")
        cacheURL = url

        if let url,
           let data = try? Data(contentsOf: url),
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           cache.schema == Self.cacheSchema,
           !cache.categories.isEmpty {
            version = cache.version
            categories = cache.categories
        } else {
            version = 0
            categories = Self.defaults
        }
    }

    /// 内置默认配置：与服务端首次下发前的内容一致
    static var defaults: [CategoryInfo] {
        let seeds = DefaultData.expenseCategorySeeds + DefaultData.incomeCategorySeeds
        return seeds.map { seed in
            CategoryInfo(code: seed.code.rawValue,
                         name: seed.name,
                         iconName: seed.iconName,
                         colorHex: seed.colorHex,
                         kindRawValue: seed.kind.rawValue,
                         domainRawValue: seed.domain.rawValue,
                         scope: seed.scope,
                         sortOrder: seed.sortOrder,
                         isArchived: false,
                         goalKinds: (DefaultData.categoryGoalKinds[seed.code] ?? []).map(\.rawValue))
        }
    }

    func category(code: String?) -> CategoryInfo? {
        guard let code else { return nil }
        return categories.first { $0.code == code }
    }

    func categories(kind: TransactionKind? = nil, includeArchived: Bool = false) -> [CategoryInfo] {
        categories.filter { item in
            (kind == nil || item.kind == kind) && (includeArchived || !item.isArchived)
        }
        .sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name < $1.name
        }
    }

    /// 服务端下发的是全量快照：整体替换，而不是和本地取并集。
    /// 合并会把内置表里残留的旧 code 留下来，界面上就会出现同名的两条分类。
    func apply(version newVersion: Int, categories incoming: [CategoryInfo]) {
        guard newVersion > version else { return }
        categories = incoming.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.code < $1.code
        }
        version = newVersion
        save()
    }

    private func save() {
        guard let cacheURL else { return }
        let cache = Cache(schema: Self.cacheSchema, version: version, categories: categories)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
