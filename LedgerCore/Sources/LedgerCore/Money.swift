import Foundation

/// Деньги везде считаем в Decimal. Расходы хранятся отрицательными, доходы положительными.
/// Округление: «половина вверх» (от нуля) до знаков валюты, выбрано один раз и зафиксировано тестами.
public enum Money {
    public static func round(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Перевод суммы в другую валюту по курсу (сколько единиц целевой валюты в одной исходной).
    public static func convert(_ amount: Decimal, rate: Decimal, scale: Int = 2) -> Decimal {
        round(amount * rate, scale: scale)
    }
}
