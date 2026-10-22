import Foundation

/// Разобранное СМС банка. Сумма всегда положительная, знак определяет `kind`.
public struct BankSMS: Equatable {
    public enum Kind: Equatable {
        /// «Oplata»: трата по карте.
        case purchase
        /// «Zachislenie perevoda» по карте: банк так подписывает внесение наличных через банкомат.
        case cashDeposit
        /// «Na vashu kartu zachisleno»: входящий перевод, номер карты в таком СМС не указан.
        case incomingTransfer
    }
    public var kind: Kind
    public var cardLast4: String?
    public var date: Date
    public var amount: Decimal
    public var currency: String
    /// Название точки без кода страны. Для переводов пусто.
    public var merchant: String
    public var balance: Decimal?
    /// true, если банк прислал «доступную сумму» (она может включать лимит или блокировки), а не остаток.
    public var balanceIsAvailable: Bool
}

/// Разбор СМС Приорбанка (латиницей). Форматы подтверждены тремя настоящими СМС (см. тесты);
/// всё остальное возвращает nil, чтобы не записывать в учёт угаданное.
public enum PriorbankSMS {
    private static let amountPattern = #"(\d[\d ]*(?:[.,]\d+)?)"#

    // Karta 4***8780 19-10-26 14:51:23. Oplata 10.08 BYN. BLR SHOP KOPEECHKA. Balance: 103.82 BYN Tel. 7299090
    private static let cardRegex = try! NSRegularExpression(
        pattern: #"Karta\s+[\d*]*?(\d{4})\s+(\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\.\s*(Oplata|Zachislenie\s+perevoda)\s+"#
            + amountPattern + #"\s+([A-Z]{3})\.\s*(.*?)\.\s*Balance:\s*"# + amountPattern + #"\s+[A-Z]{3}"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators])

    // 08/10 16:49. Na vashu kartu zachisleno 50.00 BYN. Dostupnaja summa: 63.12 BYN. Tel. 7299090
    private static let transferRegex = try! NSRegularExpression(
        pattern: #"(\d{2})/(\d{2})\s+(\d{2}):(\d{2})\.\s*Na\s+vashu\s+kartu\s+zachisleno\s+"#
            + amountPattern + #"\s+([A-Z]{3})\.\s*Dostupnaja\s+summa:\s*"# + amountPattern + #"\s+[A-Z]{3}"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators])

    /// `receivedAt` нужен, чтобы достроить год там, где банк его не пишет.
    public static func parse(_ text: String, receivedAt: Date = .now, calendar: Calendar = .current) -> BankSMS? {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String { ns.substring(with: m.range(at: i)) }

        if let m = cardRegex.firstMatch(in: text, range: all) {
            let n = (2...7).map { Int(group(m, $0)) ?? 0 }
            guard let date = calendar.date(from: DateComponents(year: 2000 + n[2], month: n[1], day: n[0],
                                                                hour: n[3], minute: n[4], second: n[5])),
                  let amount = decimal(group(m, 9)), let balance = decimal(group(m, 12)) else { return nil }
            let kind: BankSMS.Kind = group(m, 8).lowercased() == "oplata" ? .purchase : .cashDeposit
            let merchant = kind == .purchase ? displayName(group(m, 11)) : ""
            return BankSMS(kind: kind, cardLast4: group(m, 1), date: date, amount: amount, currency: group(m, 10).uppercased(),
                           merchant: merchant, balance: balance, balanceIsAvailable: false)
        }

        if let m = transferRegex.firstMatch(in: text, range: all) {
            let n = (1...4).map { Int(group(m, $0)) ?? 0 }
            let year = calendar.component(.year, from: receivedAt)
            func make(_ y: Int) -> Date? {
                calendar.date(from: DateComponents(year: y, month: n[1], day: n[0], hour: n[2], minute: n[3]))
            }
            guard var date = make(year), let amount = decimal(group(m, 5)), let avail = decimal(group(m, 7)) else { return nil }
            // СМС про декабрь, полученное в январе: год прошлый.
            if date > receivedAt.addingTimeInterval(86_400), let prev = make(year - 1) { date = prev }
            return BankSMS(kind: .incomingTransfer, cardLast4: nil, date: date, amount: amount, currency: group(m, 6).uppercased(),
                           merchant: "", balance: avail, balanceIsAvailable: true)
        }
        return nil
    }

    private static func decimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."),
                locale: Locale(identifier: "en_US_POSIX"))
    }

    /// «BLR SHOP KOPEECHKA» → «SHOP KOPEECHKA»: убираем трёхбуквенный код страны в начале.
    static func displayName(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let parts = name.split(separator: " ", maxSplits: 1)
        if parts.count == 2, parts[0].count == 3, parts[0].allSatisfy({ $0.isASCII && $0.isUppercase }) {
            return String(parts[1])
        }
        return name
    }
}
