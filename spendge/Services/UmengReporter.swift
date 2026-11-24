import Foundation
import UMCommon

/// 友盟移动统计：只在用户同意隐私政策后初始化，事件只带代码类属性。
@MainActor
enum UmengReporter {
    private static var started = false

    private static var appKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "UMAppKey") as? String
        return (key?.isEmpty == false) ? key : nil
    }

    static var isConfigured: Bool { appKey != nil }

    static func startIfAuthorized() {
        guard PrivacyConsent.canStartSDK, let appKey, !started else { return }
        #if DEBUG
        // 验证期打开 SDK 日志；Release 关闭，避免把内部信息打进线上日志
        UMConfigure.setLogEnabled(true)
        #else
        UMConfigure.setLogEnabled(false)
        #endif
        UMConfigure.initWithAppkey(appKey, channel: "App Store")
        started = true
        #if DEBUG
        print("[umeng] init " + appKey)
        #endif
    }

    static func track(_ event: String, _ params: [String: String]) {
        guard started else {
            #if DEBUG
            print("[umeng] skip \(event)：SDK 还没初始化")
            #endif
            return
        }
        MobClick.event(event, attributes: params)
        #if DEBUG
        print("[umeng] event \(event) \(params)")
        #endif
    }
}
