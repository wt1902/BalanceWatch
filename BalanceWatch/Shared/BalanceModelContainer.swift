import Foundation
import SwiftData

enum BalanceModelContainer {
    static let schema = Schema([
        FinanceTransaction.self,
        MonthlyBudget.self,
        CustomCategory.self,
        SyncTombstone.self,
        FinanceAccount.self,
        FinanceTransfer.self,
        ExchangeRate.self,
        SyncRecord.self
    ])

    /// `scope` пустой — личные данные (прежнее хранилище по умолчанию);
    /// иначе — отдельное хранилище общего пространства (сервер + пользователь + ledger).
    static func make(scope: String = "") -> ModelContainer {
        let localConfiguration = scope.isEmpty
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            : ModelConfiguration("BalanceLedger-\(scope)", schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)

        do {
            return try ModelContainer(
                for: schema,
                configurations: [localConfiguration]
            )
        } catch {
            let recoveryConfiguration = ModelConfiguration(
                scope.isEmpty ? "BalanceRecovery" : "BalanceRecovery-\(scope)",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )

            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [recoveryConfiguration]
                )
            } catch {
                fatalError("Не удалось создать хранилище Balance: \(error.localizedDescription)")
            }
        }
    }
}

/// Кеш контейнеров по пространствам: переключение туда-обратно не
/// открывает хранилище заново.
@MainActor
final class LedgerContainers {
    private var items: [String: ModelContainer] = [:]

    func container(for scope: String) -> ModelContainer {
        if let item = items[scope] { return item }
        let item = BalanceModelContainer.make(scope: scope)
        items[scope] = item
        return item
    }
}
