import SwiftUI
import SwiftData

/// Следит, чтобы правки попадали на диск сразу, а не когда система сама решит сохранить.
/// Без этого новая операция могла жить только в памяти, пока приложение не свернут: при сбое она бы пропала,
/// а автокопия и общие цифры о ней не знали. Если запись не удалась, человек видит сообщение.
@MainActor @Observable final class SaveGuard {
    static let shared = SaveGuard()

    /// Показать сообщение о неудачной записи. Показывается один раз, пока запись снова не пройдёт.
    var showError = false
    @ObservationIgnored private var failing = false
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var timer: Timer?

    func start(_ ctx: ModelContext) {
        guard context == nil else { return }
        context = ctx
        // Проверка дешёвая: смотрим только, есть ли несохранённые правки. Во время прокрутки таймер ждёт,
        // поэтому запись не мешает листать.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { SaveGuard.shared.saveNow() }
        }
    }

    /// Сохраняет сразу, если есть что сохранять.
    func saveNow() {
        guard let ctx = context, ctx.hasChanges else { return }
        do {
            try ctx.save()
            failing = false
        } catch {
            #if DEBUG
            print("save failed: \(error)")
            #endif
            // Правки остаются в памяти, следующая проверка попробует ещё раз.
            if !failing { failing = true; showError = true }
        }
    }
}
