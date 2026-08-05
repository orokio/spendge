import Foundation
import SwiftData

/// 账户业务逻辑：查询、增改、归档、删除、余额与总资产。
@MainActor
final class AccountService {
    private let context: ModelContext
    private let transactionService: TransactionService

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.transactionService = TransactionService(context: context, calendar: calendar)
    }

    func accounts(includeArchived: Bool = false) throws -> [Account] {
        var predicate: Predicate<Account>?
        if !includeArchived {
            predicate = #Predicate { $0.isArchived == false }
        }
        var descriptor = FetchDescriptor<Account>(predicate: predicate)
        descriptor.sortBy = [
            SortDescriptor(\.sortOrder),
            SortDescriptor(\.name),
        ]
        return try context.fetch(descriptor)
    }

    @discardableResult
    func create(
        name: String,
        iconName: String = "wallet.pass.fill",
        colorHex: String = "#3B82F6",
        kind: AccountKind = .other,
        initialBalanceCents: Int64 = 0,
        sortOrder: Int = 0
    ) throws -> Account {
        let account = Account(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            kind: kind,
            initialBalanceCents: initialBalanceCents,
            sortOrder: sortOrder
        )
        context.insert(account)
        try context.save()
        return account
    }

    func update(
        _ account: Account,
        name: String? = nil,
        iconName: String? = nil,
        colorHex: String? = nil,
        kind: AccountKind? = nil,
        initialBalanceCents: Int64? = nil,
        sortOrder: Int? = nil
    ) throws {
        if let name { account.name = name }
        if let iconName { account.iconName = iconName }
        if let colorHex { account.colorHex = colorHex }
        if let kind { account.kind = kind }
        if let initialBalanceCents { account.initialBalanceCents = initialBalanceCents }
        if let sortOrder { account.sortOrder = sortOrder }
        account.updatedAt = .now
        try context.save()
    }

    /// 归档：余额仍计入总资产，但不再出现在默认选择列表。
    func archive(_ account: Account) throws {
        account.isArchived = true
        account.updatedAt = .now
        try context.save()
    }

    /// 删除：存在账单的账户不允许删除（避免误删历史数据）。
    func delete(_ account: Account) throws {
        let txns = try transactionService.transactions(account: account)
        guard txns.isEmpty else { throw SpendgeError.accountHasTransactions }
        context.delete(account)
        try context.save()
    }

    /// 账户当前余额（分）。
    func balanceCents(for account: Account) throws -> Int64 {
        try transactionService.balanceCents(for: account)
    }

    /// 全部账户余额之和（分）。
    func totalAssetsCents(includeArchived: Bool = false) throws -> Int64 {
        var total: Int64 = 0
        for account in try accounts(includeArchived: includeArchived) {
            total += try balanceCents(for: account)
        }
        return total
    }
}
