import CoreGraphics

/// 页面级栅格：左右边线与上下间距都从这里取。
///
/// 规则：
/// - 页面容器只加一次 pageInset / sectionGap，组件内部不要再手填数字微调；
/// - 上下间距只有三级：行内 8、块内 12、区块之间 32。
enum PageLayout {
    /// 页面左右边距
    static let pageInset: CGFloat = 20

    /// 区块之间：情绪块↔列表 / 预算↔饼图 / 我的页标题↔表单
    static let sectionGap: CGFloat = 28

    /// 块内标题与内容：副标题↔时间轴、标题↔图例、图例↔饼图
    static let blockGap: CGFloat = 12

    /// 行内元素：情绪文字↔副标题、同一行的标签
    static let inlineGap: CGFloat = 8
}
