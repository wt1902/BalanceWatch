import SwiftData
import SwiftUI

@main
struct BalanceWatchApp: App {
    private let modelContainer = BalanceModelContainer.make()
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .tint(.indigo)
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
        }
        .modelContainer(modelContainer)
    }
}
