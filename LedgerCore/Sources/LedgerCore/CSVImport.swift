import Foundation

// Импорт из CSV: разбор файла, угадывание столбцов, определение счетов и категорий.
// Главное правило: счёт это название, которое что-то получает или с чего списывают расход.
// Всё остальное это категория расхода (если туда уходят деньги) или источник дохода (если оттуда приходят).

public enum CSVKind: Equatable { case expense, income, transfer }

/// Номера столбцов (с нуля). nil: столбца в файле нет.
public struct CSVColumns: Equatable {
    public var date: Int?
    public var type: Int?
    public var from: Int?
    public var to: Int?
    public var amount: Int?
    public var currency: Int?
    public var convertedAmount: Int?
    public var convertedCurrency: Int?
    public var note: Int?
    public init() {}
    /// Без даты, суммы и «откуда» операцию не собрать.
    public var isUsable: Bool { date != nil && amount != nil && from != nil }
}

/// Одна строка файла после разбора. `from` и `to` ещё не знают, счёт это или категория.
public struct CSVRow: Equatable {
    public var date: Date
    public var kind: CSVKind
    public var from: String
    public var to: String
    /// Всегда положительная.
    public var amount: Decimal
    public var currency: String
    public var convertedAmount: Decimal?
    public var convertedCurrency: String
    public var note: String
}

/// Сколько раз название встретилось на каждом месте. По этим числам угадывается роль.
public struct CSVName: Equatable {
    public var key: String
    public var name: String
    public var expenseFrom = 0, expenseTo = 0, incomeFrom = 0, incomeTo = 0, transferFrom = 0, transferTo = 0
    /// Названия из блока счетов в конце файла считаются счетами, даже если операций по ним нет.
    public var inAccountList = false
    /// Название стоит в блоке источников дохода в конце файла (для подсказки на экране проверки).
    public var listedAsIncome = false
    public var count: Int { expenseFrom + expenseTo + incomeFrom + incomeTo + transferFrom + transferTo }
    public var looksLikeAccount: Bool { inAccountList || expenseFrom > 0 || incomeTo > 0 || transferTo > 0 }
}

/// Строка из справочника в конце файла (счета с остатками, категории с иконками и бюджетами).
public struct CSVMeta: Equatable {
    public var name: String
    public var icon: String
    /// Для счёта текущий остаток, для категории бюджет.
    public var number: Decimal
    public var currency: String
}

public struct CSVSidecar: Equatable {
    public var accounts: [CSVMeta] = []
    public var categorySections: [[CSVMeta]] = []
    public init() {}
}

public struct CSVEntry: Equatable {
    public var date: Date
    public var kind: CSVKind
    /// Ключ счёта; для перевода счёт, с которого списано.
    public var account: String
    public var toAccount: String?
    public var category: String?
    /// Положительная сумма, ушедшая со счёта.
    public var amount: Decimal
    /// Сколько пришло на счёт назначения (для перевода между валютами может отличаться от `amount`).
    public var incoming: Decimal
    public var currency: String
    public var note: String
}

public enum CSVAccountHint: Equatable { case card, cash, savings }

public struct CSVLedgerAccount: Equatable {
    public var key: String
    public var name: String
    public var currency: String
    public var hint: CSVAccountHint
    public var icon: String
    public var count: Int
    /// Остаток на момент до первой операции. Считается из остатка «сейчас» из файла; без него 0.
    public var opening: Decimal
    public var current: Decimal?
}

public struct CSVLedgerCategory: Equatable {
    public var key: String
    public var name: String
    public var icon: String
    public var count: Int
    public var total: Decimal
    public var budget: Decimal?
}

public struct CSVLedger: Equatable {
    public var entries: [CSVEntry] = []
    public var accounts: [CSVLedgerAccount] = []
    public var expenseCategories: [CSVLedgerCategory] = []
    public var incomeCategories: [CSVLedgerCategory] = []
    /// Строки, которые не удалось разобрать или отнести к счетам.
    public var skipped = 0
    public var baseCurrency = ""
    public var firstDate: Date?
    public var lastDate: Date?
    public init() {}
}

public enum CSV {
    // MARK: Разбор текста

    /// Разбирает CSV. Понимает кавычки, переносы внутри кавычек, BOM, строку `sep=,` и разделители «, ; таб».
    /// Пустые строки сохраняются как пустые массивы: по ним делится файл на блоки.
    public static func parse(_ raw: String) -> [[String]] {
        let s = Array(raw.unicodeScalars)
        let n = s.count
        var i = 0
        if s.first == "\u{FEFF}" { i = 1 }
        var delimiter: Unicode.Scalar?
        if n >= i + 5, String(String.UnicodeScalarView(s[i..<i + 4])).lowercased() == "sep=",
           i + 5 == n || s[i + 5] == "\n" || s[i + 5] == "\r" {
            delimiter = s[i + 4]
            i += 5
            while i < n, s[i] == "\n" || s[i] == "\r" { i += 1 }
        }
        if delimiter == nil {
            var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
            var j = i, quoted = false
            while j < n, quoted || (s[j] != "\n" && s[j] != "\r") {
                if s[j] == "\"" { quoted.toggle() } else if !quoted, counts[s[j]] != nil { counts[s[j]]! += 1 }
                j += 1
            }
            delimiter = [Unicode.Scalar(","), Unicode.Scalar(";"), Unicode.Scalar("\t")].max { counts[$0]! < counts[$1]! } ?? ","
        }
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        while i < n {
            let c = s[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < n, s[i + 1] == "\"" { field.append(c); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(String(field)); field = String.UnicodeScalarView()
            } else if c == "\n" || c == "\r" {
                if c == "\r", i + 1 < n, s[i + 1] == "\n" { i += 1 }
                row.append(String(field)); field = String.UnicodeScalarView()
                rows.append(row.count == 1 && row[0].isEmpty ? [] : row)
                row = []
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(String(field)); rows.append(row) }
        return rows
    }

    /// Делит разобранный файл на блоки по пустым строкам. В каждом блоке первая строка это шапка.
    public static func sections(_ table: [[String]]) -> [[[String]]] {
        var out: [[[String]]] = []
        var current: [[String]] = []
        for r in table {
            if r.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                if !current.isEmpty { out.append(current); current = [] }
            } else { current.append(r) }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: Имена и ключи

    /// Одинаковые названия с разным регистром, «ё» вместо «е» и лишними пробелами считаются одним.
    public static func key(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func clean(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: Столбцы

    public static func guessColumns(header: [String]) -> CSVColumns {
        let h = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func first(exact: [String] = [], contains: [String] = [], without: [String] = [], skip: Set<Int> = []) -> Int? {
            if let i = h.indices.first(where: { !skip.contains($0) && exact.contains(h[$0]) }) { return i }
            return h.indices.first { i in
                !skip.contains(i) && contains.contains(where: h[i].contains) && !without.contains(where: h[i].contains)
            }
        }
        var c = CSVColumns()
        c.convertedAmount = first(contains: ["conver", "конверт"]).flatMap { i in
            ["amount", "сумм"].contains(where: h[i].contains) ? i : nil
        }
        c.convertedCurrency = h.indices.first { i in
            ["conver", "конверт"].contains(where: h[i].contains) && ["currency", "валют"].contains(where: h[i].contains)
        }
        var used = Set([c.convertedAmount, c.convertedCurrency].compactMap { $0 })
        c.date = first(exact: ["date", "data", "дата"], contains: ["date", "дата"], skip: used)
        c.type = first(exact: ["type", "тип"], contains: ["тип", "type"], skip: used)
        c.from = first(exact: ["from", "откуда", "account", "счет", "счёт", "со счета"], contains: ["from", "откуда"], skip: used)
        used.formUnion([c.date, c.type, c.from].compactMap { $0 })
        c.to = first(exact: ["to", "куда", "category", "категория"], contains: ["куда", "category", "категор"], skip: used)
        used.formUnion([c.to].compactMap { $0 })
        c.amount = first(exact: ["amount", "сумма"], contains: ["amount", "сумм"], skip: used)
        used.formUnion([c.amount].compactMap { $0 })
        c.currency = first(exact: ["currency", "валюта"], contains: ["currency", "валют"], skip: used)
        used.formUnion([c.currency].compactMap { $0 })
        c.note = first(exact: ["note", "notes", "заметка", "комментарий", "описание", "comment", "description", "memo"],
                       contains: ["note", "замет", "коммент", "descr", "опис"], skip: used)
        return c
    }

    // MARK: Даты

    enum DateOrder { case mdy, dmy, ymd }

    static func dateParts(_ s: String) -> [Int]? {
        let head = s.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "T" }).first.map(String.init) ?? ""
        let parts = head.split(whereSeparator: { $0 == "/" || $0 == "." || $0 == "-" }).map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }

    static func detectOrder(_ samples: [String]) -> DateOrder {
        var firstOver12 = false, secondOver12 = false, dots = false
        for s in samples {
            guard let p = dateParts(s) else { continue }
            if s.trimmingCharacters(in: .whitespaces).prefix(4).allSatisfy(\.isNumber) && p[0] > 31 { return .ymd }
            if p[0] > 12 { firstOver12 = true }
            if p[1] > 12 { secondOver12 = true }
            if s.contains(".") { dots = true }
        }
        if firstOver12 { return .dmy }
        if secondOver12 { return .mdy }
        return dots ? .dmy : .mdy
    }

    static func date(_ s: String, order: DateOrder, calendar: Calendar) -> Date? {
        guard let p = dateParts(s) else { return nil }
        var (y, m, d): (Int, Int, Int)
        switch order {
        case .ymd: (y, m, d) = (p[0], p[1], p[2])
        case .dmy: (d, m, y) = (p[0], p[1], p[2])
        case .mdy: (m, d, y) = (p[0], p[1], p[2])
        }
        if y < 100 { y += 2000 }
        guard (1...12).contains(m), (1...31).contains(d), (1900...2200).contains(y) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    // MARK: Суммы

    /// Понимает «1 426,12», «1,426.12», «-5», «(5)», «12 BYN».
    public static func amount(_ raw: String) -> Decimal? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var negative = t.hasPrefix("-") || t.hasPrefix("\u{2212}") || (t.hasPrefix("(") && t.hasSuffix(")"))
        let s = t.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard s.contains(where: \.isNumber) else { return nil }
        let lastDot = s.lastIndex(of: "."), lastComma = s.lastIndex(of: ",")
        var decimalSep: Character?
        if let d = lastDot, let c = lastComma {
            decimalSep = d > c ? "." : ","
        } else if let c = lastComma {
            let after = s.distance(from: c, to: s.endIndex) - 1
            decimalSep = s.filter { $0 == "," }.count == 1 && after != 3 ? "," : nil
        } else if lastDot != nil {
            decimalSep = s.filter { $0 == "." }.count == 1 ? "." : nil
        }
        var out = ""
        for ch in s {
            if ch.isNumber { out.append(ch) } else if ch == decimalSep { out.append(".") }
        }
        guard let v = Decimal(string: out, locale: nil) else { return nil }
        if v == 0 { negative = false }
        return negative ? -v : v
    }

    // MARK: Строки

    static func kind(of text: String) -> CSVKind? {
        let t = text.lowercased()
        if t.contains("transfer") || t.contains("перевод") { return .transfer }
        if ["expense", "расход", "spend", "withdraw", "списан"].contains(where: t.contains) { return .expense }
        if ["income", "доход", "deposit", "поступлен", "приход"].contains(where: t.contains) { return .income }
        return nil
    }

    /// Превращает блок операций (первая строка шапка) в строки. Вторым значением: сколько строк не разобрались.
    /// Без столбца типа вид операции берётся по знаку суммы: минус расход («откуда» счёт, «куда» категория),
    /// плюс доход (тогда «откуда» категория-источник, «куда» счёт, поэтому столбцы меняются местами).
    public static func rows(table: [[String]], columns c: CSVColumns, calendar: Calendar = .current) -> (rows: [CSVRow], skipped: Int) {
        guard c.isUsable, let dateCol = c.date, let amountCol = c.amount, let fromCol = c.from else { return ([], max(0, table.count - 1)) }
        let data = table.dropFirst()
        func cell(_ r: [String], _ i: Int?) -> String {
            guard let i, i < r.count else { return "" }
            return clean(r[i])
        }
        let order = detectOrder(data.prefix(2000).map { cell($0, dateCol) })
        var out: [CSVRow] = []
        var skipped = 0
        for r in data {
            if r.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            guard let d = date(cell(r, dateCol), order: order, calendar: calendar),
                  let signed = amount(cell(r, amountCol)), signed != 0 else { skipped += 1; continue }
            var from = cell(r, fromCol), to = cell(r, c.to)
            var kind = c.type.flatMap { CSV.kind(of: cell(r, $0)) }
            if kind == nil {
                kind = signed < 0 ? .expense : .income
                if signed > 0 { swap(&from, &to) }
            }
            guard let k = kind, !(from.isEmpty && to.isEmpty) else { skipped += 1; continue }
            let conv = c.convertedAmount.flatMap { amount(cell(r, $0)) }
            out.append(CSVRow(date: d, kind: k, from: from, to: to, amount: abs(signed),
                              currency: cell(r, c.currency).uppercased(),
                              convertedAmount: conv.map { abs($0) },
                              convertedCurrency: cell(r, c.convertedCurrency).uppercased(),
                              note: cell(r, c.note)))
        }
        return (out, skipped)
    }

    // MARK: Справочник в конце файла

    public static func sidecar(_ sections: [[[String]]]) -> CSVSidecar {
        var result = CSVSidecar()
        for sec in sections {
            guard let head = sec.first else { continue }
            let h = head.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            func col(_ words: [String]) -> Int? { h.firstIndex { cell in words.contains(where: cell.contains) } }
            let nameCol = col(["name", "имя", "назван"]) ?? 0
            let iconCol = col(["icon", "иконк"])
            let currencyCol = col(["currency", "валют"])
            let balanceCol = col(["current", "balance", "остат", "текущ"])
            let budgetCol = col(["budget", "бюджет"])
            guard balanceCol != nil || budgetCol != nil else { continue }
            func meta(_ r: [String], numberCol: Int?) -> CSVMeta? {
                guard nameCol < r.count else { return nil }
                let name = clean(r[nameCol])
                guard !name.isEmpty else { return nil }
                func at(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
                return CSVMeta(name: name, icon: at(iconCol).trimmingCharacters(in: .whitespaces),
                               number: amount(at(numberCol)) ?? 0, currency: at(currencyCol).trimmingCharacters(in: .whitespaces).uppercased())
            }
            let items = sec.dropFirst().compactMap { meta($0, numberCol: balanceCol ?? budgetCol) }
            if balanceCol != nil { result.accounts += items } else { result.categorySections.append(items) }
        }
        return result
    }

    // MARK: Роли

    public static func names(rows: [CSVRow], sidecar: CSVSidecar = CSVSidecar()) -> [CSVName] {
        var map: [String: CSVName] = [:]
        var order: [String] = []
        func touch(_ name: String, _ update: (inout CSVName) -> Void) {
            let k = key(name)
            guard !k.isEmpty else { return }
            if map[k] == nil { map[k] = CSVName(key: k, name: name); order.append(k) }
            update(&map[k]!)
        }
        for r in rows {
            switch r.kind {
            case .expense: touch(r.from) { $0.expenseFrom += 1 }; touch(r.to) { $0.expenseTo += 1 }
            case .income: touch(r.from) { $0.incomeFrom += 1 }; touch(r.to) { $0.incomeTo += 1 }
            case .transfer: touch(r.from) { $0.transferFrom += 1 }; touch(r.to) { $0.transferTo += 1 }
            }
        }
        for a in sidecar.accounts { touch(a.name) { $0.inAccountList = true } }
        let expenseKeys = Set(map.values.filter { $0.expenseTo > 0 }.map(\.key))
        let incomeKeys = Set(map.values.filter { $0.incomeFrom + $0.transferFrom > 0 }.map(\.key))
        if let sec = pickSections(sidecar, expenseKeys: expenseKeys, incomeKeys: incomeKeys).income {
            for m in sidecar.categorySections[sec] { if map[key(m.name)] != nil { map[key(m.name)]!.listedAsIncome = true } }
        }
        return order.compactMap { map[$0] }.sorted { $0.count > $1.count }
    }

    public static func guessAccounts(_ names: [CSVName]) -> Set<String> {
        Set(names.filter(\.looksLikeAccount).map(\.key))
    }

    public static func accountHint(name: String, icon: String) -> CSVAccountHint {
        let n = name.lowercased(), i = icon.lowercased()
        if ["налич", "cash", "касса", "кошел", "wallet"].contains(where: n.contains) { return .cash }
        if ["копил", "накоп", "saving", "вклад", "депозит", "deposit"].contains(where: n.contains) { return .savings }
        if i == "cash" { return .cash }
        if i == "savings" { return .savings }
        return .card
    }

    /// Какой из блоков категорий про расходы, а какой про доходы: по тому, чьи названия в нём встречаются.
    static func pickSections(_ sidecar: CSVSidecar, expenseKeys: Set<String>, incomeKeys: Set<String>) -> (expense: Int?, income: Int?) {
        let scores = sidecar.categorySections.map { sec -> (e: Int, i: Int) in
            let ks = Set(sec.map { key($0.name) })
            return (ks.intersection(expenseKeys).count, ks.intersection(incomeKeys).count)
        }
        let expense = scores.indices.max { scores[$0].e - scores[$0].i < scores[$1].e - scores[$1].i }
        let income = scores.indices.filter { $0 != expense || scores.count == 1 }
            .max { scores[$0].i - scores[$0].e < scores[$1].i - scores[$1].e }
        return (expense, income)
    }

    // MARK: Сборка

    /// Раскладывает строки по счетам и категориям, исходя из того, какие названия отмечены как счета.
    /// Оба конца счета: перевод. Счёт только слева: расход. Счёт только справа: доход. Ни одного счёта: строка пропускается.
    public static func build(rows: [CSVRow], accountKeys: Set<String>, sidecar: CSVSidecar = CSVSidecar(), skipped: Int = 0) -> CSVLedger {
        var ledger = CSVLedger()
        ledger.skipped = skipped
        var display: [String: String] = [:]
        func remember(_ name: String) { let k = key(name); if !k.isEmpty, display[k] == nil { display[k] = name } }
        var accCount: [String: Int] = [:]
        var accCurrency: [String: [String: Int]] = [:]
        struct Stat { var count = 0; var total: Decimal = 0 }
        var expense: [String: Stat] = [:], income: [String: Stat] = [:]
        var baseVotes: [String: Int] = [:]

        for r in rows {
            let fk = key(r.from), tk = key(r.to)
            let fromIsAccount = accountKeys.contains(fk), toIsAccount = accountKeys.contains(tk)
            let currency = r.currency
            if !currency.isEmpty { baseVotes[currency, default: 0] += 1 }
            switch (fromIsAccount, toIsAccount) {
            case (true, true):
                guard fk != tk else { ledger.skipped += 1; continue }
                var incoming = r.amount
                if let c = r.convertedAmount, !r.convertedCurrency.isEmpty, r.convertedCurrency != currency { incoming = c }
                remember(r.from); remember(r.to)
                accCount[fk, default: 0] += 1; accCount[tk, default: 0] += 1
                if !currency.isEmpty { accCurrency[fk, default: [:]][currency, default: 0] += 1 }
                let inCur = r.convertedCurrency.isEmpty ? currency : r.convertedCurrency
                if !inCur.isEmpty { accCurrency[tk, default: [:]][inCur, default: 0] += 1 }
                ledger.entries.append(CSVEntry(date: r.date, kind: .transfer, account: fk, toAccount: tk, category: nil,
                                               amount: r.amount, incoming: incoming, currency: currency, note: r.note))
            case (true, false):
                remember(r.from); accCount[fk, default: 0] += 1
                if !currency.isEmpty { accCurrency[fk, default: [:]][currency, default: 0] += 1 }
                if !tk.isEmpty { remember(r.to); expense[tk, default: Stat()].count += 1; expense[tk]!.total += r.amount }
                ledger.entries.append(CSVEntry(date: r.date, kind: .expense, account: fk, toAccount: nil, category: tk.isEmpty ? nil : tk,
                                               amount: r.amount, incoming: r.amount, currency: currency, note: r.note))
            case (false, true):
                remember(r.to); accCount[tk, default: 0] += 1
                if !currency.isEmpty { accCurrency[tk, default: [:]][currency, default: 0] += 1 }
                if !fk.isEmpty { remember(r.from); income[fk, default: Stat()].count += 1; income[fk]!.total += r.amount }
                ledger.entries.append(CSVEntry(date: r.date, kind: .income, account: tk, toAccount: nil, category: fk.isEmpty ? nil : fk,
                                               amount: r.amount, incoming: r.amount, currency: currency, note: r.note))
            case (false, false):
                ledger.skipped += 1
            }
        }
        ledger.entries.sort { $0.date < $1.date }
        ledger.firstDate = ledger.entries.first?.date
        ledger.lastDate = ledger.entries.last?.date
        ledger.baseCurrency = baseVotes.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.first?.key ?? ""

        // Остаток «сейчас» из справочника минус сумма всех операций = остаток до первой операции.
        var net: [String: Decimal] = [:]
        for e in ledger.entries {
            switch e.kind {
            case .expense: net[e.account, default: 0] -= e.amount
            case .income: net[e.account, default: 0] += e.amount
            case .transfer: net[e.account, default: 0] -= e.amount; net[e.toAccount!, default: 0] += e.incoming
            }
        }
        var current: [String: Decimal] = [:], metaIcon: [String: String] = [:], metaName: [String: String] = [:], metaCurrency: [String: String] = [:]
        for a in sidecar.accounts {
            let k = key(a.name)
            current[k, default: 0] += a.number
            if metaIcon[k] == nil || metaIcon[k]!.isEmpty { metaIcon[k] = a.icon }
            if metaName[k] == nil { metaName[k] = a.name }
            if metaCurrency[k] == nil, !a.currency.isEmpty { metaCurrency[k] = a.currency }
        }
        let accountOrder = accountKeys.sorted { (accCount[$0] ?? 0, $1) > (accCount[$1] ?? 0, $0) }
        for k in accountOrder {
            let name = metaName[k] ?? display[k]
            guard let name else { continue }
            let votes = accCurrency[k] ?? [:]
            let currency = votes.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.first?.key ?? metaCurrency[k] ?? ledger.baseCurrency
            let now = current[k]
            let icon = metaIcon[k] ?? ""
            ledger.accounts.append(CSVLedgerAccount(
                key: k, name: name, currency: currency, hint: accountHint(name: name, icon: icon), icon: icon,
                count: accCount[k] ?? 0, opening: now.map { $0 - (net[k] ?? 0) } ?? 0, current: now))
        }

        let expenseKeys = Set(expense.keys), incomeKeys = Set(income.keys)
        let (expenseSection, incomeSection) = pickSections(sidecar, expenseKeys: expenseKeys, incomeKeys: incomeKeys)
        func categories(_ stats: [String: Stat], section: Int?) -> [CSVLedgerCategory] {
            let meta = section.map { sidecar.categorySections[$0] } ?? []
            var byKey: [String: CSVMeta] = [:]
            for m in meta { byKey[key(m.name)] = m }
            return stats.map { k, s in
                let m = byKey[k]
                return CSVLedgerCategory(key: k, name: m?.name ?? display[k] ?? k, icon: m?.icon ?? "", count: s.count, total: s.total,
                                         budget: (m?.number ?? 0) > 0 ? m?.number : nil)
            }.sorted { ($0.count, $1.key) > ($1.count, $0.key) }
        }
        ledger.expenseCategories = categories(expense, section: expenseSection)
        ledger.incomeCategories = categories(income, section: incomeSection)
        return ledger
    }
}
