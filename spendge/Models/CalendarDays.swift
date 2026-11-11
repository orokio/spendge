import Foundation

extension Calendar {
    /// 某个月有多少天：按公历（用户日历）算，28/29/30/31 都可能。
    /// 不用「默认 30 天」这种兜底——天数算错会直接体现为柱状图少画几天、覆盖率偏大。
    func dayCount(inMonthOf date: Date) -> Int {
        if let range = range(of: .day, in: .month, for: date), range.count > 0 {
            return range.count
        }
        if let interval = dateInterval(of: .month, for: date) {
            let days = dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
            if days > 0 { return days }
        }
        return 1
    }
}
