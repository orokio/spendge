import Foundation
import SwiftData

/// 达成记录：一个周期结束时把结果固化下来。
/// 目标被删除后记录仍然保留（goalID 只是普通字段，不是关系），这样「删除目标」不会抹掉成就。
@Model
final class GoalAchievement {
    @Attribute(.unique) var id: UUID
    /// 对应目标的 id；目标删除后这条记录依然指向它（只是查不到目标了）
    var goalID: UUID
    /// 标题快照，目标删了也能正常展示
    var title: String
    var periodRawValue: String
    /// 周期起点（周一是周起点，1 号是月起点）
    var periodStart: Date
    var achieved: Bool
    var currentValue: Int
    var targetValue: Int
    /// count / days / cents
    var unitRawValue: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        goalID: UUID,
        title: String,
        period: GoalPeriod,
        periodStart: Date,
        achieved: Bool,
        currentValue: Int,
        targetValue: Int,
        unit: GoalProgress.Unit,
        createdAt: Date = .now
    ) {
        self.id = id
        self.goalID = goalID
        self.title = title
        self.periodRawValue = period.rawValue
        self.periodStart = periodStart
        self.achieved = achieved
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.unitRawValue = Self.unitRawValue(unit)
        self.createdAt = createdAt
    }

    var period: GoalPeriod { GoalPeriod(rawValue: periodRawValue) ?? .month }

    var unit: GoalProgress.Unit {
        switch unitRawValue {
        case "cents": return .cents
        case "percent": return .percent
        default: return .count
        }
    }

    private static func unitRawValue(_ unit: GoalProgress.Unit) -> String {
        switch unit {
        case .cents: return "cents"
        case .percent: return "percent"
        case .count: return "count"
        }
    }
}
