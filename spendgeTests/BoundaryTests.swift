import SwiftData
import XCTest
@testable import spendge

/// 边界：跨年、闰月、空库、金额与备注上限、未来日期。
@MainActor
final class BoundaryTests: XCTestCase {
    // MARK: - 跨年

    func testDecemberAndJanuaryDoNotLeakIntoEachOther() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)

        try service.add(amountCents: 1111, kind: .expense, date: TestStore.day(2025, 12, 31, hour: 23), category: category, account: account)
        try service.add(amountCents: 2222, kind: .expense, date: TestStore.day(2026, 1, 1, hour: 0), category: category, account: account)

        let december = try service.summary(forMonth: 2025, month: 12)
        let january = try service.summary(forMonth: 2026, month: 1)

        XCTAssertEqual(december.totalExpenseCents, 1111)
        XCTAssertEqual(january.totalExpenseCents, 2222)
        XCTAssertEqual(december.totalExpenseCents + january.totalExpenseCents, 3333)
    }

    func testNewYearsEveMidnightBoundary() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)
        try service.add(amountCents: 999, kind: .expense, date: TestStore.day(2026, 1, 1, hour: 0), category: category, account: account)

        XCTAssertEqual(try service.summary(forMonth: 2025, month: 12).totalExpenseCents, 0)
        XCTAssertEqual(try service.summary(forMonth: 2026, month: 1).totalExpenseCents, 999)
    }

    // MARK: - 闰月

    func testLeapFebruaryCoverage() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)
        try service.add(amountCents: 500, kind: .expense, date: TestStore.day(2024, 2, 29), category: category, account: account)

        let coverage = try service.coverage(forMonth: 2024, month: 2)
        XCTAssertEqual(coverage.daysInMonth, 29)
        XCTAssertEqual(coverage.daysWithRecords, 1)
        XCTAssertEqual(coverage.coveredDays, 1)
    }

    func testNonLeapFebruaryRejects29thRecordInMarch() throws {
        TestStore.reset()
        // 2025-02-29 不存在，Calendar 会把它归一化到 3 月 1 日：不该算进 2 月
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)
        try service.add(amountCents: 700, kind: .expense, date: TestStore.day(2025, 2, 28), category: category, account: account)

        let coverage = try service.coverage(forMonth: 2025, month: 2)
        XCTAssertEqual(coverage.daysInMonth, 28)
        XCTAssertEqual(coverage.daysWithRecords, 1)
    }

    // MARK: - 空库

    func testEmptyStoreSummaryAndCoverage() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let summary = try service.summary(forMonth: 2026, month: 1)
        XCTAssertEqual(summary.totalExpenseCents, 0)
        XCTAssertEqual(summary.totalIncomeCents, 0)
        XCTAssertTrue(summary.expenseByCategory.isEmpty)

        let coverage = try service.coverage(forMonth: 2026, month: 1)
        XCTAssertEqual(coverage.coveredDays, 0)
        XCTAssertEqual(coverage.ratio, 0)
        XCTAssertFalse(coverage.ratio.isNaN)
    }

    // MARK: - 金额与备注

    func testAmountUpperBound() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)

        XCTAssertNoThrow(try service.add(amountCents: InputLimits.amountCentsMax, kind: .expense,
                                         date: .now, category: category, account: account))
        assertSpendgeError("单笔金额不能超过 ¥9999999") {
            try service.add(amountCents: InputLimits.amountCentsMax + 1, kind: .expense,
                            date: .now, category: category, account: account)
        }
        assertSpendgeError("金额必须大于 0") {
            try service.add(amountCents: 0, kind: .expense, date: .now, category: category, account: account)
        }
        assertSpendgeError("金额必须大于 0") {
            try service.add(amountCents: -1, kind: .expense, date: .now, category: category, account: account)
        }
    }

    func testNoteLengthBoundary() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)
        let exact = String(repeating: "字", count: InputLimits.noteLength)

        XCTAssertNoThrow(try service.add(amountCents: 100, kind: .expense, date: .now,
                                         note: exact, category: category, account: account))
        assertSpendgeError("备注最多 100 个字") {
            try service.add(amountCents: 100, kind: .expense, date: .now,
                            note: exact + "多", category: category, account: account)
        }
    }

    // MARK: - 日期

    func testFutureDateIsRejectedButTodayIsNot() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)
        let calendar = Calendar.current
        let todayLate = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now

        XCTAssertNoThrow(try service.add(amountCents: 100, kind: .expense, date: todayLate,
                                         category: category, account: account))
        assertSpendgeError("不能记录未来的日期") {
            try service.add(amountCents: 100, kind: .expense, date: tomorrow, category: category, account: account)
        }
    }

    // MARK: - 断言工具

    private func assertSpendgeError(_ expected: String, file: StaticString = #filePath, line: UInt = #line,
                                    _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard let spendge = error as? SpendgeError else {
                return XCTFail("错误类型不对：\(error)", file: file, line: line)
            }
            XCTAssertEqual(spendge.errorDescription, expected, file: file, line: line)
        }
    }
}
