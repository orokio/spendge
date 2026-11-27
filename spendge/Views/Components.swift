import SwiftUI

// MARK: - Color

extension Color {
    /// 品牌主色（语义 token，实际取值见 Palette）
    static var brand: Color { Palette.current.accent }
    /// 强调色的浅色版
    static var brandSoft: Color { Palette.current.accentSoft }
    /// 收入色
    static var income: Color { Palette.current.income }
    /// 提醒色：支出比上期涨了
    static var warning: Color { Palette.current.warning }
    /// 达标 / 稳定态
    static var info: Color { Palette.current.info }
    /// 超限
    static var danger: Color { Palette.current.danger }
    /// 传说级奖杯
    static var gold: Color { Palette.current.gold }
    /// 强调色上的文字 / 图标
    static var onAccent: Color { Palette.current.onAccent }
    /// 浮层遮罩
    static var scrim: Color { Palette.current.scrim }
    /// 页面底色
    static var canvas: Color { Palette.current.background }
    /// 表面色：键盘、输入框、分段控件底
    static var surface: Color { Palette.current.surface }
    /// 整页容器 / 卡片色
    static var surfaceElevated: Color { Palette.current.surfaceElevated }
    /// 正文与次要文字
    static var textPrimary: Color { Palette.current.text }
    static var textSecondary: Color { Palette.current.textSecondary }
    /// 领域色：饼图与图例的唯一来源
    static func domainColor(_ domain: CategoryDomain) -> Color {
        Palette.current.domainColor(domain)
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - 金额格式化

enum AmountFormat {
    /// 分 → "¥1,235"
    /// - Parameter exact: 为 true 时保留角分（去掉末尾的 0），流水明细用它；
    ///   否则四舍五入到整元，汇总与统计用这个。
    static func string(cents: Int64, showsSign: Bool = false, exact: Bool = false) -> String {
        let number: String
        if exact {
            number = Money.yuan(from: abs(cents)).formatted(
                .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "zh_CN"))
            )
        } else {
            number = Money.roundedYuan(from: cents).formatted(
                .number.locale(Locale(identifier: "zh_CN"))
            )
        }
        let sign: String
        if !showsSign {
            sign = ""
        } else if cents > 0 {
            sign = "+"
        } else if cents < 0 {
            sign = "-"
        } else {
            sign = ""
        }
        return "\(sign)¥\(number)"
    }
}

// MARK: - 流式布局

/// 自动换行布局。用于分类胶囊，避免"要拖动才看得全"。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth == .infinity ? x : maxWidth
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 日期工具

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? date
    }
}

// MARK: - 分类图标

struct CategoryIcon: View {
    let iconName: String
    let colorHex: String
    var size: CGFloat = 40

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
            Image(systemName: iconName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// 全局滑入页左上角的返回：主题色、32pt 点击区，放在标题上方。
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: PageLayout.backButtonSize, height: PageLayout.backButtonSize, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 区块小标题：左边标题，右边一句灰色补充（日期、范围等）。
/// 今天页「今日流水 + 日期」是它的基准样式，其他页面同构的标题都用它。
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typography.sectionTitle)
            Spacer(minLength: 12)
            trailing()
                .font(Typography.label)
                .foregroundStyle(.secondary)
        }
    }
}

struct CategoryBadge: View {
    let category: CategoryInfo
    var iconSize: CGFloat = 44
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            CategoryIcon(iconName: category.iconName, colorHex: category.colorHex, size: iconSize)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.brand, lineWidth: 2.5)
                            .padding(-4)
                    }
                }
            Text(category.displayName)
                .font(Typography.label)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 月份切换

struct MonthStepper: View {
    @Binding var month: Date

    var body: some View {
        HStack {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(Typography.bodyStrong)
                    .frame(width: 36, height: 36)
                    .background(Color.surface, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(Typography.sectionTitle)
                .contentTransition(.numericText())

            Spacer()

            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(Typography.bodyStrong)
                    .frame(width: 36, height: 36)
                    .background(Color.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private var title: String {
        month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    private func shift(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: month) {
            month = Calendar.current.startOfMonth(for: newDate)
        }
    }
}

/// 从屏幕顶部滑下来的抽屉：半透明遮罩 + 贴顶底板 + 下滑动画。
/// 用法是放在 overlay(alignment: .top) 里，传入绑定和内容。
struct TopDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            if isPresented {
                Color.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { close() }

                content
                    // 底板向上铺到屏幕最上沿，把状态栏那块也盖住
                    .background {
                        UnevenRoundedRectangle(bottomLeadingRadius: 28,
                                               bottomTrailingRadius: 28,
                                               style: .continuous)
                            .fill(Color.surfaceElevated)
                            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                            .ignoresSafeArea(.container, edges: .top)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .ignoresSafeArea(.keyboard)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isPresented)
        .onChange(of: isPresented) { _, shown in
            // 收起抽屉时同时收键盘，两者才会一起走
            if !shown { hideKeyboard() }
        }
    }

    private func close() {
        hideKeyboard()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isPresented = false
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}


// MARK: - 统一确认弹层

/// 全 App 统一使用的确认请求：遮罩 + 居中卡片，不用系统 alert。
///
/// 系统 confirmationDialog 会锚定在被点控件上，靠屏幕底部时向下展开、超出屏幕；
/// 系统 alert 在 overlay 层里也不一定弹得出来，所以统一自己画。
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var confirmTitle = "继续"
    var isDestructive = true
    /// 为 nil 时只显示一个「好」按钮
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
}

extension View {
    /// 挂载统一确认弹层；点遮罩或「取消」关闭
    func confirmDialog(_ request: Binding<ConfirmRequest?>) -> some View {
        overlay {
            if let item = request.wrappedValue {
                ConfirmOverlayCard(request: item) {
                    request.wrappedValue = nil
                }
                .transition(.opacity)
            }
        }
    }
}

struct ConfirmOverlayCard: View {
    let request: ConfirmRequest
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    request.onCancel?()
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 12) {
                Text(request.title)
                    .font(Typography.bodyStrong)
                    .foregroundStyle(Color.textPrimary)

                Text(request.message)
                    .font(Typography.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let action = request.onConfirm {
                        Button {
                            request.onCancel?()
                            onDismiss()
                        } label: {
                            Text("取消")
                                .font(Typography.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onDismiss()
                            action()
                        } label: {
                            Text(request.confirmTitle)
                                .font(Typography.body)
                                .foregroundStyle(Color.onAccent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(request.isDestructive ? Color.danger : Color.brand,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            onDismiss()
                        } label: {
                            Text("好")
                                .font(Typography.body)
                                .foregroundStyle(Color.onAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.brand, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 32)
        }
    }
}


/// 按下时不改变颜色和透明度：给悬浮按钮这类需要「稳」的控件用
struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension ButtonStyle where Self == NoHighlightButtonStyle {
    static var noHighlight: NoHighlightButtonStyle { NoHighlightButtonStyle() }
}
