import Foundation

enum PrivacyConsent {
    /// 隐私政策版本：内容变更时加一，下次启动重新询问
    static let version = 4

    static var isGranted: Bool {
        UserDefaults.standard.string(forKey: PreferenceKey.privacyChoice) == "granted"
    }

    /// 当前版本已经做过选择（同意或拒绝都算）
    static var hasDecision: Bool {
        UserDefaults.standard.integer(forKey: PreferenceKey.privacyVersionSeen) >= version
    }

    static var canStartSDK: Bool { isGranted && hasDecision }
}

#if canImport(Bugly)
import Bugly

/// Bugly 崩溃上报。只有用户同意隐私政策且配置了 AppId 才启动。
enum CrashReporter {
    private static var started = false

    static var isConfigured: Bool {
        guard let appId = Bundle.main.object(forInfoDictionaryKey: "BuglyAppId") as? String else {
            return false
        }
        return !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func startIfAuthorized() {
        guard PrivacyConsent.canStartSDK, isConfigured, !started,
              let appId = Bundle.main.object(forInfoDictionaryKey: "BuglyAppId") as? String else {
            return
        }

        let appKey = (Bundle.main.object(forInfoDictionaryKey: "BuglyAppKey") as? String) ?? ""
        let config = BuglyConfig(appId: appId, appKey: appKey)
        config.debugMode = false
        config.userIdentifier = IdentityService.deviceId

        // 只保留崩溃所需的最小采集，其余按官方示例关闭
        config.setEnableCpuInfo(false)
        config.setEnableDiskSpace(false)
        config.setEnableFreeMemory(false)
        config.setEnableCountryCode(false)
        config.setEnableDeviceModel(false)
        config.setEnableNetworkType(false)
        config.setEnableProcessMemory(false)
        config.setEnableSystemVersion(false)
        config.setEnableJailbreakStatus(false)
        config.setEnableSystemVersionCode(false)

        Bugly.start(with: config)
        started = true
    }

}
#else
/// 没放 Bugly.xcframework 时保持可编译，功能为空。
enum CrashReporter {
    static var isConfigured: Bool { false }
    static func startIfAuthorized() {}
}
#endif
