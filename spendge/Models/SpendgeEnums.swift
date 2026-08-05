import Foundation

/// 收支类型
enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income

    /// UI 展示用中文名（后续 UI 阶段可调整）
    var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }
}

/// 账户类型
enum AccountKind: String, Codable, CaseIterable, Sendable {
    case cash       // 现金
    case debitCard  // 储蓄卡
    case creditCard // 信用卡
    case eWallet    // 电子钱包（支付宝 / 微信等）
    case other

    var displayName: String {
        switch self {
        case .cash: return "现金"
        case .debitCard: return "储蓄卡"
        case .creditCard: return "信用卡"
        case .eWallet: return "电子钱包"
        case .other: return "其他"
        }
    }
}
