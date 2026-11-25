import Foundation
import SwiftData

/// 目标类型：封闭枚举，不做通用规则引擎。
/// 加一种新类型 = 加一个 case + 在 GoalService 里补齐「聚合 / 展示 / 方向」。
enum GoalKind: String, CaseIterable {
    /// 某个高频分类的次数上限
    case countLimit
    /// 金额上限：categoryCodes 为空 = 全部支出，非空 = 对应分类
    case budget
    /// 某个分类占当月总支出的比例上限
    case shareCap
}

extension GoalKind {
    /// 三种维度都是「用得越少越好」
    var isAtMost: Bool { true }

    /// 阈值的单位
    var unitSuffix: String {
        switch self {
        case .countLimit: return "次"
        case .budget: return "元"
        case .shareCap: return "%"
        }
    }
}

enum GoalPeriod: String, CaseIterable {
    case month
}

/// 目标：用户语言的一句意图，底层是「范围 + 聚合 + 阈值」。
@Model
final class Goal {
    var id: UUID = UUID()
    /// 所属账本；v1 固定为默认账本
    var ledgerID: UUID?
    /// 用户语言，如「少喝奶茶」
    var title: String = ""
    var kindRawValue: String = GoalKind.countLimit.rawValue
    /// 参与聚合的分类 code；为空表示全部分类
    var categoryCodes: [String] = []
    var periodRawValue: String = GoalPeriod.month.rawValue
    /// 目标归属的月份（该月 1 号）；每个月是一份独立的目标对象
    var periodStart: Date?
    /// 计数类目标存次数 / 天数，金额类目标存分
    var targetValue: Int = 0
    var isActive: Bool = true
    /// 循环应用：下个月自动建一份一样的目标
    var isRecurring: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// 软删除时间；nil 表示未删除
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        kind: GoalKind,
        categoryCodes: [String] = [],
        period: GoalPeriod,
        periodStart: Date? = nil,
        ledgerID: UUID? = nil,
        targetValue: Int,
        isActive: Bool = true,
        isRecurring: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kind.rawValue
        self.categoryCodes = categoryCodes
        self.periodRawValue = period.rawValue
        self.periodStart = periodStart
        self.ledgerID = ledgerID
        self.targetValue = targetValue
        self.isActive = isActive
        self.isRecurring = isRecurring
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 所属月份起点；旧数据没有值时按创建时间推算
    var monthStart: Date {
        if let periodStart { return periodStart }
        return Calendar.current.dateInterval(of: .month, for: createdAt)?.start ?? createdAt
    }

    var kind: GoalKind {
        GoalKind(rawValue: kindRawValue) ?? .countLimit
    }

    /// 整体支出上限（原预算卡）
    var isBudget: Bool { kind == .budget && categoryCodes.isEmpty }

    /// 上限型（用得越少越好）还是下限型（攒得越多越好）
    var isAtMost: Bool { kind.isAtMost }
    var period: GoalPeriod { GoalPeriod(rawValue: periodRawValue) ?? .month }
}
