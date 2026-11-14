import SwiftUI

/// 设置某个月的预算：只做一个总额，不提醒、不变色。
struct BudgetEditorSheet: View {
    let monthTitle: String
    let initialCents: Int64?
    let initialRecurring: Bool
    let onSave: (Int64, Bool) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var recurring: Bool

    init(monthTitle: String,
         initialCents: Int64?,
         initialRecurring: Bool = false,
         onSave: @escaping (Int64, Bool) -> Void,
         onClear: @escaping () -> Void) {
        self.monthTitle = monthTitle
        self.initialCents = initialCents
        self.initialRecurring = initialRecurring
        self.onSave = onSave
        self.onClear = onClear
        _text = State(initialValue: initialCents.map { Self.text(fromCents: $0) } ?? "")
        _recurring = State(initialValue: initialRecurring)
    }

    private static func text(fromCents cents: Int64) -> String {
        cents % 100 == 0 ? String(cents / 100) : String(format: "%.2f", Double(cents) / 100)
    }

    private var cents: Int64? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: "")), value > 0 else { return nil }
        return Int64((value * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text("\(monthTitle)预算")
                    .font(.headline)

                Spacer()

                if initialCents != nil {
                    Button {
                        onClear()
                        dismiss()
                    } label: {
                        Text("清除预算")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let cents {
                        onSave(cents, recurring)
                        dismiss()
                    }
                } label: {
                    Text("保存")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cents == nil ? Color.secondary : Color.brand)
                }
                .buttonStyle(.plain)
                .disabled(cents == nil)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.brand)
            }

            Button {
                recurring.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: recurring ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(recurring ? Color.brand : Color.secondary)
                    Text("循环应用到下个月")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(24)
    }
}

/// 选择月份。不用导航栏，避免滚动时顶部出现半透明效果。
/// 月份选择面板（回看页顶部切换月份用）
struct MonthPickerSheet: View {
    let selected: Date
    let onPick: (Date) -> Void

    private var options: [Date] {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: .now)
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: base) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("选择月份")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { date in
                        Button {
                            onPick(date)
                        } label: {
                            HStack {
                                Text(date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if Calendar.current.isDate(date, equalTo: selected, toGranularity: .month) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.brand)
                                }
                            }
                            .padding(.horizontal, PageLayout.pageInset)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color.surfaceElevated)
    }
}
