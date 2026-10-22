import SwiftUI
import LedgerCore

/// Сумма с символом валюты. Минус впереди, цифры одной ширины.
struct MoneyText: View {
    let amount: Decimal
    let code: String
    var colored = false
    var signed = false
    /// Явный цвет. Без него сумма наследует цвет окружения (серый в подписях и т. п.).
    var color: Color? = nil
    /// Цифры одной ширины нужны в столбцах; в крупной сумме они разрежены, там выключаем.
    var tabular = true
    /// Жирность цифр, нужна знаку BYN, чтобы черта была той же толщины.
    var weight: Font.Weight = .regular

    private var content: some View {
        HStack(spacing: 3) {
            Text(Self.number(amount, code: code, signed: signed)).monospacedDigit(tabular)
            CurrencySymbolView(code: code, weight: weight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Self.number(amount, code: code, signed: signed)) \(Self.spoken(code))"))
    }

    var body: some View {
        if let c = color ?? (colored ? tint : nil) { content.foregroundStyle(c) } else { content }
    }

    private var tint: Color { amount < 0 ? TxType.expense.tint : (amount > 0 ? TxType.income.tint : .primary) }

    static func number(_ amount: Decimal, code: String, signed: Bool = false) -> String {
        let d = Money.fractionDigits(code)
        let s = amount.formatted(.number.precision(.fractionLength(d)))
        return signed && amount > 0 ? "+" + s : s
    }

    static func spoken(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

    /// Обычная строка для мест, где картинку не вставить (тексты в предложениях). У BYN вместо знака код.
    static func plain(_ amount: Decimal, code: String) -> String {
        "\(number(amount, code: code)) \(code == "BYN" ? "BYN" : Currencies.symbol(code))"
    }
}

/// Ряд «подпись и сумма» там, где сумма стоит внутри предложения.
struct LabeledMoney: View {
    let label: LocalizedStringKey
    let amount: Decimal
    let code: String
    var colored = false
    var color: Color? = nil
    var body: some View {
        HStack { Text(label); Spacer(); MoneyText(amount: amount, code: code, colored: colored, color: color) }
    }
}

extension Decimal {
    /// Разбор введённого числа с запятой или точкой.
    static func parse(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
}

private extension Text {
    func monospacedDigit(_ on: Bool) -> Text { on ? monospacedDigit() : self }
}
