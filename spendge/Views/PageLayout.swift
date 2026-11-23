import CoreGraphics

/// 页面级栅格：左右边线与上下间距都从这里取。
///
/// 规则：
/// - 页面容器只加一次 pageInset / sectionGap，组件内部不要再手填数字微调；
/// - 上下间距只有几级：行内 8、卡片堆叠 12、块内 12、卡片内 20、区块之间 28。
enum PageLayout {
    /// 页面左右边距
    static let pageInset: CGFloat = 20

    /// 区块之间：情绪块↔列表 / 预算↔饼图 / 我的页标题↔表单
    static let sectionGap: CGFloat = 28

    /// 块内标题与内容：副标题↔时间轴、标题↔图例、图例↔饼图
    static let blockGap: CGFloat = 12

    /// 卡片内：标题↔内容，内容↔卡片底部，两个方向用同一个值
    static let cardTitleGap: CGFloat = 20

    /// 同权重卡片连续堆叠：卡片之间统一 12，比区块间距紧
    static let stackedCardGap: CGFloat = 12

    // MARK: - 二级页

    /// 二级页顶部留白（返回按钮上方）
    static let pageTopInset: CGFloat = 12
    /// 返回按钮的点击区与图标框
    static let backButtonSize: CGFloat = 32
    /// 返回按钮与页面标题之间：所有二级页统一
    static let backToTitleGap: CGFloat = 12
    /// 滚动页底部留白：给悬浮底部导航让位
    static let tabBarClearance: CGFloat = 110

    /// 行内元素：情绪文字↔副标题、同一行的标签
    static let inlineGap: CGFloat = 8

    // MARK: - 圆角

    /// 卡片：预算卡、目标卡、列表容器
    static let cardRadius: CGFloat = 22
    /// 卡片内的分组块
    static let moduleRadius: CGFloat = 14
}
