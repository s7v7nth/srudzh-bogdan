import Foundation
import Observation
import SwiftData
import UserNotifications
import LedgerCore

/// Вечерняя сводка: одно уведомление в выбранное время. Новых уведомлений после трат нет,
/// после каждого изменения базы молча переписывается текст уже запланированных.
/// Нажатие открывает приложение, а RootView сам показывает разбор СМС, если он нужен.
@MainActor @Observable final class EveningNotifier {
    static let shared = EveningNotifier()

    /// На сколько дней вперёд ставить сводки: если приложение неделю не открывать, они всё равно придут.
    private static let daysAhead = 7
    private static let idPrefix = "digest."

    var enabled: Bool { didSet { ud.set(enabled, forKey: Keys.enabled); reschedule() } }
    /// Время в минутах от полуночи.
    var minutes: Int { didSet { ud.set(minutes, forKey: Keys.minutes); reschedule() } }
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private enum Keys { static let enabled = "digest.enabled", minutes = "digest.minutes" }
    private let ud = UserDefaults.standard
    private var context: ModelContext?
    private var rates: RatesStore?
    private var pending: Task<Void, Never>?

    private init() {
        enabled = ud.object(forKey: Keys.enabled) as? Bool ?? true
        minutes = ud.object(forKey: Keys.minutes) as? Int ?? 21 * 60
    }

    func start(container: ModelContainer, rates: RatesStore) {
        guard context == nil else { return }
        context = container.mainContext
        self.rates = rates
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { EveningNotifier.shared.reschedule(delay: .seconds(1)) }
        }
        Task { await refreshAuthorization(); reschedule() }
    }

    /// Применяет настройки из резервной копии.
    func apply(enabled: Bool?, minutes: Int?) {
        if let minutes { self.minutes = minutes }
        if let enabled { self.enabled = enabled }
    }

    // MARK: Разрешение

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Системный вопрос про уведомления. Задаётся один раз, дальше только через настройки iPhone.
    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
        reschedule()
    }

    // MARK: Расписание

    func reschedule(delay: Duration = .zero) {
        pending?.cancel()
        pending = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await scheduleNow()
        }
    }

    /// Переписывает сводки на неделю вперёд. Команда «СМС банка» зовёт это сразу, не дожидаясь паузы.
    func scheduleNow() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard enabled, let ctx = context, let rates, !rates.base.isEmpty else { return }
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }

        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let base = rates.base
        let spentToday = Self.spentToday(ctx: ctx, rates: rates, from: today)
        let pendingSMS = (try? ctx.fetchCount(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.smsReview != 0 }))) ?? 0
        let budget = Self.monthlyBudget(ctx: ctx, rates: rates)
        let alerts = Self.budgetAlerts(ctx: ctx, rates: rates, skip: budget?.overall)
        let payments = Self.upcomingPayments(ctx: ctx, rates: rates, until: cal.date(byAdding: .day, value: Self.daysAhead + 2, to: today)!)

        for offset in 0..<Self.daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let fire = cal.date(byAdding: .minute, value: minutes, to: day), fire > now else { continue }
            // Будущие дни считаем так, будто трат больше не будет: появится трата, и всё пересчитается.
            let sameMonth = cal.isDate(day, equalTo: now, toGranularity: .month)
            let left = budget.map { sameMonth ? $0.left : $0.limit }
            let tomorrow = cal.date(byAdding: .day, value: 1, to: day)!
            let due = payments.filter { cal.isDate($0.date, inSameDayAs: tomorrow) }.map(\.payment)
            // Бюджет на исходе упоминаем, пока идёт его период.
            let dayAlerts = alerts.filter { day < $0.end }.map(\.alert)
            let digest = EveningDigest.make(date: day, spent: offset == 0 ? spentToday : 0, pending: pendingSMS,
                                            budgetLeft: left, tomorrow: due, budgets: dayAlerts, calendar: cal)
            let content = UNMutableNotificationContent()
            content.title = String(localized: digest.kind == .review ? "digest.title.review" : "digest.title")
            content.body = Self.body(digest, base: base)
            content.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            // В имени и время: если сводку за сегодня уже показали, новое время в тот же день всё равно сработает.
            let id = Self.idPrefix + "\(Int(fire.timeIntervalSince1970))"
            try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    // MARK: Данные

    private static func spentToday(ctx: ModelContext, rates: RatesStore, from start: Date) -> Decimal {
        let txs = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.date >= start }))) ?? []
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return txs.filter { $0.type == .expense && $0.date < end }
            .reduce(Decimal(0)) { $0 - (rates.value(of: $1, in: rates.base) ?? $1.amount) }
    }

    /// Месячный бюджет в основной валюте: общий (без категорий), если он есть, иначе сумма месячных бюджетов по категориям.
    /// `overall` это общий бюджет, если строка про месяц построена по нему: в списке бюджетов на исходе он не повторяется.
    private static func monthlyBudget(ctx: ModelContext, rates: RatesStore) -> (limit: Decimal, left: Decimal, overall: PersistentIdentifier?)? {
        let all = ((try? ctx.fetch(FetchDescriptor<Budget>())) ?? []).filter { $0.repeatType == 3 }
        let overall = all.filter { $0.categories.isEmpty }
        let chosen = overall.isEmpty ? all : [overall[0]]
        guard !chosen.isEmpty else { return nil }
        let txs = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>())) ?? []
        var limit = Decimal(0), left = Decimal(0)
        for b in chosen {
            guard let p = BudgetProgress.make(b, transactions: txs, rates: rates) else { continue }
            limit += rates.convert(p.limit, from: p.currency, to: rates.base) ?? p.limit
            left += rates.convert(p.remaining, from: p.currency, to: rates.base) ?? p.remaining
        }
        return (limit, left, overall.first?.persistentModelID)
    }

    /// Все бюджеты, потраченные на 80% и больше, с концом их текущего периода.
    private static func budgetAlerts(ctx: ModelContext, rates: RatesStore, skip: PersistentIdentifier?) -> [(end: Date, alert: EveningDigest.BudgetAlert)] {
        let budgets = ((try? ctx.fetch(FetchDescriptor<Budget>())) ?? []).filter { $0.persistentModelID != skip }
        let txs = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>())) ?? []
        let items = budgets.compactMap { b -> (Date, EveningDigest.BudgetAlert)? in
            guard let p = BudgetProgress.make(b, transactions: txs, rates: rates) else { return nil }
            return (p.periodEnd, EveningDigest.BudgetAlert(name: b.name, currency: p.currency, limit: p.limit, spent: p.spent))
        }
        let hot = EveningDigest.alerts(items.map(\.1))
        return hot.compactMap { a in items.first { $0.1 == a }.map { (end: $0.0, alert: a) } }
    }

    /// Расходы по расписанию до `until`, в основной валюте.
    private static func upcomingPayments(ctx: ModelContext, rates: RatesStore, until: Date) -> [(date: Date, payment: EveningDigest.Payment)] {
        let items = ((try? ctx.fetch(FetchDescriptor<RecurringTransaction>())) ?? []).filter { $0.active && $0.type == .expense }
        var result: [(Date, EveningDigest.Payment)] = []
        for r in items {
            let currency = r.account?.currency ?? rates.base
            let amount = rates.convert(abs(r.amount), from: currency, to: rates.base) ?? abs(r.amount)
            let name = r.payee.isEmpty ? (r.category?.name ?? "") : r.payee
            var date: Date? = r.nextDate
            while let d = date, d < until {
                if let end = r.endDate, d > end { break }
                result.append((d, EveningDigest.Payment(name: name, amount: amount)))
                date = Recurrence.nextDate(type: r.repeatType, duration: r.duration, from: r.nextDate, after: d)
            }
        }
        return result
    }

    // MARK: Текст

    static func body(_ g: EveningDigest, base: String) -> String {
        func money(_ x: Decimal) -> String { MoneyText.plain(x, code: base) }
        var lines: [String] = []
        if g.spent > 0 { lines.append(fmt("digest.spent", money(g.spent))) }
        else if g.kind == .empty { lines.append(String(localized: "digest.empty")) }
        if g.kind == .review {
            lines.append(fmt("digest.pending", g.pending))
        } else {
            if let left = g.budgetLeft, left < 0 { lines.append(fmt("digest.over", money(-left))) }
            else if let left = g.budgetLeft, let perDay = g.perDay {
                // «около 30 BYN в день»: копейки в примерной сумме только мешают.
                let rough = MoneyText.plain(perDay, code: base).replacingOccurrences(of: MoneyText.number(perDay, code: base),
                                                                                     with: perDay.formatted(.number.precision(.fractionLength(0))))
                lines.append(fmt("digest.budget", money(left), rough))
            }
            if g.tomorrow.count == 1, let p = g.tomorrow.first { lines.append(fmt("digest.tomorrow.one", p.name, money(p.amount))) }
            else if g.tomorrow.count > 1 {
                lines.append(fmt("digest.tomorrow.many", g.tomorrow.count, money(g.tomorrow.reduce(0) { $0 + $1.amount })))
            }
        }
        if !g.budgets.isEmpty {
            // Два самых горящих по имени, остальные числом, чтобы уведомление не разрасталось.
            var parts = g.budgets.prefix(2).map { a in
                a.isOver ? fmt("digest.alert.over", a.name, MoneyText.plain(-a.left, code: a.currency))
                         : fmt("digest.alert.left", a.name, MoneyText.plain(a.left, code: a.currency))
            }
            if g.budgets.count > 2 { parts.append(fmt("digest.alert.more", g.budgets.count - 2)) }
            lines.append(fmt("digest.alerts", parts.joined(separator: ", ")))
        }
        return lines.joined(separator: " ")
    }
}
