#if DEBUG
import Foundation
import SwiftData

/// 开发期只读自检：跑一遍核心不变量，结果写 Documents/selfcheck.log。
///
/// 只读的原因：SwiftData 里同时存在两个指向同一组 Model 的 ModelContainer 会 trap，
/// 所以不能另开内存容器；写真实库又会污染演示数据。写路径的正确性靠手动试用覆盖。
@MainActor
enum SelfCheck {
    static func run(context: ModelContext) {
        var passed = 0
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() { passed += 1 } else { failures.append(name) }
        }

        let categoryService = CategoryService(context: context)
        let transactionService = TransactionService(context: context)
        let accountService = AccountService(context: context)

        // 1. 种子完整性
        let categories = (try? categoryService.categories()) ?? []
        let expenses = categories.filter { $0.kind == .expense }
        expect(expenses.count == 15, "种子应有 15 个支出分类，实际 \(expenses.count)")
        expect(categories.allSatisfy { $0.categoryCode != nil }, "每个分类都应有 code")
        expect(expenses.filter { $0.domain == .food }.count == 5, "吃的领域应有 5 个分类")
        expect(categories.contains { $0.categoryCode == .salary }, "应有工资分类")

        // 2. 金额建议随方差分层（纯函数，不依赖库里的历史）
        let lowVariance = AmountSuggestion.make(from: [3_000, 2_500, 2_500, 2_500])
        expect(lowVariance.style == .mode, "低方差应使用众数预填")
        expect(lowVariance.prefillCents == 2_500, "众数应取出现最多的金额")

        let highVariance = AmountSuggestion.make(from: [2_000, 10_000, 18_000, 26_000])
        expect(highVariance.style == .bucketsOnly, "高方差应只给档位")
        expect(highVariance.prefillCents == nil, "高方差分类不得预填历史值")
        expect(!highVariance.chips.isEmpty, "档位不应为空")
        expect(AmountSuggestion.make(from: [2_000, 3_000]).style == .none, "样本不足时不应预填")

        // 3. 覆盖率自洽
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: .now)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        if let coverage = try? transactionService.coverage(forMonth: year, month: month) {
            expect(coverage.ratio >= 0 && coverage.ratio <= 1, "覆盖率应在 0–1 之间")
            expect(coverage.coveredDays <= coverage.daysInMonth, "覆盖天数不应超过当月天数")
        }

        // 4. 汇总与明细一致
        if let summary = try? transactionService.summary(forMonth: year, month: month) {
            let detailTotal = ((try? transactionService.transactions(from: nil, to: nil)) ?? [])
                .filter { $0.kind == .expense }
                .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
                .reduce(into: Int64(0)) { $0 += $1.amountCents }
            expect(summary.totalExpenseCents == detailTotal, "月度汇总应与明细合计一致")
        }

        // 5. 总资产等于各账户余额之和
        if let accounts = try? accountService.accounts(), !accounts.isEmpty {
            let expected = accounts.reduce(into: Int64(0)) { partial, account in
                partial += (try? transactionService.balanceCents(for: account)) ?? 0
            }
            expect((try? accountService.totalAssetsCents()) == expected, "总资产应等于各账户余额之和")
        }

        // 语音文本解析：只认高置信度的组合
        expect(VoiceParser.parse("外卖三十").categoryCode == .takeout, "语音应识别出外卖")
        expect(VoiceParser.parse("外卖三十").yuan == 30, "语音应识别出中文金额")
        expect(VoiceParser.parse("打车25块").yuan == 25, "语音应识别出阿拉伯数字金额")
        expect(VoiceParser.parse("打车25块").categoryCode == .outing, "语音应识别出出行")
        expect(VoiceParser.parse("随便说点什么").isEmpty, "没有把握时不应猜分类或金额")

        report(passed: passed, failures: failures)
    }

    private static func report(passed: Int, failures: [String]) {
        var lines: [String] = []
        if failures.isEmpty {
            lines.append("[SelfCheck] 通过 \(passed) 项")
        } else {
            lines.append("[SelfCheck] 通过 \(passed) 项，失败 \(failures.count) 项")
            for failure in failures { lines.append("[SelfCheck] FAIL: \(failure)") }
        }
        let text = lines.joined(separator: "\n") + "\n"
        print(text, terminator: "")
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? text.write(to: directory.appending(path: "selfcheck.log"), atomically: true, encoding: .utf8)
        }
    }
}
#endif
