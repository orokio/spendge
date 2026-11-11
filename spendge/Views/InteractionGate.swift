import Observation

/// 页面里还有横向滚动的控件（回看页柱状图）。它们和整页翻页抢同一个横向手势，
/// 谁先识别谁说了算：控件用更小的触发距离抢先，翻页看到标记就让路。
@Observable
final class InteractionGate {
    var blockingPageSwipe = false
}
