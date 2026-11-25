import Foundation

enum SpendgeError: LocalizedError {
    case invalidAmount
    case invalidDate
    case cannotDeleteSystemCategory
    /// DEBUG 故障注入：带具体故障点，方便定位
    case amountTooLarge
    case futureDate
    case noteTooLong
    case goalTitleTooLong
    case invalidGoalTarget
    /// DEBUG 故障注入：带具体故障点，方便定位
    case injectedFailure(FaultPoint)
    case notRefundable
    case alreadyRefunded
    case goalLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "金额必须大于 0"
        case .invalidDate:
            return "日期无效"
        case .cannotDeleteSystemCategory:
            return "系统预置分类不能删除"
        case .amountTooLarge:
            let maxYuan = Money.roundedYuan(from: InputLimits.amountCentsMax)
            return "单笔金额不能超过 ¥\(maxYuan)"
        case .futureDate:
            return "不能记录未来的日期"
        case .noteTooLong:
            return "备注最多 \(InputLimits.noteLength) 个字"
        case .goalTitleTooLong:
            return "目标名称最多 \(InputLimits.goalTitleLength) 个字"
        case .invalidGoalTarget:
            return "目标数值超出允许范围"
        case .injectedFailure(let point):
            return "模拟失败：\(point.title)"
        case .notRefundable:
            return "这笔账单不能退款"
        case .alreadyRefunded:
            return "这笔账单已经退过款"
        case .goalLimitReached:
            return "免费版最多 \(Entitlements.freeGoalLimit) 个目标，解锁后不限"
        }
    }
}
