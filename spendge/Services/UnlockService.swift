import Foundation

/// 解锁（一次性买断）的入口。
/// 现在只有提示与开发期模拟；StoreKit 等开发者账号开通后接在这里。
@MainActor
enum UnlockService {
    static let priceText = "¥18"

    static let benefits = [
        "目标数量不限，想设几个设几个",
        "完整历史回看，不只看近 3 个月",
        "iCloud 多设备同步，换手机不丢",
    ]

    /// 用户确认解锁：走 StoreKit 非消耗型内购
    static func purchase() {
        Task { _ = await StoreService.shared.purchase() }
    }
}
