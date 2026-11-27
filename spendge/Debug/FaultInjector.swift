import Foundation

/// 可注入的故障点。业务层只认识「这一步可能失败」，不关心调试开关。
enum FaultPoint: String, CaseIterable, Identifiable {
    case transactionWrite
    case goalWrite
    case budgetWrite
    case dayConfirmationWrite
    case shareExport
    case cloudSync
    case parseRequest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transactionWrite: return "账单写入"
        case .goalWrite: return "目标写入"
        case .budgetWrite: return "预算写入"
        case .dayConfirmationWrite: return "没花钱"
        case .shareExport: return "分享图片"
        case .cloudSync: return "iCloud 同步"
        case .parseRequest: return "云端解析"
        }
    }

    /// 「全部写入失败」批量开关覆盖的点
    var isWrite: Bool {
        switch self {
        case .transactionWrite, .goalWrite, .budgetWrite, .dayConfirmationWrite:
            return true
        case .shareExport, .cloudSync, .parseRequest:
            return false
        }
    }
}

enum DebugKeys {
    static let unlocked = "debug.unlocked"
    static let recentlyDeletedEntry = "debug.recentlyDeletedEntry"
    static func fault(_ point: FaultPoint) -> String { "debug.fault.\(point.rawValue)" }
}

protocol FaultInjector {
    func check(_ point: FaultPoint) throws
}

struct NoFaultInjector: FaultInjector {
    func check(_ point: FaultPoint) throws {}
}

enum FaultInjection {
    static var current: FaultInjector {
        #if DEBUG
        return DebugFaultInjector()
        #else
        return NoFaultInjector()
        #endif
    }
}

#if DEBUG
/// 读取开发者面板里的开关；只有打开的故障点才抛错。
struct DebugFaultInjector: FaultInjector {
    func check(_ point: FaultPoint) throws {
        if UserDefaults.standard.bool(forKey: DebugKeys.fault(point)) {
            throw SpendgeError.injectedFailure(point)
        }
    }
}
#endif
