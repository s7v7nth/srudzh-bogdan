import SwiftUI
import SwiftData

/// Общие для приложения и команд Shortcuts база и курсы: команда выполняется в том же процессе и должна писать в ту же базу.
@MainActor enum AppStore {
    static let rates = RatesStore()
    /// Ошибка вместо базы, если её не удалось открыть: тогда показываем экран с объяснением, а не вылетаем.
    static let opened: Result<ModelContainer, Error> = Result { try ModelContainer(for: Seed.schema) }.map(prepare)

    private static func prepare(_ c: ModelContainer) -> ModelContainer {
        Seed.run(c.mainContext)
        #if DEBUG
        DemoData.runIfRequested(c.mainContext, rates: rates)
        #endif
        AutoBackup.shared.start(container: c, rates: rates)
        EveningNotifier.shared.start(container: c, rates: rates)
        #if DEBUG
        // -backupFolder <путь>: папка для копий без окна выбора (для проверки в симуляторе).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-backupFolder"), i + 1 < args.count {
            try? AutoBackup.shared.setFolder(URL(fileURLWithPath: args[i + 1], isDirectory: true))
        }
        #endif
        return c
    }
}

@main
struct SrudzhBogdanApp: App {
    init() { AppFont.setUp() }

    var body: some Scene {
        WindowGroup {
            Group {
                switch AppStore.opened {
                case .success(let container):
                    RootView()
                        .environment(AppStore.rates)
                        .onAppear { AppLock.shared.attach() }
                        .task {
                            await AppStore.rates.refreshIfNeeded()
                        }
                        .modelContainer(container)
                case .failure(let error):
                    StoreErrorView(error: error)
                }
            }
            .preferredColorScheme(.dark)
            .font(.app(.body))
            .tint(Theme.accent)
        }
    }
}

/// База не открылась. Данные на месте, просто эта версия приложения не смогла их прочитать.
private struct StoreErrorView: View {
    let error: Error
    var body: some View {
        ContentUnavailableView {
            Label("storeError.title", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("storeError.hint")
            Text(verbatim: error.localizedDescription).font(.app(.caption)).foregroundStyle(.secondary)
        }
    }
}
