import SwiftUI

// MARK: - Color

extension Color {
    /// 品牌主色：海绵青
    static let brand = Color(hex: "#14B8A6")
    /// 收入绿
    static let income = Color(hex: "#10B981")

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
            Text(category.name)
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
                    .background(Color(.systemGray6), in: Circle())
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
                    .background(Color(.systemGray6), in: Circle())
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
