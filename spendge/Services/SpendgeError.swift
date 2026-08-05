import Foundation

enum SpendgeError: LocalizedError {
    case invalidAmount
    case invalidDate
    case accountHasTransactions
    case cannotDeleteSystemCategory

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
        }
    }
}
