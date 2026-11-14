import SwiftUI

/// 全站字阶：一个角色一个 token，视图里不再手写 size / weight。
///
/// 规则：
/// - 重量只用 regular 和 semibold（金额输入是唯一例外，用 bold）；
/// - rounded 只给页面标题和数字，正文用系统默认字体；
/// - 同一角色的字号不再各处不同。
enum Typography {
    // MARK: 标题

    /// 情绪大句：比页面标题大一档，是全屏最重的那句话
    static let hero = Font.system(size: 26, weight: .semibold, design: .rounded)
    /// 页面标题（四个 tab 的主标题）
    static let pageTitle = Font.system(size: 24, weight: .semibold, design: .rounded)
    /// 区块标题（今日流水、钱花在哪儿、先定一个目标）
    static let sectionTitle = Font.headline

    // MARK: 数字

    /// 卡片主数字：预算金额、目标阈值
    static let number = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// 次一级数字：进度分数、状态值
    static let numberSmall = Font.system(size: 15, weight: .semibold, design: .rounded)
    /// 大一号的数字：键盘、表单输入、饼图中心
    static let numberLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
    /// 金额输入框：唯一允许 bold 的地方
    static let amountInput = Font.system(size: 36, weight: .bold, design: .rounded)

    // MARK: 文本

    /// 列表主文案 / 表单输入：比正文大一档
    static let rowTitle = Font.body
    /// 正文 / 说明性文案
    static let body = Font.subheadline
    /// 需要强调的正文：按钮、胶囊、行内主文案
    static let bodyStrong = Font.subheadline.weight(.semibold)
    /// 说明、副标题、单位
    static let label = Font.footnote
    /// 角标、周期、图例小字
    static let caption = Font.caption2
    /// 需要强调的角标
    static let captionStrong = Font.caption2.weight(.semibold)
    /// 时间轴刻度：唯一比 caption 更小的场景
    static let axisLabel = Font.system(size: 9)
}
