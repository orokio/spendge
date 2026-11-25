import CloudKit
import Combine
import CoreData
import Foundation

enum CloudSyncPreference {
    static let enabledKey = "sync.icloudEnabled"
    static let lastSuccessKey = "sync.lastSuccessAt"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

extension Notification.Name {
    /// 同步开关变化：App 根部据此重建 ModelContainer
    static let cloudSyncPreferenceChanged = Notification.Name("spendge.cloudSyncPreferenceChanged")
    /// 远端导入完成：@Query 需要一次手动 fetch 才会刷新
    static let cloudDataImported = Notification.Name("spendge.cloudDataImported")
    /// 用户主动重新同步：App 根部关掉同步重建一次容器，再开回来触发全量导入
    static let cloudSyncResyncRequested = Notification.Name("spendge.cloudSyncResyncRequested")
}

/// iCloud 同步状态：账号是否可用、当前是否在同步、上次成功时间与失败原因。
/// 事件来自 NSPersistentCloudKitContainer，SwiftData 底层就是它。
@MainActor
final class CloudSyncMonitor: ObservableObject {
    /// 全局一份：设置页不可见时也要能收到后台同步事件，否则「上次同步」会停在旧时间
    static let shared = CloudSyncMonitor()
    enum Status: Equatable {
        case off
        case checking
        case idle
        case syncing
        case unavailable(String)
    }

    @Published private(set) var status: Status = .checking
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var errorText: String?
    /// 重建容器期间界面显示「重建中」，不重复触发
    @Published private(set) var isResyncing = false

    private var observer: NSObjectProtocol?

    private init() {
        lastSuccess = UserDefaults.standard.object(forKey: CloudSyncPreference.lastSuccessKey) as? Date
        if !CloudSyncPreference.isEnabled { status = .off }
    }

    func start() {
        guard CloudSyncPreference.isEnabled else {
            status = .off
            return
        }
        status = .checking
        observeEvents()
        Task { await refresh() }
    }

    /// 同步卡上的「重新同步」：关掉同步重建容器，隔几秒再开回来
    func resync() {
        guard !isResyncing else { return }
        isResyncing = true
        NotificationCenter.default.post(name: .cloudSyncResyncRequested, object: nil)
    }

    /// App 根部两次重建都完成后调用
    func finishResync() {
        isResyncing = false
        errorText = nil
        status = .checking
        Task { await refresh() }
    }

    #if DEBUG
    /// 开发者面板：把同步卡置成失败态，用来验证「重新同步」入口
    func debugSimulateFailure() {
        errorText = "同步失败，请稍后重试"
        status = .unavailable("同步失败")
    }
    #endif

    /// 开关切换后立即接管状态，不用等页面重新出现
    func applyPreferenceChange() {
        if CloudSyncPreference.isEnabled {
            start()
        } else {
            stop()
            errorText = nil
            status = .off
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// 重新读账号状态；失败原因一并清掉，等待下一次同步事件
    func refresh() async {
        guard CloudSyncPreference.isEnabled else {
            status = .off
            return
        }
        errorText = nil
        #if targetEnvironment(simulator)
        status = .unavailable("模拟器不启用 iCloud")
        #else
        status = .checking
        do {
            switch try await CKContainer.default().accountStatus() {
            case .available: status = .idle
            case .noAccount: status = .unavailable("未登录 iCloud")
            case .restricted: status = .unavailable("iCloud 受限")
            case .couldNotDetermine: status = .unavailable("无法确认 iCloud 状态")
            case .temporarilyUnavailable: status = .unavailable("iCloud 暂时不可用")
            @unknown default: status = .unavailable("iCloud 不可用")
            }
        } catch {
            status = .unavailable("无法确认 iCloud 状态")
        }
        #endif
    }

    private func observeEvents() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in self?.handle(event) }
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard let endDate = event.endDate else {
            status = .syncing
            return
        }
        if event.succeeded {
            errorText = nil
            lastSuccess = endDate
            UserDefaults.standard.set(endDate, forKey: CloudSyncPreference.lastSuccessKey)
            status = .idle
            // @Query 不会因远端导入自动刷新，通知根部手动 fetch 一次
            if event.type == .import {
                NotificationCenter.default.post(name: .cloudDataImported, object: nil)
            }
        } else {
            errorText = failureText(for: event.error)
            status = .unavailable("同步失败")
        }
    }

    /// 系统错误文案是英文，界面上按错误类型给中文短句；兜底带上错误码方便排查
    private func failureText(for error: Error?) -> String {
        guard let error = error as? CKError else { return "同步失败，请稍后重试" }
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return "网络连接不可用"
        case .notAuthenticated:
            return "未登录 iCloud"
        case .quotaExceeded:
            return "iCloud 空间不足"
        case .changeTokenExpired, .zoneNotFound:
            return "同步数据已过期，点「重新同步」"
        case .serverRecordChanged:
            return "记录冲突，正在重试"
        case .requestRateLimited:
            return "请求过于频繁，请稍后重试"
        case .partialFailure:
            return "部分数据同步失败"
        default:
            return "同步失败，请稍后重试（\(error.code.rawValue)）"
        }
    }
}
