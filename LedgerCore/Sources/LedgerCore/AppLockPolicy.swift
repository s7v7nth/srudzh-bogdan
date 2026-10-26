import Foundation

/// Когда снова спрашивать Face ID. Решение: короткая отлучка (меньше 30 секунд, например ответить на сообщение)
/// не блокирует, ровно 30 секунд и больше блокирует. Если часы устройства ушли назад, блокируем: так безопаснее.
public enum AppLockPolicy {
    public static let defaultGrace: TimeInterval = 30

    /// Нужен ли экран блокировки при возврате из фона. `backgroundedAt == nil` значит, что ухода в фон не было.
    public static func shouldLockOnReturn(enabled: Bool, backgroundedAt: Date?, now: Date, grace: TimeInterval = defaultGrace) -> Bool {
        guard enabled, let t = backgroundedAt else { return false }
        let away = now.timeIntervalSince(t)
        return away < 0 || away >= grace
    }

    /// При запуске приложения с нуля блокируем всегда, если блокировка включена.
    public static func shouldLockOnLaunch(enabled: Bool) -> Bool { enabled }
}
