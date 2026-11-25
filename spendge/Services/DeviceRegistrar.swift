import Foundation
import os

/// 设备登记：每次启动向 `/v1/devices/register` 上报一次 deviceId。
///
/// - 每次启动都报，服务端按 deviceId 幂等更新 last_seen 与版本号
/// - 失败：不打扰用户，下次启动重试
/// - 没配 ServerBaseURL：什么都不做
enum DeviceRegistrar {
    private static let logger = Logger(subsystem: "com.orokio.spendge", category: "register")

    /// 首次签发才返回明文 token；之后的滑动续期不带
    struct RegisterResponse: Decodable {
        let deviceToken: String?
        let categoriesVersion: Int?
        let categories: [RemoteCategory]?
    }

    struct RemoteCategory: Decodable {
        let code: String
        let name: String
        let iconName: String?
        let colorHex: String?
        let kindRawValue: String?
        let domainRawValue: String?
        let scope: String?
        let sortOrder: Int?
        let isArchived: Bool?
        let goalKinds: [String]?

        var categoryInfo: CategoryInfo {
            CategoryInfo(code: code,
                         name: name,
                         iconName: iconName ?? "tag.fill",
                         colorHex: colorHex ?? "#9CA3AF",
                         kindRawValue: kindRawValue ?? TransactionKind.expense.rawValue,
                         domainRawValue: domainRawValue ?? CategoryDomain.other.rawValue,
                         scope: scope ?? "",
                         sortOrder: sortOrder ?? 99,
                         isArchived: isArchived ?? false,
                         goalKinds: goalKinds ?? [])
        }
    }

    static func registerIfNeeded() async {
        // 隐私同意前不上报
        guard PrivacyConsent.canStartSDK else { return }
        guard let baseURL = ServerConfig.baseURL else { return }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices/register"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 已有 token 时带上，服务端据此滑动续期
        if let token = IdentityService.deviceToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let knownVersion = await MainActor.run { CategoryCatalog.shared.version }
        let body: [String: Any] = [
            "deviceId": IdentityService.deviceId,
            "deviceSecret": IdentityService.deviceSecret,
            "appVersion": (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "",
            "build": (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "",
            "platform": "ios",
            "categoriesVersion": knownVersion,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 服务端签发设备 token，存 Keychain；M4 的接口用它鉴权
            if let payload = try? JSONDecoder().decode(RegisterResponse.self, from: data) {
                if let token = payload.deviceToken {
                    IdentityService.deviceToken = token
                }
                if (200...299).contains(status),
                   let version = payload.categoriesVersion,
                   version > knownVersion,
                   let remote = payload.categories,
                   !remote.isEmpty {
                    let items = remote.map(\.categoryInfo)
                    await MainActor.run {
                        CategoryCatalog.shared.apply(version: version, categories: items)
                    }
                }
            }
            logger.notice("register status=\(status, privacy: .public)")
        } catch {
            // 下次启动再试
            logger.notice("register failed: \(String(describing: error), privacy: .public)")
        }
    }
}
