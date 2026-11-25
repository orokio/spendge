import CloudKit
import Combine
import CoreData
import Foundation

enum CloudSyncPreference {
    static let enabledKey = "sync.icloudEnabled"
    static let lastSuccessKey = "sync.lastSuccessAt"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

extension Notification.Name {
    /// 同步开关变化：App 根部据此重建 ModelContainer
    static let cloudSyncPreferenceChanged = Notification.Name("spendge.cloudSyncPreferenceChanged")
    /// 远端导入完成：@Query 需要一次手动 fetch 才会刷新
    static let cloudDataImported = Notification.Name("spendge.cloudDataImported")
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
            // 系统错误文案是英文，界面上只给中文
            errorText = "同步失败，请稍后重试"
            status = .unavailable("同步失败")
        }
    }
}
