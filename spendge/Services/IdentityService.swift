import Foundation
import Security

/// 设备标识：首次启动生成 UUID，存 Keychain（重装不丢）。
///
/// v1 只做这一项。M4 账号体系上线时，服务端按这个 deviceId 把历史和日志回填到新建的 accountId，
/// 客户端不需要迁移，也不需要现在登录。
enum IdentityService {
    private static let service = "com.orokio.spendge.identity"
    private static let deviceAccount = "deviceId"
    private static let tokenAccount = "deviceToken"
    private static let secretAccount = "deviceSecret"

    /// 稳定的设备标识；并发调用也只会生成一次
    static let deviceId: String = {
        if let existing = read(account: deviceAccount), !existing.isEmpty {
            return existing
        }
        // 老版本把安装标识存在 UserDefaults，迁移进 Keychain，Bugly 的归组不会断
        if let legacy = UserDefaults.standard.string(forKey: PreferenceKey.installID), !legacy.isEmpty {
            write(legacy, account: deviceAccount)
            return legacy
        }
        let value = UUID().uuidString
        write(value, account: deviceAccount)
        return value
    }()

    /// 服务端签发的设备 token；register 成功后写入，没有就为空
    static var deviceToken: String? {
        get {
            guard let value = read(account: tokenAccount), !value.isEmpty else { return nil }
            return value
        }
        set {
            guard let newValue, !newValue.isEmpty else { return }
            write(newValue, account: tokenAccount)
        }
    }

    /// 设备密钥：首次启动生成，register 时随请求带上；服务端只存哈希。
    /// 仅知道 deviceId 不足以获取 token，这是没有 App Attest 时的最低凭证。
    static let deviceSecret: String = {
        if let existing = read(account: secretAccount), !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = Array(UUID().uuidString.utf8)
        }
        let value = Data(bytes).base64EncodedString()
        write(value, account: secretAccount)
        return value
    }()

    // MARK: - Keychain

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var insert = baseQuery(account: account)
        insert.merge(attributes) { _, new in new }
        SecItemAdd(insert as CFDictionary, nil)
    }
}
