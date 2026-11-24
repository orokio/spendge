import Foundation

/// 设备登记：每次启动向 `/v1/devices/register` 上报一次 deviceId。
///
/// - 每次启动都报，服务端按 deviceId 幂等更新 last_seen 与版本号
/// - 失败：不打扰用户，下次启动重试
/// - 没配 ServerBaseURL：什么都不做
enum DeviceRegistrar {
    static func registerIfNeeded() async {
        // 隐私同意前不上报
        guard PrivacyConsent.canStartSDK else { return }
        guard let baseURL = ServerConfig.baseURL else { return }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices/register"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "deviceId": IdentityService.deviceId,
            "appVersion": (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "",
            "build": (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "",
            "platform": "ios",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // 下次启动再试
        }
    }
}
