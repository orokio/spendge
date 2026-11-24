import Foundation

/// 服务端地址：从 Info.plist 的 ServerBaseURL 读取；为空表示还没部署，客户端不做任何网络请求。
enum ServerConfig {
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ServerBaseURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    static var isConfigured: Bool { baseURL != nil }
}
