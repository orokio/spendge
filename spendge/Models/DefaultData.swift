import Foundation
import SwiftData

/// 首次启动写入的预置分类：25 个支出 + 4 个收入 + 默认「现金」账户。
///
/// 分类是用户可见的**动作**（我做了什么），内部领域（domain）用户不可见。
/// 代码里一律按 code 匹配，不按 name —— 改名不应影响任何逻辑。
/// `scope` 是「包含范围」，既给人看，也用于备注 / 语音的自动识别。
enum DefaultData {
    struct CategorySeed {
        let code: CategoryCode
        let name: String
        let iconName: String
        let colorHex: String
        let kind: TransactionKind
        let domain: CategoryDomain
        let scope: String
        let sortOrder: Int
    }

    static let expenseCategorySeeds: [CategorySeed] = [
        // 一、吃
        .init(code: .takeout, name: "点外卖", iconName: "takeoutbag.and.cup.and.straw.fill",
              colorHex: "#FB923C", kind: .expense, domain: .food,
              scope: "外卖点餐、外卖熟食、美团、饿了么", sortOrder: 1),
        .init(code: .dineout, name: "下馆子", iconName: "fork.knife",
              colorHex: "#F59E0B", kind: .expense, domain: .food,
              scope: "堂食、聚餐、到店就餐、饭店、餐厅、火锅", sortOrder: 2),
        .init(code: .grocery, name: "买菜食材", iconName: "basket.fill",
              colorHex: "#F97316", kind: .expense, domain: .food,
              scope: "菜、肉、蛋、米面粮油、调料、菜市场、生鲜、超市", sortOrder: 3),
        .init(code: .drink, name: "奶茶咖啡", iconName: "cup.and.saucer.fill",
              colorHex: "#B45309", kind: .expense, domain: .food,
              scope: "咖啡、奶茶、果茶、新式茶饮、星巴克、瑞幸、喜茶", sortOrder: 4),
        .init(code: .alcoholBeverage, name: "酒水饮料", iconName: "wineglass",
              colorHex: "#92400E", kind: .expense, domain: .food,
              scope: "啤酒、白酒、红酒、果酒、饮料、可乐、矿泉水、预包装饮品", sortOrder: 5),
        .init(code: .snack, name: "零食水果", iconName: "carrot.fill",
              colorHex: "#FBBF24", kind: .expense, domain: .food,
              scope: "包装零食、糕点、坚果、水果、果切", sortOrder: 6),

        // 二、用
        .init(code: .daily, name: "生活日用", iconName: "shippingbox.fill",
              colorHex: "#A855F7", kind: .expense, domain: .goods,
              scope: "洗护、清洁、纸品、卫生用品、日用品", sortOrder: 11),
        .init(code: .wear, name: "衣帽鞋袜", iconName: "tshirt.fill",
              colorHex: "#EC4899", kind: .expense, domain: .goods,
              scope: "衣服、鞋、包、配饰、裤子、外套", sortOrder: 12),
        .init(code: .digitalGear, name: "数码器材", iconName: "camera.fill",
              colorHex: "#6366F1", kind: .expense, domain: .goods,
              scope: "手机配件、耳机、相机、小数码、硬件外设、充电器、数据线、充电宝、硬盘", sortOrder: 13),
        .init(code: .sportsOutdoor, name: "运动户外", iconName: "figure.run",
              colorHex: "#65A30D", kind: .expense, domain: .goods,
              scope: "健身、游泳、球类、瑜伽、露营、登山、滑雪、骑行、跑鞋", sortOrder: 14),

        // 三、住
        .init(code: .housing, name: "房租房贷", iconName: "house.fill",
              colorHex: "#14B8A6", kind: .expense, domain: .housing,
              scope: "房租、房贷、月供", sortOrder: 21),
        .init(code: .utilities, name: "水电燃气", iconName: "drop.fill",
              colorHex: "#0891B2", kind: .expense, domain: .housing,
              scope: "水费、电费、燃气费、水电", sortOrder: 22),
        .init(code: .broadband, name: "宽带物业", iconName: "wifi",
              colorHex: "#0284C7", kind: .expense, domain: .housing,
              scope: "宽带费、物业费、宽带、物业", sortOrder: 23),
        .init(code: .renovation, name: "装修维护", iconName: "hammer.fill",
              colorHex: "#78716C", kind: .expense, domain: .housing,
              scope: "装修、维修、家居改造、换锁", sortOrder: 24),
        .init(code: .appliance, name: "家具家电", iconName: "sofa.fill",
              colorHex: "#C026D3", kind: .expense, domain: .housing,
              scope: "大件家具、家电、家具、沙发、冰箱、洗衣机、空调", sortOrder: 25),

        // 四、行
        .init(code: .outing, name: "交通出行", iconName: "car.fill",
              colorHex: "#3B82F6", kind: .expense, domain: .transport,
              scope: "公交、地铁、打车、共享单车、出租车、网约车", sortOrder: 31),
        .init(code: .fuel, name: "加油充电", iconName: "fuelpump.fill",
              colorHex: "#EA580C", kind: .expense, domain: .transport,
              scope: "加油、充电、油费、汽油、充电桩", sortOrder: 32),
        .init(code: .travel, name: "机票酒店", iconName: "airplane",
              colorHex: "#2563EB", kind: .expense, domain: .transport,
              scope: "火车、高铁、机票、酒店、民宿、住宿", sortOrder: 33),
        .init(code: .carCare, name: "停车保养", iconName: "parkingsign",
              colorHex: "#475569", kind: .expense, domain: .transport,
              scope: "停车费、停车、车辆保养、保养、洗车、年检、车险", sortOrder: 34),

        // 五、玩
        .init(code: .game, name: "游戏娱乐", iconName: "gamecontroller.fill",
              colorHex: "#8B5CF6", kind: .expense, domain: .play,
              scope: "游戏、电影、门票、展览、演出、爱好、剧本杀", sortOrder: 41),

        // 六、健康
        .init(code: .health, name: "医疗保健", iconName: "cross.case.fill",
              colorHex: "#10B981", kind: .expense, domain: .health,
              scope: "门诊、药品、体检、保健、医院、看病", sortOrder: 51),

        // 七、人情
        .init(code: .social, name: "人情往来", iconName: "gift.fill",
              colorHex: "#EF4444", kind: .expense, domain: .social,
              scope: "送礼、请客、红包、随礼、礼物", sortOrder: 61),

        // 八、其他
        .init(code: .phone, name: "通讯话费", iconName: "simcard.fill",
              colorHex: "#06B6D4", kind: .expense, domain: .communication,
              scope: "话费、流量包、手机充值、流量", sortOrder: 71),
        .init(code: .subscription, name: "会员订阅", iconName: "creditcard.fill",
              colorHex: "#0EA5E9", kind: .expense, domain: .communication,
              scope: "视频会员、软件会员、云服务、周期扣费、会员、订阅、续费、网盘", sortOrder: 72),
        .init(code: .otherExpense, name: "其他", iconName: "ellipsis.circle",
              colorHex: "#9CA3AF", kind: .expense, domain: .other,
              scope: "", sortOrder: 81),
    ]

    static let incomeCategorySeeds: [CategorySeed] = [
        .init(code: .salary, name: "工资", iconName: "banknote.fill",
              colorHex: "#3B82F6", kind: .income, domain: .other,
              scope: "固定薪资、工资、薪水", sortOrder: 101),
        .init(code: .sideJob, name: "兼职", iconName: "briefcase.fill",
              colorHex: "#3B82F6", kind: .income, domain: .other,
              scope: "兼职、外快、副业", sortOrder: 102),
        .init(code: .invest, name: "理财", iconName: "chart.line.uptrend.xyaxis",
              colorHex: "#3B82F6", kind: .income, domain: .other,
              scope: "利息、投资收益、分红、理财", sortOrder: 103),
        .init(code: .otherIncome, name: "其他", iconName: "plus.circle",
              colorHex: "#3B82F6", kind: .income, domain: .other,
              scope: "其他收入", sortOrder: 199),
    ]

    /// 分类体系改版：把旧分类迁到新分类上，**保留已有账单**。
    /// 与结构变更不同，这里不删库——账单归属是用户数据。
    static func migrateCategoriesIfNeeded(context: ModelContext) {
        let key = "spendge.categoryMigration"
        let version = UserDefaults.standard.integer(forKey: key)
        guard version < 15 else { return }

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        guard !categories.isEmpty else {
            UserDefaults.standard.set(15, forKey: key)
            return
        }

        func category(_ code: String) -> Category? {
            categories.first { $0.code == code }
        }

        // 11 及更早：旧的「买东西」并入装备；交通 + 娱乐合成「出行游玩」
        if version < 11 {
            category("shopping")?.code = CategoryCode.digitalGear.rawValue
            if let outing = category("outing") ?? category("transport") {
                outing.code = CategoryCode.outing.rawValue
                outing.name = "交通出行"
                outing.domain = .transport
                if let fun = category("fun") {
                    for txn in fun.transactions {
                        txn.category = outing
                    }
                    context.delete(fun)
                }
            }
        }

        // 12：装备器材 → 数码器材，code 一并改；目标里引用的分类同步改名
        if let gear = category("gear") {
            gear.code = CategoryCode.digitalGear.rawValue
        }
        if let goals = try? context.fetch(FetchDescriptor<Goal>()) {
            for goal in goals {
                let mapped = goal.categoryCodes.map {
                    $0 == "gear" ? CategoryCode.digitalGear.rawValue : $0
                }
                if mapped != goal.categoryCodes { goal.categoryCodes = mapped }
            }
        }

        // 按种子校正名称、图标、领域、排序与包含范围
        for seed in expenseCategorySeeds + incomeCategorySeeds {
            guard let existing = category(seed.code.rawValue) else { continue }
            existing.name = seed.name
            existing.iconName = seed.iconName
            existing.colorHex = seed.colorHex
            existing.domain = seed.domain
            existing.sortOrder = seed.sortOrder
            existing.scope = seed.scope
        }

        // 补充新增分类
        let existingCodes = Set(categories.compactMap(\.code))
        for seed in expenseCategorySeeds + incomeCategorySeeds where !existingCodes.contains(seed.code.rawValue) {
            context.insert(Category(
                name: seed.name,
                code: seed.code.rawValue,
                iconName: seed.iconName,
                colorHex: seed.colorHex,
                kind: seed.kind,
                domain: seed.domain,
                scope: seed.scope,
                sortOrder: seed.sortOrder,
                isSystem: true
            ))
        }

        try? context.save()
        UserDefaults.standard.set(15, forKey: key)
    }

    /// 幂等：已有数据时不重复写入。
    static func seedIfNeeded(context: ModelContext) {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        if categoryCount == 0 {
            for seed in expenseCategorySeeds + incomeCategorySeeds {
                context.insert(Category(
                    name: seed.name,
                    code: seed.code.rawValue,
                    iconName: seed.iconName,
                    colorHex: seed.colorHex,
                    kind: seed.kind,
                    domain: seed.domain,
                    scope: seed.scope,
                    sortOrder: seed.sortOrder,
                    isSystem: true
                ))
            }
        }

        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        if accountCount == 0 {
            context.insert(Account(
                name: "现金",
                iconName: "banknote",
                colorHex: "#10B981",
                kind: .cash,
                sortOrder: 1
            ))
        }

        try? context.save()
    }
}