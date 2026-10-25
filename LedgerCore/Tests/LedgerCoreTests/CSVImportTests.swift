import XCTest
@testable import LedgerCore

final class CSVImportTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Маленькая копия формата, в котором экспортирует Debit & Credit: операции, потом блоки со справочниками.
    let sample = """
    sep=,
    "Data","Type","From","To","Tags","Amount","Currency","Amount converted","Currency of conversion","Recurrence","Note"
    "3/14/2025","Transfer","Доход","Банковский счет","","1000","BYN","1000","BYN","None",""
    "3/14/2025","Transfer","Банковский счет","Копилка","","200","BYN","200","BYN","None",""
    "3/14/2025","Expense","Банковский счет","Продукты","","50.5","BYN","50.5","BYN","None","молоко
    и хлеб"
    "3/15/2025","Expense","Наличные","Продукты","","10","BYN","10","BYN","None",""
    "3/15/2025","Transfer","Банковский счет","Наличные","","100","BYN","100","BYN","None",""
    "3/16/2025","Transfer","Gifts","Наличные","","30","BYN","30","BYN","None",""
    "3/16/2025","Expense","Банковский счет","Gifts","","5","BYN","5","BYN","None",""


    "Name","Budget","Received to date","Icon","Currency"
    "Доход","0","1000","Salary","BYN"
    "Gifts","0","30","Gifts","BYN"


    "Name","Current amount","Icon","Currency"
    "Копилка","200","Savings","BYN"
    "Наличные","120","Cash","BYN"
    "Банковский счет","644.5","Bank","BYN"


    "Name","Budget","Received to date","Icon","Currency"
    "Продукты","850","60.5","ForkAndKnife","BYN"
    "Gifts","0","5","Gifts","BYN"
    """

    func ledger(_ text: String) -> (CSVLedger, [CSVName]) {
        let sections = CSV.sections(CSV.parse(text))
        let cols = CSV.guessColumns(header: sections[0][0])
        let parsed = CSV.rows(table: sections[0], columns: cols, calendar: cal)
        let side = CSV.sidecar(Array(sections.dropFirst()))
        let names = CSV.names(rows: parsed.rows, sidecar: side)
        return (CSV.build(rows: parsed.rows, accountKeys: CSV.guessAccounts(names), sidecar: side, skipped: parsed.skipped), names)
    }

    // MARK: Разбор текста

    func testParseHandlesQuotesNewlinesAndBOM() {
        let t = CSV.parse("\u{FEFF}a;b;c\r\n\"x;1\";\"he said \"\"hi\"\"\";\"two\nlines\"\r\n\r\nlast;;")
        XCTAssertEqual(t[0], ["a", "b", "c"])
        XCTAssertEqual(t[1], ["x;1", "he said \"hi\"", "two\nlines"])
        XCTAssertEqual(t[2], [])
        XCTAssertEqual(t[3], ["last", "", ""])
    }

    func testParseDetectsDelimiter() {
        XCTAssertEqual(CSV.parse("a\tb\n1\t2")[1], ["1", "2"])
        XCTAssertEqual(CSV.parse("a;b,c;d\n1;2,5;3")[1], ["1", "2,5", "3"])
    }

    // MARK: Столбцы

    func testGuessColumnsForDebitAndCreditHeader() {
        let c = CSV.guessColumns(header: ["Data", "Type", "From", "To", "Tags", "Amount", "Currency", "Amount converted", "Currency of conversion", "Recurrence", "Note"])
        XCTAssertEqual([c.date, c.type, c.from, c.to, c.amount, c.currency, c.convertedAmount, c.convertedCurrency, c.note],
                       [0, 1, 2, 3, 5, 6, 7, 8, 10])
    }

    func testGuessColumnsForRussianBankHeader() {
        let c = CSV.guessColumns(header: ["Дата", "Счёт", "Категория", "Сумма", "Валюта", "Комментарий"])
        XCTAssertEqual([c.date, c.from, c.to, c.amount, c.currency, c.note], [0, 1, 2, 3, 4, 5])
        XCTAssertNil(c.type)
    }

    // MARK: Даты и суммы

    func testDateOrderIsDetectedFromValues() {
        func parse(_ s: [String]) -> DateComponents {
            let o = CSV.detectOrder(s)
            return cal.dateComponents([.year, .month, .day], from: CSV.date(s[0], order: o, calendar: cal)!)
        }
        XCTAssertEqual(parse(["3/14/2025", "1/2/2025"]).month, 3)
        XCTAssertEqual(parse(["14/03/2025", "1/2/2025"]).month, 3)
        XCTAssertEqual(parse(["14.03.2025"]).day, 14)
        XCTAssertEqual(parse(["03.04.2025"]).month, 4, "точки: сначала день")
        XCTAssertEqual(parse(["2025-03-14 10:30"]).day, 14)
        XCTAssertNil(CSV.date("32/13/2025", order: .dmy, calendar: cal))
    }

    func testAmountParsing() {
        XCTAssertEqual(CSV.amount("1426.12"), Decimal(string: "1426.12"))
        XCTAssertEqual(CSV.amount("1 426,12"), Decimal(string: "1426.12"))
        XCTAssertEqual(CSV.amount("1,426.12"), Decimal(string: "1426.12"))
        XCTAssertEqual(CSV.amount("1.426,12"), Decimal(string: "1426.12"))
        XCTAssertEqual(CSV.amount("1,426"), 1426)
        XCTAssertEqual(CSV.amount("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(CSV.amount("-5"), -5)
        XCTAssertEqual(CSV.amount("(5.50)"), Decimal(string: "-5.5"))
        XCTAssertEqual(CSV.amount("12 BYN"), 12)
        XCTAssertNil(CSV.amount(""))
        XCTAssertNil(CSV.amount("abc"))
    }

    // MARK: Роли и сборка

    func testRolesAreGuessedFromHowNamesAreUsed() {
        let (_, names) = ledger(sample)
        let accounts = CSV.guessAccounts(names)
        XCTAssertEqual(accounts, ["банковский счет", "наличные", "копилка"])
        XCTAssertFalse(accounts.contains("доход"), "только отдаёт деньги: источник дохода")
        XCTAssertFalse(accounts.contains("gifts"))
    }

    func testLedgerSplitsExpenseIncomeAndTransfers() {
        let (l, _) = ledger(sample)
        XCTAssertEqual(l.skipped, 0)
        XCTAssertEqual(l.entries.count, 7)
        XCTAssertEqual(l.entries.filter { $0.kind == .transfer }.count, 2)
        XCTAssertEqual(l.entries.filter { $0.kind == .income }.count, 2, "«Доход → Банк» и «Gifts → Наличные»")
        XCTAssertEqual(Set(l.expenseCategories.map(\.name)), ["Продукты", "Gifts"])
        XCTAssertEqual(Set(l.incomeCategories.map(\.name)), ["Доход", "Gifts"])
        XCTAssertEqual(l.baseCurrency, "BYN")
        XCTAssertEqual(l.entries.first { $0.note.contains("молоко") }?.note, "молоко и хлеб")
    }

    func testIconsAndBudgetsComeFromTheRightBlock() {
        let (l, _) = ledger(sample)
        XCTAssertEqual(l.expenseCategories.first { $0.name == "Продукты" }?.budget, 850)
        XCTAssertEqual(l.expenseCategories.first { $0.name == "Продукты" }?.icon, "ForkAndKnife")
        XCTAssertEqual(l.incomeCategories.first { $0.name == "Доход" }?.icon, "Salary")
        XCTAssertNil(l.incomeCategories.first { $0.name == "Доход" }?.budget)
    }

    func testOpeningBalanceMakesCurrentBalanceMatch() {
        let (l, _) = ledger(sample)
        // Банк: +1000 −200 −50.5 −100 −5 = 644.5, значит остаток до первой операции 0.
        // Наличные: −10 +100 +30 = 120, до операций 0. Копилка: +200.
        for a in l.accounts { XCTAssertEqual(a.opening, 0, a.name) }
        XCTAssertEqual(l.accounts.first { $0.name == "Копилка" }?.hint, .savings)
        XCTAssertEqual(l.accounts.first { $0.name == "Наличные" }?.hint, .cash)
        XCTAssertEqual(l.accounts.first { $0.name == "Банковский счет" }?.hint, .card)
        // Если остаток «сейчас» больше, разницу берёт на себя начальный остаток.
        var side = CSVSidecar()
        side.accounts = [CSVMeta(name: "Банковский счет", icon: "Bank", number: 700, currency: "BYN")]
        let rows = CSV.rows(table: CSV.sections(CSV.parse(sample))[0], columns: CSV.guessColumns(header: CSV.sections(CSV.parse(sample))[0][0]), calendar: cal).rows
        let l2 = CSV.build(rows: rows, accountKeys: ["банковский счет", "наличные", "копилка"], sidecar: side)
        XCTAssertEqual(l2.accounts.first { $0.name == "Банковский счет" }?.opening, Decimal(string: "55.5"))
    }

    func testUserCanTurnSourceIntoAccount() {
        let sections = CSV.sections(CSV.parse(sample))
        let rows = CSV.rows(table: sections[0], columns: CSV.guessColumns(header: sections[0][0]), calendar: cal).rows
        let l = CSV.build(rows: rows, accountKeys: ["банковский счет", "наличные", "копилка", "доход"])
        XCTAssertEqual(l.entries.filter { $0.kind == .transfer }.count, 3)
        XCTAssertEqual(l.accounts.count, 4)
    }

    func testRowWithNoAccountIsSkipped() {
        let sections = CSV.sections(CSV.parse(sample))
        let rows = CSV.rows(table: sections[0], columns: CSV.guessColumns(header: sections[0][0]), calendar: cal).rows
        let l = CSV.build(rows: rows, accountKeys: ["банковский счет"])
        XCTAssertEqual(l.skipped, 2, "наличные ↔ продукты и gifts → наличные не затрагивают выбранный счёт")
    }

    func testSignedBankFormatWithoutTypeColumn() {
        let text = """
        Дата;Счёт;Категория;Сумма;Валюта
        14.03.2025;Карта;Продукты;-12,50;BYN
        15.03.2025;Карта;Зарплата;1 000,00;BYN
        15.03.2025;Карта;;-3;BYN
        битая;Карта;Еда;-1;BYN
        """
        let (l, _) = ledger(text)
        XCTAssertEqual(l.skipped, 1)
        XCTAssertEqual(l.entries.map(\.kind), [.expense, .income, .expense])
        XCTAssertEqual(l.accounts.map(\.name), ["Карта"])
        XCTAssertEqual(l.entries[0].amount, Decimal(string: "12.5"))
        XCTAssertEqual(l.incomeCategories.map(\.name), ["Зарплата"])
        XCTAssertNil(l.entries[2].category, "расход без категории остаётся без категории")
    }

    func testTransferBetweenCurrenciesUsesConvertedAmount() {
        let text = """
        Date,Type,From,To,Amount,Currency,Amount converted,Currency of conversion
        1/5/2025,Expense,USD card,Food,10,USD,32,BYN
        1/6/2025,Transfer,USD card,BYN card,100,USD,320,BYN
        """
        let (l, _) = ledger(text)
        let t = l.entries.first { $0.kind == .transfer }!
        XCTAssertEqual(t.amount, 100)
        XCTAssertEqual(t.incoming, 320)
        XCTAssertEqual(l.accounts.first { $0.name == "USD card" }?.currency, "USD")
        XCTAssertEqual(l.accounts.first { $0.name == "BYN card" }?.currency, "BYN")
        XCTAssertEqual(l.entries.first { $0.kind == .expense }?.amount, 10, "у расхода берём сумму в валюте счёта")
    }

    // MARK: Настоящий файл (если путь задан в переменной CSV_SAMPLE)

    func testRealExport() throws {
        guard let path = ProcessInfo.processInfo.environment["CSV_SAMPLE"] else { throw XCTSkip("CSV_SAMPLE не задан") }
        let (l, names) = ledger(try String(contentsOfFile: path, encoding: .utf8))
        print("ENTRIES", l.entries.count, "SKIPPED", l.skipped, "BASE", l.baseCurrency)
        print("ACCOUNTS", l.accounts.map { "\($0.name) \($0.currency) \($0.hint) opening=\($0.opening) now=\($0.current.map(String.init(describing:)) ?? "-")" })
        print("EXPENSE", l.expenseCategories.map { "\($0.name)|\($0.icon)|\($0.budget.map(String.init(describing:)) ?? "-")" })
        print("INCOME", l.incomeCategories.map { "\($0.name)|\($0.icon)" })
        print("NAMES", names.count, "RANGE", l.firstDate!, l.lastDate!)
        XCTAssertEqual(l.entries.count + l.skipped, 4619)
    }
}

extension CSVImportTests {
    func testIncomeListedInFileIsFlagged() {
        let (_, names) = ledger(sample)
        XCTAssertTrue(names.first { $0.key == "доход" }!.listedAsIncome)
        XCTAssertFalse(names.first { $0.key == "банковский счет" }!.listedAsIncome)
    }
}
