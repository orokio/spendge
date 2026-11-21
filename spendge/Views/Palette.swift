import SwiftUI

/// 一层颜色语义 token。
///
/// 视图只认「强调色 / 表面 / 背景 / 文字 / 领域色」，不再直接写 hex 或系统灰。
/// 换主题 = 换一套 `Palette`，不用逐个视图改颜色。
struct Palette {
    /// 主强调色：按钮、选中、柱子
    let accent: Color
    /// 强调色的浅色版：选中底、标签底、淡填充
    let accentSoft: Color
    /// 压重的文字色：情绪句关键词、月度结论。用量极少
    let deepGreen: Color
    /// 收入色
    let income: Color
    /// 提醒色：支出比上期涨了，用暖黄，不用红
    let warning: Color
    /// 冷蓝：收入金额、刚性 / 稳定结构，以及需要与品牌绿区分的中性强调
    let info: Color
    /// 超限：只在真的越线时出现
    let danger: Color
    /// 强调色 / 危险色上的文字与图标
    let onAccent: Color
    /// 浮层背后的遮罩
    let scrim: Color
    /// 页面底色（根背景）
    let background: Color
    /// 表面色：键盘、输入框、分段控件底
    let surface: Color
    /// 整页容器色（记录页整页、卡片）
    let surfaceElevated: Color
    /// 正文与次要文字
    let text: Color
    let textSecondary: Color
    /// 顶部渐变（颜色 + 位置）
    let gradientStops: [(color: Color, location: Double)]
    /// 领域配色：回看页饼图与图例
    let domainColors: [CategoryDomain: Color]

    func domainColor(_ domain: CategoryDomain) -> Color {
        domainColors[domain] ?? textSecondary
    }
}

/// 全局背景：底色 + 顶部渐变，三个 tab 各自铺一层，
/// 因为 TabView 的页面容器自带不透明底色，根部的渐变会被盖住。
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.canvas
            LinearGradient(
                stops: Palette.current.gradientStops.map {
                    Gradient.Stop(color: $0.color, location: $0.location)
                },
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

extension Palette {
    /// 薄荷：当前启用的主题
    static let mint = Palette(
        accent: Color(hex: "#14B8A6"),
        accentSoft: Color(hex: "#14B8A6").opacity(0.12),
        deepGreen: Color(hex: "#0F766E"),
        income: Color(hex: "#10B981"),
        warning: Color(hex: "#D97706"),
        info: Color(hex: "#3B82F6"),
        danger: Color(hex: "#D9503F"),
        onAccent: Color(hex: "#FFFFFF"),
        scrim: Color.black.opacity(0.18),
        background: Color(.systemGroupedBackground),
        surface: Color(.systemGray6),
        surfaceElevated: Color(hex: "#FFFFFF"),
        text: Color(hex: "#3F5150"),
        textSecondary: Color(hex: "#6B7A78"),
        gradientStops: [
            (Color(hex: "#14B8A6").opacity(0.20), 0),
            (Color(hex: "#14B8A6").opacity(0.15), 0.10),
            (Color(hex: "#14B8A6").opacity(0.09), 0.24),
            (Color(hex: "#14B8A6").opacity(0.04), 0.40),
            (Color(hex: "#14B8A6").opacity(0.012), 0.58),
            (Color(hex: "#14B8A6").opacity(0), 0.74),
        ],
        domainColors: [
            .food: Color(hex: "#FB923C"),
            .transport: Color(hex: "#3B82F6"),
            .housing: Color(hex: "#0D9488"),
            .goods: Color(hex: "#A855F7"),
            .play: Color(hex: "#EC4899"),
            .social: Color(hex: "#EF4444"),
            .health: Color(hex: "#10B981"),
            .communication: Color(hex: "#06B6D4"),
            .other: Color(hex: "#94A3B8"),
        ]
    )

    /// 暖色：暂存，尚未启用（配色取自 design/logo/warm 那套奶油桃）
    static let warm = Palette(
        accent: Color(hex: "#B7653C"),
        accentSoft: Color(hex: "#E2C9A6"),
        deepGreen: Color(hex: "#7A3E22"),
        income: Color(hex: "#8FA36B"),
        warning: Color(hex: "#B7653C"),
        info: Color(hex: "#7C8FA3"),
        danger: Color(hex: "#C2544B"),
        onAccent: Color(hex: "#FFFDFB"),
        scrim: Color.black.opacity(0.18),
        background: Color(hex: "#FBF3EA"),
        surface: Color(hex: "#F3E7D9"),
        surfaceElevated: Color(hex: "#FFFDFB"),
        text: Color(hex: "#3E342C"),
        textSecondary: Color(hex: "#8A7A6C"),
        gradientStops: [
            (Color(hex: "#E2C9A6").opacity(0.40), 0),
            (Color(hex: "#E2C9A6").opacity(0.28), 0.10),
            (Color(hex: "#E2C9A6").opacity(0.16), 0.24),
            (Color(hex: "#E2C9A6").opacity(0.07), 0.40),
            (Color(hex: "#E2C9A6").opacity(0.02), 0.58),
            (Color(hex: "#E2C9A6").opacity(0), 0.74),
        ],
        domainColors: [
            .food: Color(hex: "#C4703F"),
            .transport: Color(hex: "#7C8FA3"),
            .housing: Color(hex: "#9A8B5C"),
            .goods: Color(hex: "#A9705E"),
            .play: Color(hex: "#8A6A8F"),
            .social: Color(hex: "#C2544B"),
            .health: Color(hex: "#8FA36B"),
            .other: Color(hex: "#A99A8C"),
        ]
    )

    /// 当前启用的主题：以后做切换时，这里改成从设置读取并触发刷新
    static var current: Palette = .mint
}
