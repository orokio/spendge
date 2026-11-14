import SwiftUI

// MARK: - Color

extension Color {
    /// 品牌主色（语义 token，实际取值见 Palette）
    static var brand: Color { Palette.current.accent }
    /// 强调色的浅色版
    static var brandSoft: Color { Palette.current.accentSoft }
    /// 收入色
    static var income: Color { Palette.current.income }
    /// 页面底色
    static var canvas: Color { Palette.current.background }
    /// 表面色：键盘、输入框、分段控件底
    static var surface: Color { Palette.current.surface }
    /// 整页容器 / 卡片色
    static var surfaceElevated: Color { Palette.current.surfaceElevated }
    /// 正文与次要文字
    static var textPrimary: Color { Palette.current.text }
    static var textSecondary: Color { Palette.current.textSecondary }

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
    /// 分 → "¥1,234.5" 形式
    static func string(cents: Int64, showsSign: Bool = false) -> String {
        let yuan = Money.yuan(from: abs(cents))
        let number = yuan.formatted(
            .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "zh_CN"))
        )
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

/// 区块小标题：左边标题，右边一句灰色补充（日期、范围等）。
/// 今天页「今日流水 + 日期」是它的基准样式，其他页面同构的标题都用它。
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer(minLength: 12)
            trailing()
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct CategoryBadge: View {
    let category: Category
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
                .font(.caption)
                .foregroundStyle(.primary)
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
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.surface, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.headline)
                .contentTransition(.numericText())

            Spacer()

            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
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
