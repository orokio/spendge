import Foundation
import SwiftUI
import SwiftData

/// 奖杯墙的静态目录：30 枚奖杯的 id、名称、系列、稀有度、达成条件与图标。
///
/// 目录是代码常量，不建表：奖杯的定义跟着版本走，用户的进度靠实时计算。
/// 只有「解锁」这件事需要落库（TrophyUnlock），因为解锁日期要留住、且不可回收。
enum TrophyID: String, CaseIterable {
    // 起步
    case firstRecord, firstGoal, firstAchievement, firstIncome, firstNote
    // 累计
    case records100, records500, records1000, records5000
    case days90, days365, days730
    // 连续
    case streak7, streak30, streak100, streak365, months12
    // 目标与预算
    case goals3, goals12, goalChain3, goalChain12
    case budgets3, budgets12
    // 记录质量
    case notes100, notesHalf, fullMonth, allCategories
    // 习惯
    case nightOwl, backdated, earlyBird
}

enum TrophySeries: String, CaseIterable {
    case start, volume, streak, goal, quality, habit

    var title: String {
        switch self {
        case .start: return "起步"
        case .volume: return "累计"
        case .streak: return "连续"
        case .goal: return "目标与预算"
        case .quality: return "记录质量"
        case .habit: return "习惯"
        }
    }
}

enum TrophyRarity: String, CaseIterable {
    case common, rare, legendary

    var title: String {
        switch self {
        case .common: return "普通"
        case .rare: return "稀有"
        case .legendary: return "传说"
        }
    }

    /// 外壳形状：三档稀有度用三种轮廓，缩略图上也能分出来
    var shell: TrophyShell {
        switch self {
        case .common: return .circle
        case .rare: return .hexagon
        case .legendary: return .star
        }
    }
}

/// 进度单位，只用于「还差 2 笔」这类文案
enum TrophyUnit: String {
    case records, days, times, months, notes, categories, percent

    var suffix: String {
        switch self {
        case .records: return "笔"
        case .days: return "天"
        case .times: return "次"
        case .months: return "个月"
        case .notes: return "条"
        case .categories: return "个"
        case .percent: return "%"
        }
    }
}

struct TrophySpec: Identifiable, Equatable {
    let id: TrophyID
    /// 网格里的短名，控制在 5 个字以内
    let name: String
    let series: TrophySeries
    let rarity: TrophyRarity
    /// 详情里的完整达成条件
    let condition: String
    let symbol: String
}

enum TrophyCatalog {
    static let all: [TrophySpec] = [
        // 同系列按「达成难度」升序排列；下一档提示直接取该系列第一个未解锁项，所以顺序即指引。
        // MARK: 起步 · 5
        .init(id: .firstRecord, name: "开张", series: .start, rarity: .common,
              condition: "记下第一笔账", symbol: "sparkles"),
        .init(id: .firstNote, name: "写了备注", series: .start, rarity: .common,
              condition: "第一笔带备注的记录", symbol: "text.bubble.fill"),
        .init(id: .firstIncome, name: "有进账", series: .start, rarity: .common,
              condition: "记录第一笔收入", symbol: "banknote.fill"),
        .init(id: .firstGoal, name: "立个字据", series: .start, rarity: .common,
              condition: "创建第一个目标", symbol: "target"),
        .init(id: .firstAchievement, name: "说到做到", series: .start, rarity: .common,
              condition: "第一次达成目标", symbol: "checkmark.seal.fill"),

        // MARK: 累计 · 7
        .init(id: .records100, name: "一百笔", series: .volume, rarity: .common,
              condition: "累计记录 100 笔", symbol: "square.stack.3d.up.fill"),
        .init(id: .records500, name: "五百笔", series: .volume, rarity: .common,
              condition: "累计记录 500 笔", symbol: "square.stack.3d.up.fill"),
        .init(id: .days90, name: "三个月", series: .volume, rarity: .common,
              condition: "累计 90 天有记录", symbol: "calendar"),
        .init(id: .records1000, name: "一千笔", series: .volume, rarity: .rare,
              condition: "累计记录 1000 笔", symbol: "square.stack.3d.up.fill"),
        .init(id: .days365, name: "一整年", series: .volume, rarity: .rare,
              condition: "累计 365 天有记录", symbol: "calendar.badge.checkmark"),
        .init(id: .records5000, name: "五千笔", series: .volume, rarity: .legendary,
              condition: "累计记录 5000 笔", symbol: "crown.fill"),
        .init(id: .days730, name: "两年", series: .volume, rarity: .legendary,
              condition: "累计 730 天有记录", symbol: "calendar.circle.fill"),

        // MARK: 连续 · 5
        .init(id: .streak7, name: "一周没断", series: .streak, rarity: .common,
              condition: "连续 7 天有记录", symbol: "flame"),
        .init(id: .streak30, name: "一个月没断", series: .streak, rarity: .rare,
              condition: "连续 30 天有记录", symbol: "flame.fill"),
        .init(id: .months12, name: "十二个月", series: .streak, rarity: .rare,
              condition: "连续 12 个月都有记录", symbol: "calendar.badge.clock"),
        .init(id: .streak100, name: "一百天", series: .streak, rarity: .legendary,
              condition: "连续 100 天有记录", symbol: "bolt.fill"),
        .init(id: .streak365, name: "全年不断", series: .streak, rarity: .legendary,
              condition: "连续 365 天有记录", symbol: "sun.max.fill"),

        // MARK: 目标与预算 · 6
        .init(id: .goals3, name: "三次做到", series: .goal, rarity: .common,
              condition: "目标累计达成 3 次", symbol: "target"),
        .init(id: .budgets3, name: "守住三次", series: .goal, rarity: .common,
              condition: "单月预算没超，累计 3 次", symbol: "shield.lefthalf.filled"),
        .init(id: .goalChain3, name: "连着三个月", series: .goal, rarity: .rare,
              condition: "同一个目标连续 3 个月达成", symbol: "arrow.triangle.2.circlepath"),
        .init(id: .goals12, name: "十二次做到", series: .goal, rarity: .rare,
              condition: "目标累计达成 12 次", symbol: "scope"),
        .init(id: .budgets12, name: "守住一年", series: .goal, rarity: .legendary,
              condition: "预算连续 12 个月没超", symbol: "shield.checkered"),
        .init(id: .goalChain12, name: "连着一年", series: .goal, rarity: .legendary,
              condition: "同一个目标连续 12 个月达成", symbol: "infinity"),

        // MARK: 记录质量 · 4
        .init(id: .allCategories, name: "分类齐全", series: .quality, rarity: .common,
              condition: "单月覆盖 8 个以上分类", symbol: "square.grid.2x2.fill"),
        .init(id: .fullMonth, name: "满月", series: .quality, rarity: .common,
              condition: "某个月每一天都有记录", symbol: "moon.stars.fill"),
        .init(id: .notesHalf, name: "备注过半", series: .quality, rarity: .rare,
              condition: "某个月一半以上记录带备注", symbol: "text.alignleft"),
        .init(id: .notes100, name: "一百条备注", series: .quality, rarity: .rare,
              condition: "累计 100 笔带备注", symbol: "quote.bubble.fill"),

        // MARK: 习惯 · 3
        .init(id: .nightOwl, name: "深夜的账", series: .habit, rarity: .common,
              condition: "23 点后记过一笔", symbol: "moon.zzz.fill"),
        .init(id: .backdated, name: "想起来了", series: .habit, rarity: .common,
              condition: "补记三天前的账", symbol: "clock.arrow.circlepath"),
        .init(id: .earlyBird, name: "早起记", series: .habit, rarity: .common,
              condition: "7 点前记过一笔", symbol: "sunrise.fill"),
    ]

    static func spec(for id: TrophyID) -> TrophySpec {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 解锁记录：只写一次，永不删除（清空数据时除外）。
/// 存在即表示拿过，解锁日期用于展示。
@Model
final class TrophyUnlock {
    var trophyID: String = ""
    var unlockedAt: Date = Date.now
    /// 软删除时间；nil 表示未删除
    var deletedAt: Date?

    init(trophyID: TrophyID, unlockedAt: Date = .now) {
        self.trophyID = trophyID.rawValue
        self.unlockedAt = unlockedAt
    }

    var id: TrophyID? { TrophyID(rawValue: trophyID) }
}

/// 奖杯外壳：三档稀有度 = 三种轮廓，不靠颜色也能区分
enum TrophyShell: String {
    case circle, hexagon, star
}

struct TrophyShellShape: Shape {
    let shell: TrophyShell

    func path(in rect: CGRect) -> Path {
        switch shell {
        case .circle:
            return Path(ellipseIn: rect)
        case .hexagon:
            return polygon(in: rect, sides: 6, rotation: -90, radiusRatio: 1.0)
        case .star:
            return star(in: rect, points: 10, innerRatio: 0.78)
        }
    }

    private func polygon(in rect: CGRect, sides: Int, rotation: Double, radiusRatio: CGFloat) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * radiusRatio
        var path = Path()
        for index in 0..<sides {
            let angle = (Double(index) / Double(sides)) * 2 * .pi + rotation * .pi / 180
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                                y: center.y + radius * CGFloat(sin(angle)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func star(in rect: CGRect, points: Int, innerRatio: CGFloat) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outer : outer * innerRatio
            let angle = (Double(index) / Double(points * 2)) * 2 * .pi - .pi / 2
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                                y: center.y + radius * CGFloat(sin(angle)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

extension TrophyRarity {
    /// 稀有度色：普通 = 品牌绿、稀有 = 蓝、传说 = 金
    var tint: Color {
        switch self {
        case .common: return Color.brand
        case .rare: return Color.info
        case .legendary: return Color.gold
        }
    }
}

extension TrophyID {
    var spec: TrophySpec { TrophyCatalog.spec(for: self) }
}
