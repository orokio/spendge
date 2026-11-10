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

/// 账单来源。manual 手动记录，backfill 事后补记（含截图 / 语音解析）。
enum TransactionSource: String, Codable, CaseIterable, Sendable {
    case manual
    case backfill
}

/// 内部横切标签：饮食方式。
enum DietMode: String, Codable, CaseIterable, Sendable {
    case homemade
    case eatingOut
}

/// 内部横切标签：消费场景。
enum SpendScene: String, Codable, CaseIterable, Sendable {
    case solo
    case social
}

/// 内部横切标签：消费性质。
enum SpendNature: String, Codable, CaseIterable, Sendable {
    case essential
    case enjoyment
}

/// 分类的内部聚合领域。用户不可见，只用于回看聚合。
enum CategoryDomain: String, Codable, CaseIterable, Sendable {
    case food        // 吃
    case transport   // 行
    case housing     // 住
    case goods       // 用
    case play        // 玩
    case social      // 人情
    case health      // 健康
    case other       // 其他

    var displayName: String {
        switch self {
        case .food: return "吃"
        case .transport: return "行"
        case .housing: return "住"
        case .goods: return "用"
        case .play: return "玩"
        case .social: return "人情"
        case .health: return "健康"
        case .other: return "其他"
        }
    }
}

/// 分类的稳定标识。代码里一律按 code 匹配，不按 name。
enum CategoryCode: String, CaseIterable, Sendable {
    // 支出
    case grocery = "grocery"
    case takeout = "takeout"
    case dineout = "dineout"
    case drink = "drink"
    case transport = "transport"
    case housing = "housing"
    case shopping = "shopping"
    case fun = "fun"
    case social = "social"
    case health = "health"
    case otherExpense = "other_expense"
    // 收入
    case salary = "salary"
    case sideJob = "side_job"
    case invest = "invest"
    case otherIncome = "other_income"
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
