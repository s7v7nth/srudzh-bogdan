import SwiftUI
import SwiftData

/// Общие для приложения и команд Shortcuts база и курсы: команда выполняется в том же процессе и должна писать в ту же базу.
@MainActor enum AppStore {
    static let rates = RatesStore()
    static let container: ModelContainer = {
        let c = try! ModelContainer(for: Seed.schema)
        Seed.run(c.mainContext)
        #if DEBUG
        DemoData.runIfRequested(c.mainContext, rates: rates)
        #endif
        return c
    }()
}

@main
struct SrudzhBogdanApp: App {
    init() { AppFont.setUp() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .font(.app(.body))
                .tint(Theme.accent)
                .environment(AppStore.rates)
                .task {
                    await AppStore.rates.refreshIfNeeded()
                }
        }
        .modelContainer(AppStore.container)
    }
}
