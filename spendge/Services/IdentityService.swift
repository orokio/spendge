import Foundation
import Security

/// 设备标识：首次启动生成 UUID，存 Keychain（重装不丢）。
///
/// v1 只做这一项。M4 账号体系上线时，服务端按这个 deviceId 把历史和日志回填到新建的 accountId，
/// 客户端不需要迁移，也不需要现在登录。
enum IdentityService {
    private static let service = "com.orokio.spendge.identity"
    private static let account = "deviceId"

    /// 稳定的设备标识；并发调用也只会生成一次
    static let deviceId: String = {
        if let existing = readFromKeychain(), !existing.isEmpty {
            return existing
        }
        // 老版本把安装标识存在 UserDefaults，迁移进 Keychain，Bugly 的归组不会断
        if let legacy = UserDefaults.standard.string(forKey: PreferenceKey.installID), !legacy.isEmpty {
            writeToKeychain(legacy)
            return legacy
        }
        let value = UUID().uuidString
        writeToKeychain(value)
        return value
    }()

    // MARK: - Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readFromKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeToKeychain(_ value: String) {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var insert = baseQuery()
        insert.merge(attributes) { _, new in new }
        SecItemAdd(insert as CFDictionary, nil)
    }
}
