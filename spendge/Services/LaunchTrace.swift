import Foundation
import os

/// 启动路径打点。
///
/// - DEBUG：print 到 Xcode 控制台，带相对耗时
/// - Release：写 os_log，用 Console.app 或以后的 MetricKit 读
///
/// 测启动时记得先关掉 Scheme 的 Debug executable 与 Main Thread Checker，
/// 否则数字会被放大几十倍。
@MainActor
enum LaunchTrace {
    static let start = ProcessInfo.processInfo.systemUptime
    private static let logger = Logger(subsystem: "com.orokio.spendge", category: "launch")
    private static var seen: Set<String> = []

    static func mark(_ name: String) {
        #if DEBUG
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        print(String(format: "[launch] %@ +%.1fms", name, elapsed))
        #else
        logger.notice("\(name, privacy: .public)")
        #endif
    }

    /// 同一次启动只打一次，避免 body 反复求值刷屏
    static func once(_ name: String) {
        guard !seen.contains(name) else { return }
        seen.insert(name)
        mark(name)
    }
}
