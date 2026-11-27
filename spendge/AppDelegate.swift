import SwiftData
import UIKit

/// 只为 CloudKit 静默推送服务：注册远程通知后，SwiftData 底层的
/// NSPersistentCloudKitContainer 会自己处理 token 与推送，不需要解析 payload。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Bugly 要求尽早在 didFinishLaunching 里启动；隐私未同意时它自己会跳过
        CrashReporter.startIfAuthorized()
        PushSync.registerIfNeeded()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        LaunchTrace.mark("push.registered")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LaunchTrace.mark("push.failed")
    }

    /// 静默推送本身由 Core Data 消费；这里只把后台抓取标记为有新数据
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }
}

enum PushSync {
    /// 只在同步真正可用时注册；关闭同步或未买断时不打扰系统
    @MainActor
    static func registerIfNeeded() {
        guard CloudSyncPreference.isEnabled else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }
}
