import SwiftData
import XCTest
@testable import spendge

/// 备份往返：导出 → 校验 → 恢复 → 再查，以及各类损坏备份必须被拒。
@MainActor
final class BackupRoundTripTests: XCTestCase {
    private func service() -> BackupService { BackupService(context: TestStore.context) }

    private func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// 造三笔支出 + 一笔收入，返回 (导出数据, 账单数, 支出合计)
    private func seededBackup() throws -> (data: Data, count: Int, expenseTotal: Int64) {
        TestStore.reset()
        let transactions = TransactionService(context: TestStore.context)
        let takeout = try TestStore.category(.takeout)
        let salary = try TestStore.category(.salary)

        try transactions.add(amountCents: 1200, kind: .expense, date: TestStore.day(2026, 11, 3), category: takeout)
        try transactions.add(amountCents: 800, kind: .expense, date: TestStore.day(2026, 11, 5), note: "早饭", category: takeout)
        try transactions.add(amountCents: 300, kind: .expense, date: TestStore.day(2026, 10, 31), category: takeout)
        try transactions.add(amountCents: 500000, kind: .income, date: TestStore.day(2026, 11, 1), category: salary)

        let data = try service().backupData()
        return (data, 4, 2300)
    }

    // MARK: - 往返

    func testRoundTripPreservesTransactions() throws {
        let seed = try seededBackup()
        let file = try service().validateBackupData(seed.data)
        let codesBefore = Set(file.transactions.compactMap(\.categoryCode))

        let restored = try service().restore(from: seed.data)
        XCTAssertEqual(restored, seed.count)

        let transactions = TransactionService(context: TestStore.context)
        let rows = try transactions.transactions(from: nil, to: nil)
        XCTAssertEqual(rows.count, seed.count)
        XCTAssertEqual(rows.filter { $0.kind == .expense }.reduce(into: Int64(0)) { $0 += $1.amountCents },
                       seed.expenseTotal)
        XCTAssertEqual(rows.filter { $0.kind == .income }.reduce(into: Int64(0)) { $0 += $1.amountCents },
                       500000)
        XCTAssertEqual(rows.filter { $0.note == "早饭" }.count, 1)

        let codesAfter = Set(rows.compactMap(\.categoryCode))
        XCTAssertEqual(codesAfter, codesBefore)
    }

    func testRoundTripKeepsValidationPassing() throws {
        let seed = try seededBackup()
        _ = try service().restore(from: seed.data)
        let exportedAgain = try service().backupData()
        XCTAssertNoThrow(try service().validateBackupData(exportedAgain))
    }

    // MARK: - 拒绝损坏备份

    private func assertRejected(_ expected: String, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body()) { error in
            guard let validation = error as? BackupValidationError else {
                return XCTFail("错误类型不对：\(error)")
            }
            XCTAssertEqual(validation.errorDescription, expected)
        }
    }

    func testRejectsUnsupportedVersion() throws {
        let seed = try seededBackup()
        var file = try service().decodeBackup(seed.data)
        file.version = 99
        assertRejected("备份文件版本不受支持") { try service().validate(file) }
    }



    func testDeduplicatesDuplicateTransactionIDs() throws {
        let seed = try seededBackup()
        var file = try service().decodeBackup(seed.data)
        file.transactions.append(file.transactions[0])
        let restored = try service().restore(from: try encode(file))
        XCTAssertEqual(restored, seed.count)
    }



    func testRestoresLegacyCategorySumAsBudget() throws {
        let seed = try seededBackup()
        var file = try service().decodeBackup(seed.data)
        let oldID = UUID()
        let legacy = Goal(id: oldID,
                          title: "奶茶咖啡 100 元",
                          kind: .budget,
                          categoryCodes: ["drink"],
                          period: .month,
                          targetValue: 10000)
        legacy.kindRawValue = "categorySum"
        file.goals = [GoalDTO(legacy)]
        _ = try service().restore(from: try encode(file))
        let goals = try TestStore.context.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(goals.first(where: { $0.id == oldID })?.kind, .budget)
    }

    func testRejectsFutureTransactionDate() throws {
        let seed = try seededBackup()
        var file = try service().decodeBackup(seed.data)
        file.transactions[0].date = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        assertRejected("备份文件里的账单日期不合法") { try service().validate(file) }
    }

    func testRejectsDuplicateDayConfirmation() throws {
        let seed = try seededBackup()
        var file = try service().decodeBackup(seed.data)
        let day = TestStore.day(2026, 11, 7)
        file.dayConfirmations = [
            DayConfirmationDTO(DayConfirmation(day: day)),
            DayConfirmationDTO(DayConfirmation(day: day))
        ]
        assertRejected("备份文件里有重复的没花钱确认") { try service().validate(file) }
    }

    /// 奖杯目录以后可能改，未知奖杯不该让整份备份作废
    func testUnknownTrophyIsSkipped() throws {
        let seed = try seededBackup()
        let object = try JSONSerialization.jsonObject(with: seed.data)
        var root = object as? [String: Any] ?? [:]
        root["trophies"] = [["trophyID": "futureTrophy", "unlockedAt": "2026-01-01T00:00:00Z"]]
        let patched = try JSONSerialization.data(withJSONObject: root)
        XCTAssertNoThrow(try service().validateBackupData(patched))
    }

    /// 校验失败时不能先清库
    func testFailedRestoreKeepsExistingData() throws {
        let seed = try seededBackup()
        var file = try service().decodeBackup(seed.data)
        file.version = 99
        let broken = try encode(file)

        XCTAssertThrowsError(try service().restore(from: broken))
        let remaining = try TransactionService(context: TestStore.context).transactions(from: nil, to: nil)
        XCTAssertEqual(remaining.count, seed.count)
    }
}
