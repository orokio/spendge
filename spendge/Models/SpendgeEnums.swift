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
/// 分类的内部聚合领域。用户不可见，只用于回看聚合。
enum CategoryDomain: String, Codable, CaseIterable, Sendable {
    case food        // 吃
    case transport   // 行
    case housing     // 住
    case goods       // 用
    case play        // 玩
    case social      // 人情
    case health      // 健康
    case communication // 通信：话费与订阅
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
        case .communication: return "通信"
        case .other: return "其他"
        }
    }
}

/// 分类的稳定标识。代码里一律按 code 匹配，不按 name。
enum CategoryCode: String, CaseIterable, Sendable {
    // 支出
    case grocery = "grocery"
    case snack = "snack"
    case takeout = "takeout"
    case dineout = "dineout"
    /// 咖啡、奶茶、果茶
    case drink = "drink"
    /// 啤酒、白酒、红酒、饮料
    case alcoholBeverage
    /// 公交、地铁、打车、共享单车
    case outing = "outing"
    /// 游戏、电影、门票、展览、演出
    case game = "game"
    /// 房租、房贷月供
    case housing = "housing"
    /// 水费、电费、燃气费
    case utilities = "utilities"
    /// 宽带费、物业费
    case broadband = "broadband"
    /// 装修、维修、家居改造
    case renovation = "renovation"
    case daily = "daily"
    /// 穿的：衣帽鞋袜、包、配饰
    case wear = "wear"
    /// 数码：手机配件、耳机、相机、外设
    case digitalGear
    /// 运动与户外：健身、球类、露营、登山
    case sportsOutdoor
    /// 给家里添置的固定设施：家具、家电
    case appliance = "appliance"
    /// 加油、充电
    case fuel = "fuel"
    /// 火车、机票、酒店、民宿
    case travel = "travel"
    /// 停车费、保养、洗车
    case carCare
    /// 话费、流量包
    case phone = "phone"
    /// 视频 / 软件 / 云服务会员、周期扣费
    case subscription = "subscription"
    case social = "social"
    case health = "health"
    case otherExpense
    // 收入
    case salary = "salary"
    case sideJob
    case invest = "invest"
    case otherIncome
}

extension CategoryCode {
    /// 第一版刚性 / 弹性标注。
    /// 支出侧 true = 刚性（不太好砍），收入侧 true = 稳定（每月基本会到）。
    var isFixed: Bool {
        switch self {
        case .housing, .utilities, .broadband, .renovation, .grocery,
             .outing, .phone, .health,
             .daily, .fuel, .carCare:
            return true
        case .salary:
            return true
        default:
            return false
        }
    }
}

