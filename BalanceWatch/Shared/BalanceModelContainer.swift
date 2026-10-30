import Foundation
import SwiftData

enum BalanceModelContainer {
    static let schema = Schema([
        FinanceTransaction.self,
        MonthlyBudget.self,
        CustomCategory.self,
        SyncTombstone.self
    ])

    static func make() -> ModelContainer {
        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [localConfiguration]
            )
        } catch {
            let recoveryConfiguration = ModelConfiguration(
                "BalanceRecovery",
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
