import Foundation

/// Расчёты по банковскому кредиту (счёт «Кредит»): остаток долга хранится как отрицательный остаток счёта,
/// ежемесячный платёж это перевод по расписанию с карты на этот счёт.
///
/// Решения:
/// - Проценты не моделируем: число платежей считается как «остаток ÷ платёж» с округлением вверх
///   (последний платёж может быть меньше). Банк этот остаток знает точнее, его можно поправить вручную.
/// - Для бюджета платёж по кредиту (перевод на счёт-кредит) считается тратой в категории кредита.
///   Платёж по кредитной карте тратой не считается: покупки по ней уже учтены в своих категориях.
public enum Loans {
    /// Сколько платежей осталось. nil, если платёж не задан. 0, если долга нет.
    public static func paymentsLeft(debt: Decimal, payment: Decimal) -> Int? {
        guard payment > 0 else { return nil }
        guard debt > 0 else { return 0 }
        let n = NSDecimalNumber(decimal: debt / payment).doubleValue.rounded(.up)
        return Int(min(max(n, 1), 1200))
    }

    /// Оценка остатка долга, когда известно только число оставшихся платежей.
    public static func estimatedDebt(payments: Int, payment: Decimal) -> Decimal {
        guard payments > 0, payment > 0 else { return 0 }
        return Decimal(payments) * payment
    }

    /// Доля уже выплаченного: 0...1. Исходная сумма не меньше остатка (остаток мог вырасти от процентов).
    public static func paidRatio(principal: Decimal?, remaining: Decimal) -> Double {
        let rest = max(remaining, 0)
        let total = max(principal ?? rest, rest)
        guard total > 0 else { return 1 }
        return NSDecimalNumber(decimal: (total - rest) / total).doubleValue
    }

    /// Сколько платежей по расписанию осталось до даты окончания (включая ближайший). nil, если окончания нет.
    public static func scheduledPayments(next: Date, end: Date?, repeatType: Int, duration: Int,
                                         calendar: Calendar = .current) -> Int? {
        guard let end else { return nil }
        guard next <= end else { return 0 }
        var count = 1
        var date = next
        while count < 1200,
              let d = Recurrence.nextDate(type: repeatType, duration: duration, from: date, after: date, calendar: calendar),
              d <= end {
            count += 1; date = d
        }
        return count
    }
}
