import CryptoKit
import Foundation

/// 跨设备稳定的 ID：同一个 code 在任何设备上算出同一个 UUID。
///
/// CloudKit 不支持唯一约束，去重靠「同一条记录」；分类与账户种子没有自定义，
/// 所以由 code 推导 ID，两台设备各自建出来的种子会被 CloudKit 合并成一条。
enum StableID {
    static func category(_ code: String) -> UUID { make("spendge.category.\(code)") }
    static func account(_ code: String) -> UUID { make("spendge.account.\(code)") }

    private static func make(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        // RFC 4122 版本位与变体位，让它是一个合法的 v5 风格 UUID
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let text = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: text)!
    }
}
