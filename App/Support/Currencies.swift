import SwiftUI

struct CurrencyInfo: Identifiable, Hashable {
    let code: String
    let symbol: String
    var id: String { code }
    /// Название на языке интерфейса, берётся из системы.
    var name: String { Locale.current.localizedString(forCurrencyCode: code)?.capitalizedFirst ?? code }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

enum Currencies {
    /// Валюты, доступные для счетов. У BYN собственный знак, он рисуется отдельно (BynSign).
    static let all: [CurrencyInfo] = [
        ("BYN", "Br"), ("RUB", "₽"), ("USD", "$"), ("EUR", "€"), ("GBP", "£"), ("UAH", "₴"), ("KZT", "₸"),
        ("PLN", "zł"), ("CNY", "¥"), ("JPY", "¥"), ("TRY", "₺"), ("GEL", "₾"), ("AMD", "֏"), ("UZS", "UZS"),
        ("KGS", "KGS"), ("AZN", "₼"), ("MDL", "MDL"), ("CHF", "CHF"), ("CZK", "Kč"), ("CAD", "C$"),
        ("AUD", "A$"), ("AED", "AED"), ("KRW", "₩"), ("INR", "₹"),
    ].map { CurrencyInfo(code: $0.0, symbol: $0.1) }

    static func symbol(_ code: String) -> String { all.first { $0.code == code }?.symbol ?? code }

    /// Основная валюта по региону телефона, если она есть в списке.
    static var deviceDefault: String {
        let c = Locale.current.currency?.identifier ?? "USD"
        return all.contains { $0.code == c } ? c : "USD"
    }
}
