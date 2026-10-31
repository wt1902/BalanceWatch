import SwiftData
import SwiftUI

@main
struct BalanceWatchApp: App {
    private let containers = LedgerContainers()
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage(LedgerSelection.scopeKey) private var ledgerScope = ""

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .id(ledgerScope)
                .tint(BalancePalette.accent)
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .modelContainer(containers.container(for: ledgerScope))
        }
    }
}
