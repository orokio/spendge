import Combine
import StoreKit
import SwiftUI

/// 一次性买断（非消耗型内购）。v1 只有一个商品，成功后写本地能力层。
@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()
    /// 必须与 App Store Connect 里创建的内购 Product ID 一致
    static let productID = "com.orokio.spendge.lifetime"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isUnlocked = Entitlements.isUnlocked
    @Published private(set) var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    /// StoreKit 会给「¥18.00」，界面沿用设计里的整数写法
    var displayPrice: String {
        let raw = product?.displayPrice ?? UnlockService.priceText
        return raw.hasSuffix(".00") ? String(raw.dropLast(3)) : raw
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    func loadProduct() async {
        #if DEBUG
        if let storefront = await Storefront.current {
            print("[Store] storefront:", storefront.countryCode)
        }
        #endif
        do {
            product = try await Product.products(for: [Self.productID]).first
            #if DEBUG
            print("[Store] product:", product?.id ?? "nil", product?.displayPrice ?? "nil")
            #endif
            if product == nil { errorMessage = "商品还没上架" }
        } catch {
            errorMessage = "无法获取商品信息"
        }
    }

    /// 返回是否已解锁；用户取消不算错误
    func purchase() async -> Bool {
        if product == nil { await loadProduct() }
        guard let product else {
            errorMessage = errorMessage ?? "商品暂不可用"
            return false
        }
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "购买校验失败，请稍后重试"
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isUnlocked
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "购买正在等待批准"
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    #if DEBUG
    /// 开发者面板切换付费状态：界面读的是 isUnlocked，必须和 Entitlements 同步改
    func debugSetUnlocked(_ value: Bool) {
        isUnlocked = value
        Entitlements.isUnlocked = value
    }
    #endif

    /// 系统错误一律翻成中文，不把 StoreKit 的英文原文抛给用户
    private func friendlyMessage(for error: Error) -> String {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .userCancelled: return "已取消"
            case .networkError: return "网络不太稳定，请稍后重试"
            case .notAvailableInStorefront: return "当前地区暂不支持购买"
            case .notEntitled: return "当前账户没有购买权限"
            case .systemError: return "系统繁忙，请稍后重试"
            case .unknown: return "没有成功，请再试一次"
            @unknown default: return "没有成功，请再试一次"
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "网络不太稳定，请稍后重试"
        }
        return "没有成功，请再试一次"
    }

    /// 恢复购买（换机、家人共享、重装）
    func restore() async -> Bool {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
        await refreshEntitlements()
        if !isUnlocked { errorMessage = "没有可恢复的购买" }
        return isUnlocked
    }

    /// 以 StoreKit 的有效交易为准：有就解锁，没有（含退款/撤销）就回到免费。
    /// 非消耗型的内购凭据在本地，离线时 currentEntitlements 仍能返回，不需要额外缓存兜底。
    func refreshEntitlements() async {
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            active = true
        }

        let newValue = active
        guard newValue != isUnlocked else { return }
        isUnlocked = newValue
        Entitlements.isUnlocked = newValue
        // iCloud 是买断能力，权限变化后让容器按新权限重建
        NotificationCenter.default.post(name: .cloudSyncPreferenceChanged, object: nil)
    }
}
