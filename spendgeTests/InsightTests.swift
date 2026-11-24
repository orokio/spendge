import SwiftData
import XCTest
@testable import spendge

/// 情绪句按「当天最新一笔」判断；退款单独说，且不计入外卖次数与目标计数。
@MainActor
final class InsightTests: XCTestCase {
    private func makeExpense(_ code: CategoryCode, cents: Int64 = 3000) throws -> Transaction {
        try TransactionService(context: TestStore.context).add(
            amountCents: cents,
            kind: .expense,
            date: .now,
            category: try TestStore.category(code),
            account: try TestStore.account()
        )
    }

    func testRefundOnlySaysMoneyBack() throws {
        TestStore.reset()
        let original = try makeExpense(.takeout)
        try TransactionService(context: TestStore.context).addRefund(for: original)

        let insight = try InsightService(context: TestStore.context).headline()
        XCTAssertEqual(insight.title, "钱退回来了")
        XCTAssertEqual(insight.detail, "那笔不算花")
    }

    func testRefundIsNotCountedAsTakeout() throws {
        TestStore.reset()
        let original = try makeExpense(.takeout)
        try TransactionService(context: TestStore.context).addRefund(for: original)
        // 再来一笔咖啡，让最新一笔不是退款；今天真正的外卖只有 1 次，退款不补一顿
        _ = try makeExpense(.drink, cents: 1800)

        let insight = try InsightService(context: TestStore.context).headline()
        XCTAssertNotEqual(insight.title, "第 2 顿外卖")
        XCTAssertNotEqual(insight.title, "钱退回来了")
    }

    func testNewestRecordDecidesTheSentence() throws {
        TestStore.reset()
        let original = try makeExpense(.takeout)
        try TransactionService(context: TestStore.context).addRefund(for: original)
        _ = try makeExpense(.drink, cents: 1800)

        let insight = try InsightService(context: TestStore.context).headline()
        XCTAssertNotEqual(insight.title, "钱退回来了")
        XCTAssertNotEqual(insight.title, "今天还空着")
    }

    func testCountGoalIgnoresRefunds() throws {
        TestStore.reset()
        let goalService = GoalService(context: TestStore.context)
        let goal = try goalService.create(
            title: "外卖不超过 5 次",
            kind: .countLimit,
            categoryCodes: [CategoryCode.takeout.rawValue],
            period: .month,
            targetValue: 5
        )

        let takeout = try makeExpense(.takeout)
        try TransactionService(context: TestStore.context).addRefund(for: takeout)

        // 原单算一次，退款不算
        XCTAssertEqual(try goalService.progress(for: goal).current, 1)
    }
}
