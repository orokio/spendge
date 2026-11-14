import Foundation
import SwiftData

/// 目标类型：封闭枚举，不做通用规则引擎。
/// 加一种新类型 = 加一个 case + 在 GoalService 里补齐「聚合 / 展示 / 方向」。
enum GoalKind: String, CaseIterable {
    /// 某个高频分类的次数上限
    case countLimit
    /// 某个分类的金额上限
    case categorySum
    /// 某个分类占当月总支出的比例上限
    case shareCap
}

extension GoalKind {
    /// 三种维度都是「用得越少越好」
    var isAtMost: Bool { true }

    /// 每个维度只允许「高频、可控」的分类：刚性支出和兜底分类都不进
    var allowedCategoryCodes: [CategoryCode] {
        switch self {
        case .countLimit:
            return [.takeout, .dineout, .drink, .snack]
        case .categorySum:
            return [.takeout, .dineout, .grocery, .drink, .snack, .wear, .gear]
        case .shareCap:
            return [.takeout, .dineout, .grocery, .drink, .snack]
        }
    }

    /// 阈值的单位
    var unitSuffix: String {
        switch self {
        case .countLimit: return "次"
        case .categorySum: return "元"
        case .shareCap: return "%"
        }
    }
}

enum GoalPeriod: String, CaseIterable {
    case week
    case month
}

/// 基准：现在只用固定值，环比与三月均值留给向导那轮。
enum GoalBasis: String, CaseIterable {
    case fixed
    case previousMonth
    case trailing3Avg
}

/// 目标：用户语言的一句意图，底层是「范围 + 聚合 + 阈值」。
@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    /// 用户语言，如「少喝奶茶」
    var title: String
    var kindRawValue: String
    /// 参与聚合的分类 code；为空表示全部分类
    var categoryCodes: [String] = []
    var periodRawValue: String
    /// 计数类目标存次数 / 天数，金额类目标存分
    var targetValue: Int
    var basisRawValue: String = GoalBasis.fixed.rawValue
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: GoalKind,
        categoryCodes: [String] = [],
        period: GoalPeriod,
        targetValue: Int,
        basis: GoalBasis = .fixed,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kind.rawValue
        self.categoryCodes = categoryCodes
        self.periodRawValue = period.rawValue
        self.targetValue = targetValue
        self.basisRawValue = basis.rawValue
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: GoalKind { GoalKind(rawValue: kindRawValue) ?? .countLimit }

    /// 上限型（用得越少越好）还是下限型（攒得越多越好）
    var isAtMost: Bool { kind.isAtMost }
    var period: GoalPeriod { GoalPeriod(rawValue: periodRawValue) ?? .month }
    var basis: GoalBasis { GoalBasis(rawValue: basisRawValue) ?? .fixed }
}
