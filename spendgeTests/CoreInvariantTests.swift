import SwiftData
import XCTest
@testable import spendge

// 核心不变量的回归用例：种子、汇总、覆盖率、语音解析、奖杯。
// 这些断言原先写在 App 内的 SelfCheck 里，2026-11-24 迁到这里后 SelfCheck 已删除。

// MARK: - 1. 种子完整性

@MainActor
final class SeedTests: XCTestCase {
    func testExpenseCategoryCountIs25() throws {
        TestStore.reset()
        let categories = try CategoryService(context: TestStore.context).categories()
        XCTAssertEqual(categories.filter { $0.kind == .expense }.count, 25)
    }

    func testEveryCategoryHasCode() throws {
        TestStore.reset()
        let categories = try CategoryService(context: TestStore.context).categories()
        XCTAssertTrue(categories.allSatisfy { $0.categoryCode != nil })
    }

    func testOnlyOtherExpenseHasEmptyScope() throws {
        TestStore.reset()
        let categories = try CategoryService(context: TestStore.context).categories()
        XCTAssertTrue(categories.allSatisfy { $0.scope.isEmpty == ($0.categoryCode == .otherExpense) })
    }

    func testFoodDomainHasSixCategories() throws {
        TestStore.reset()
        let categories = try CategoryService(context: TestStore.context).categories()
        let food = categories.filter { $0.kind == .expense && $0.domain == .food }
        XCTAssertEqual(food.count, 6)
    }

    func testSalaryCategoryExists() throws {
        TestStore.reset()
        let categories = try CategoryService(context: TestStore.context).categories()
        XCTAssertTrue(categories.contains { $0.categoryCode == .salary })
    }
}

// MARK: - 2. 金额快填

@MainActor
final class RecentAmountTests: XCTestCase {
    func testRecentAmountsAreUniqueAndAtMostThree() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let category = try TestStore.category(.takeout)
        let now = Date.now
        for cents in [1000, 1000, 2000, 3000] {
            try service.add(amountCents: Int64(cents), kind: .expense, date: now, category: category, account: account)
        }

        let recent = try service.recentAmounts()
        XCTAssertLessThanOrEqual(recent.count, 3)
        XCTAssertEqual(Set(recent).count, recent.count)
    }
}

// MARK: - 3. 覆盖率

@MainActor
final class CoverageTests: XCTestCase {
    func testCoverageStaysWithinBounds() throws {
        TestStore.reset()
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: .now)
        let coverage = try TransactionService(context: TestStore.context)
            .coverage(forMonth: comps.year ?? 2026, month: comps.month ?? 1)
        XCTAssertGreaterThanOrEqual(coverage.ratio, 0)
        XCTAssertLessThanOrEqual(coverage.ratio, 1)
        XCTAssertLessThanOrEqual(coverage.coveredDays, coverage.daysInMonth)
    }
}

// MARK: - 3a. 导出与备份

@MainActor
final class BackupExportTests: XCTestCase {
    func testCSVHasBOMAndHeader() throws {
        TestStore.reset()
        let csv = try BackupService(context: TestStore.context).csv(scope: .all)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}日期,类型,分类,金额,备注"))
    }

    func testBackupContainsEverythingAndPassesValidation() throws {
        TestStore.reset()
        let service = BackupService(context: TestStore.context)
        let transactions = TransactionService(context: TestStore.context)
        try transactions.add(amountCents: 1200, kind: .expense, category: TestStore.category(.takeout), account: try TestStore.account())

        let data = try service.backupData()
        let decoded = try service.decodeBackup(data)
        XCTAssertEqual(decoded.transactions.count, try transactions.transactions(from: nil, to: nil).count)
        XCTAssertGreaterThan(decoded.categories.count, 0)
        XCTAssertNoThrow(try service.validate(decoded))
    }
}

// MARK: - 3a2. 目标进度与区间

@MainActor
final class GoalProgressTests: XCTestCase {
    func testCountLimitProgress() {
        let progress = GoalProgress(current: 3, target: 4, unit: .count, isAtMost: true, period: .month)
        XCTAssertTrue(progress.isReached)
        XCTAssertEqual(progress.remaining, 1)
    }

    func testCountMinimumProgress() {
        let progress = GoalProgress(current: 2, target: 3, unit: .count, isAtMost: false, period: .month)
        XCTAssertFalse(progress.isReached)
        XCTAssertEqual(progress.remaining, 1)
    }

    func testPeriodRanges() throws {
        TestStore.reset()
        let service = GoalService(context: TestStore.context)
        let month = try service.periodRange(.month)
        XCTAssertEqual(Calendar.current.component(.day, from: month.start), 1)

        let monthRange = try service.periodRange(.month)
        let days = Calendar.current.dateComponents([.day], from: monthRange.start, to: monthRange.end).day ?? 0
        XCTAssertGreaterThanOrEqual(days, 28)
    }
}

// MARK: - 3b. 月份天数

@MainActor
final class CalendarDayCountTests: XCTestCase {
    func testMonthLengths() {
        let calendar = Calendar.current
        XCTAssertEqual(calendar.dayCount(inMonthOf: TestStore.day(2028, 2, 1)), 29)
        XCTAssertEqual(calendar.dayCount(inMonthOf: TestStore.day(2026, 2, 1)), 28)
        XCTAssertEqual(calendar.dayCount(inMonthOf: TestStore.day(2026, 4, 1)), 30)
        XCTAssertEqual(calendar.dayCount(inMonthOf: TestStore.day(2026, 10, 1)), 31)
    }
}

// MARK: - 4. 汇总与明细一致

@MainActor
final class SummaryTests: XCTestCase {
    func testMonthlySummaryEqualsDetailTotal() throws {
        TestStore.reset()
        let service = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        let takeout = try TestStore.category(.takeout)
        let salary = try TestStore.category(.salary)

        try service.add(amountCents: 1200, kind: .expense, date: .now, category: takeout, account: account)
        try service.add(amountCents: 800, kind: .expense, date: .now, category: takeout, account: account)
        try service.add(amountCents: 500000, kind: .income, date: .now, category: salary, account: account)

        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: .now)
        let summary = try service.summary(forMonth: comps.year ?? 2026, month: comps.month ?? 1)
        let detailTotal = try service.transactions(from: nil, to: nil)
            .filter { $0.kind == .expense }
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(into: Int64(0)) { $0 += $1.amountCents }

        XCTAssertEqual(summary.totalExpenseCents, detailTotal)
        XCTAssertEqual(summary.totalExpenseCents, 2000)
        XCTAssertEqual(summary.totalIncomeCents, 500000)
        XCTAssertEqual(summary.netCents, 498000)
    }
}

// MARK: - 5. 总资产

@MainActor
final class AssetTests: XCTestCase {
    func testTotalAssetsEqualsSumOfBalances() throws {
        TestStore.reset()
        let accountService = AccountService(context: TestStore.context)
        let transactionService = TransactionService(context: TestStore.context)
        let account = try TestStore.account()
        try transactionService.add(amountCents: 3000, kind: .expense, date: .now,
                                   category: TestStore.category(.takeout), account: account)
        _ = try accountService.create(name: "银行卡", kind: .debitCard, initialBalanceCents: 100000)

        let accounts = try accountService.accounts()
        XCTAssertFalse(accounts.isEmpty)
        let expected = accounts.reduce(into: Int64(0)) { total, item in
            total += (try? transactionService.balanceCents(for: item)) ?? 0
        }
        XCTAssertEqual(try accountService.totalAssetsCents(), expected)
    }
}

// MARK: - 语音与分类匹配

final class VoiceParserTests: XCTestCase {
    func testParsesCategoryAndAmount() {
        XCTAssertEqual(VoiceParser.parse("外卖三十").categoryCode, .takeout)
        XCTAssertEqual(VoiceParser.parse("外卖三十").yuan, 30)
        XCTAssertEqual(VoiceParser.parse("打车25块").yuan, 25)
        XCTAssertEqual(VoiceParser.parse("打车25块").categoryCode, .outing)
        XCTAssertTrue(VoiceParser.parse("随便说点什么").isEmpty)
        XCTAssertEqual(VoiceParser.parse("买了个充电宝50").categoryCode, .digitalGear)
        XCTAssertEqual(VoiceParser.parse("给车充电30").categoryCode, .fuel)
        XCTAssertEqual(VoiceParser.parse("外卖３０").yuan, 30)
        XCTAssertNil(VoiceParser.parse("买了苹果12").categoryCode)
        XCTAssertFalse(VoiceParser.parse("买了苹果12").hasMoneyCue)
        XCTAssertTrue(VoiceParser.parse("花了50").hasMoneyCue)
        XCTAssertEqual(VoiceParser.parse("今天买了一瓶香水500块").yuan, 500)
        XCTAssertEqual(VoiceParser.parse("一杯咖啡30").yuan, 30)
    }
}

@MainActor
final class CategoryMatcherTests: XCTestCase {
    func testMatchesByScope() throws {
        TestStore.reset()
        let categories = try CategoryService(context: TestStore.context).categories()
        XCTAssertEqual(CategoryMatcher.match("PS Plus 会员", in: categories, kind: .expense)?.categoryCode, .subscription)
        XCTAssertEqual(CategoryMatcher.match("买了瓶啤酒", in: categories, kind: .expense)?.categoryCode, .alcoholBeverage)
        XCTAssertEqual(CategoryMatcher.match("高铁票200", in: categories, kind: .expense)?.categoryCode, .travel)
    }
}

// MARK: - 6. 奖杯

@MainActor
final class TrophyTests: XCTestCase {
    func testCatalogShape() {
        XCTAssertEqual(TrophyCatalog.all.count, 30)
        XCTAssertEqual(Set(TrophyCatalog.all.map(\.id)).count, 30)
        XCTAssertEqual(TrophyCatalog.all.filter { $0.rarity == .common }.count, 16)
        XCTAssertEqual(TrophyCatalog.all.filter { $0.rarity == .rare }.count, 8)
        XCTAssertEqual(TrophyCatalog.all.filter { $0.rarity == .legendary }.count, 6)
        XCTAssertTrue(TrophySeries.allCases.allSatisfy { series in
            TrophyCatalog.all.contains { $0.series == series }
        })
    }

    func testProgressTextHasUnit() {
        XCTAssertEqual(TrophyProgress(current: 2, target: 5, unit: .days).remainingText, "还差 3 天")
    }

    func testSnapshotCoversEveryTrophy() {
        TestStore.reset()
        let snapshot = AchievementService(context: TestStore.context).snapshot()
        XCTAssertEqual(snapshot.states.count, 30)
        XCTAssertLessThanOrEqual(snapshot.unlockedCount, 30)
    }
}
