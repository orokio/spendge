import Foundation

enum SpendgeError: LocalizedError {
    case invalidAmount
    case invalidDate
    case accountHasTransactions
    case cannotDeleteSystemCategory
    /// DEBUG 故障注入：带具体故障点，方便定位
    case injectedFailure(FaultPoint)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "金额必须大于 0"
        case .invalidDate:
            return "日期无效"
        case .accountHasTransactions:
            return "该账户下存在账单，不能删除"
        case .cannotDeleteSystemCategory:
            return "系统预置分类不能删除"
        case .injectedFailure(let point):
            return "模拟失败：\(point.title)"
        }
    }
}
