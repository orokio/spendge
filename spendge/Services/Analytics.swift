import Foundation
import os

/// 最小埋点：只落本地，不联网。
///
/// 两个出口：os_log（Console.app / 以后接 MetricKit）与本地滚动文件（设置里可导出）。
/// 只记录事件名、代码类属性和错误码；不写金额原文、不写备注内容。
@MainActor
enum Analytics {
    enum Event: String {
        case appLaunch = "app_launch"
        case recordSaved = "record_saved"
        case recordFailed = "record_failed"
        case noSpend = "no_spend_mark"
        case onboarding = "onboarding"
        case goalCreated = "goal_created"
        case reviewOpened = "review_opened"
        case backup = "backup"
        case settingsOpened = "settings_opened"
    }

    /// 金额只记档位，不记具体数值
    static func amountBand(cents: Int64) -> String {
        switch cents {
        case ..<10_000: return "lt_100"
        case ..<50_000: return "100_500"
        case ..<200_000: return "500_2000"
        default: return "gt_2000"
        }
    }

    static func durationBand(milliseconds: Int) -> String {
        switch milliseconds {
        case ..<200: return "lt_200"
        case ..<500: return "200_500"
        case ..<1000: return "500_1000"
        default: return "gt_1000"
        }
    }

    static func errorCode(_ error: Error) -> String {
        guard let spendge = error as? SpendgeError else {
            return String(describing: type(of: error))
        }
        return spendge.analyticsCode
    }

    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("diagnostics.log")
    }()

    private static let logger = Logger(subsystem: "com.orokio.spendge", category: "analytics")
    private static let maxBytes = 1_000_000
    private static let keepDays = 7
    private static let keepLines = 3000

    static func record(_ event: Event, _ params: [String: String] = [:]) {
        let detail = params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "\(timestamp()) \(event.rawValue)\(detail.isEmpty ? "" : " " + detail)"
        logger.notice("\(line, privacy: .public)")
        append(line)
        UmengReporter.track(event.rawValue, params)
    }

    // MARK: - 本地文件

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: .now)
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        if let size = try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > maxBytes {
            rotate()
        }

        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 超过 1MB 时裁掉 7 天前的行，再保留最后 3000 行
    private static func rotate() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: .now) ?? .now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let kept = text
            .split(separator: "\n")
            .filter { line in
                guard let token = line.split(separator: " ").first,
                      let date = formatter.date(from: String(token)) else { return false }
                return date >= cutoff
            }
            .suffix(keepLines)

        let rebuilt = kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")
        try? rebuilt.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

extension SpendgeError {
    var analyticsCode: String {
        switch self {
        case .invalidAmount: return "invalid_amount"
        case .invalidDate: return "invalid_date"
        case .accountHasTransactions: return "account_has_transactions"
        case .cannotDeleteSystemCategory: return "system_category"
        case .amountTooLarge: return "amount_too_large"
        case .futureDate: return "future_date"
        case .noteTooLong: return "note_too_long"
        case .goalTitleTooLong: return "goal_title_too_long"
        case .invalidGoalTarget: return "invalid_goal_target"
        case .injectedFailure: return "injected"
        }
    }
}
