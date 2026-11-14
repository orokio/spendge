import Foundation
import SwiftData

/// 「今天不花钱」的确认操作。
/// 一键就能完成——这个动作同时支撑零花费日目标和数据覆盖率。
@MainActor
final class DayConfirmationService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// 某天是否已确认无支出。
    func isConfirmed(_ date: Date) throws -> Bool {
        try confirmation(on: date) != nil
    }

    func confirmation(on date: Date) throws -> DayConfirmation? {
        let range = try dayRange(date)
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<DayConfirmation>(
            predicate: #Predicate { $0.day >= start && $0.day < end }
        )
        return try context.fetch(descriptor).first
    }

    /// 幂等：同一天重复确认不会产生多条记录。
    @discardableResult
    func confirmNoSpend(on date: Date = .now) throws -> DayConfirmation {
        if let existing = try confirmation(on: date) { return existing }
        let item = DayConfirmation(day: calendar.startOfDay(for: date))
        context.insert(item)
        try context.save()
        return item
    }

    func remove(on date: Date) throws {
        guard let existing = try confirmation(on: date) else { return }
        context.delete(existing)
        try context.save()
    }

    private func dayRange(_ date: Date) throws -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw SpendgeError.invalidDate
        }
        return (start, end)
    }
}
