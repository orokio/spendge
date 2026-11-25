import SwiftData
import XCTest
@testable import spendge

/// 退款：全额、一条、负数支出、与原单双向联动、删除级联。
@MainActor
final class RefundTests: XCTestCase {
    private func makeExpense(cents: Int64 = 3000) throws -> Transaction {
        try TransactionService(context: TestStore.context).add(
            amountCents: cents,
            kind: .expense,
            date: .now,
            category: try TestStore.category(.takeout)
        )
    }

    func testRefundCreatesLinkedNegativeRecord() throws {
        TestStore.reset()
        let original = try makeExpense()
        let service = TransactionService(context: TestStore.context)

        let refund = try service.addRefund(for: original)

        XCTAssertEqual(refund.amountCents, -3000)
        XCTAssertEqual(refund.kind, .expense)
        XCTAssertEqual(refund.refundOfID, original.id)
        XCTAssertEqual(refund.category?.categoryCode, .takeout)
        XCTAssertEqual(try service.refundRecord(of: original)?.id, refund.id)
    }

    func testSecondRefundIsRejected() throws {
        TestStore.reset()
        let original = try makeExpense()
        let service = TransactionService(context: TestStore.context)
        try service.addRefund(for: original)

        XCTAssertThrowsError(try service.addRefund(for: original)) { error in
            XCTAssertEqual((error as? SpendgeError)?.errorDescription, "这笔账单已经退过款")
        }
    }

    func testIncomeCannotBeRefunded() throws {
        TestStore.reset()
        let income = try TransactionService(context: TestStore.context).add(
            amountCents: 500000,
            kind: .income,
            date: .now,
            category: try TestStore.category(.salary)
        )

        XCTAssertThrowsError(try TransactionService(context: TestStore.context).addRefund(for: income)) { error in
            XCTAssertEqual((error as? SpendgeError)?.errorDescription, "这笔账单不能退款")
        }
    }

    func testEditingOriginalSyncsRefundAmountAndCategory() throws {
        TestStore.reset()
        let original = try makeExpense()
        let service = TransactionService(context: TestStore.context)
        let refund = try service.addRefund(for: original)

        try service.update(original, amountCents: 4500, category: try TestStore.category(.snack))

        XCTAssertEqual(refund.amountCents, -4500)
        XCTAssertEqual(refund.category?.categoryCode, .snack)
    }

    func testEditingRefundSyncsOriginal() throws {
        TestStore.reset()
        let original = try makeExpense()
        let service = TransactionService(context: TestStore.context)
        let refund = try service.addRefund(for: original)

        // 退款页按正数编辑
        try service.update(refund, amountCents: 2000, category: try TestStore.category(.drink))

        XCTAssertEqual(refund.amountCents, -2000)
        XCTAssertEqual(original.amountCents, 2000)
        XCTAssertEqual(original.category?.categoryCode, .drink)
    }

    func testDeletingOriginalRemovesRefund() throws {
        TestStore.reset()
        let original = try makeExpense()
        let service = TransactionService(context: TestStore.context)
        let refund = try service.addRefund(for: original)
        let refundID = refund.id

        try service.delete(original)

        let remaining = try service.transactions(from: nil, to: nil)
        XCTAssertFalse(remaining.contains { $0.id == refundID })
        XCTAssertTrue(remaining.isEmpty)
    }

    func testMonthlySummaryNetsRefund() throws {
        TestStore.reset()
        _ = try makeExpense(cents: 3000)
        let original = try makeExpense(cents: 2000)
        let service = TransactionService(context: TestStore.context)
        try service.addRefund(for: original)

        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: .now)
        let summary = try service.summary(forMonth: comps.year ?? 2026, month: comps.month ?? 1)

        XCTAssertEqual(summary.totalExpenseCents, 3000)
    }

    func testBackupKeepsRefundLink() throws {
        TestStore.reset()
        let original = try makeExpense()
        let service = TransactionService(context: TestStore.context)
        let refund = try service.addRefund(for: original)
        let backup = BackupService(context: TestStore.context)

        let data = try backup.backupData()
        let file = try backup.validateBackupData(data)

        let refundDTO = file.transactions.first { $0.id == refund.id }
        XCTAssertEqual(refundDTO?.refundOfID, original.id)
        XCTAssertEqual(refundDTO?.amountCents, -3000)
    }
}
