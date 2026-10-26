import SwiftUI
import UIKit
import Observation
import LocalAuthentication
import LedgerCore

/// Блокировка по Face ID (запасной вариант: код-пароль iPhone) и заглушка в переключателе приложений.
/// Рисуется в отдельном окне поверх всего, чтобы закрывать и открытые шторки. Данные не трогает:
/// команда «СМС банка», автокопия и вечерняя сводка работают и при заблокированном экране.
@MainActor @Observable final class AppLock {
    static let shared = AppLock()

    private(set) var enabled: Bool
    private(set) var isLocked: Bool
    /// Приложение не на экране (переключатель приложений, Пункт управления): суммы закрыты заглушкой.
    private(set) var covered = false
    private(set) var authenticating = false

    private enum Keys { static let enabled = "lock.enabled" }
    private let ud = UserDefaults.standard
    private var backgroundedAt: Date?
    /// Face ID сам предлагаем один раз на каждую блокировку, дальше только по кнопке: иначе отмена зациклится.
    private var autoPrompted = false
    private var window: UIWindow?

    private init() {
        enabled = ud.bool(forKey: Keys.enabled)
        isLocked = AppLockPolicy.shouldLockOnLaunch(enabled: ud.bool(forKey: Keys.enabled))
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.resignActive() }
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.enterBackground() }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.enterForeground() }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.becomeActive() }
        }
    }

    /// Создаёт окно поверх сцены. Вызывается, когда интерфейс появился.
    func attach() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.overrideUserInterfaceStyle = .dark
        let host = UIHostingController(rootView: AppLockOverlay())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        window = w
        update()
        if UIApplication.shared.applicationState == .active { becomeActive() }
    }

    // MARK: Настройка

    /// Включение подтверждаем Face ID сразу, чтобы убедиться, что он работает. Ошибку возвращаем для показа.
    func setEnabled(_ on: Bool) async -> String? {
        guard on != enabled else { return nil }
        if on {
            var error: NSError?
            guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                return String(localized: "lock.unavailable")
            }
            guard await authenticate() else { return nil }
        }
        enabled = on
        ud.set(on, forKey: Keys.enabled)
        return nil
    }

    // MARK: Разблокировка

    func unlock() {
        Task {
            // Код-пароль на устройстве убрали: Face ID тоже недоступен, иначе экран не открыть никогда.
            var error: NSError?
            if !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error),
               (error as? LAError)?.code == .passcodeNotSet {
                isLocked = false; update(); return
            }
            if await authenticate() { isLocked = false; update() }
        }
    }

    private func authenticate() async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        update()
        defer { authenticating = false; update() }
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "lock.reason"))) ?? false
    }

    // MARK: Жизненный цикл

    private func resignActive() {
        // Окно Face ID тоже уводит приложение в неактивное состояние: заглушку тогда не показываем.
        if !authenticating { covered = true; update() }
    }

    private func enterBackground() {
        covered = true
        backgroundedAt = .now
        update()
    }

    private func enterForeground() {
        if AppLockPolicy.shouldLockOnReturn(enabled: enabled, backgroundedAt: backgroundedAt, now: .now), !isLocked {
            isLocked = true
            autoPrompted = false
        }
        backgroundedAt = nil
        update()
    }

    private func becomeActive() {
        covered = false
        update()
        if isLocked, !autoPrompted, window != nil {
            autoPrompted = true
            unlock()
        }
    }

    private func update() {
        window?.isHidden = !(isLocked || covered)
    }
}

/// То, что рисуется в окне блокировки: экран с кнопкой или просто заглушка.
private struct AppLockOverlay: View {
    @Bindable private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("AppLogo").resizable().scaledToFit().frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                if lock.isLocked {
                    Text("lock.title").font(.app(.title3, .semibold))
                    Button { lock.unlock() } label: {
                        Label("lock.unlock", systemImage: "faceid")
                            .font(.app(.headline))
                            .padding(.horizontal, 28).padding(.vertical, 14)
                            .background(Theme.brand, in: Capsule())
                            .foregroundStyle(Theme.onBrand)
                    }
                    .disabled(lock.authenticating)
                    .padding(.top, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Переключатель в настройках.
struct AppLockSettingsSection: View {
    private var lock = AppLock.shared
    @State private var error: String?

    var body: some View {
        Section {
            Toggle("lock.toggle", isOn: Binding(
                get: { lock.enabled },
                set: { on in Task { error = await lock.setEnabled(on) } }
            ))
            .disabled(lock.authenticating)
        } footer: { Text("lock.footer") }
        .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("common.ok") {}
        }
    }
}
