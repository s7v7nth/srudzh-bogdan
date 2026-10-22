#if DEBUG
import Foundation
import SwiftData

/// Только для разработки: запуск с аргументом -seedDemo наполняет базу примерами.
enum DemoData {
    @MainActor static func runIfRequested(_ ctx: ModelContext, rates: RatesStore) {
        // -seedSMSMore: добавляет свежие СМС в уже существующую базу (для ручной проверки дайджеста).
        if CommandLine.arguments.contains("-seedSMSMore") {
            for t in ["Karta 4***8780 19-10-26 18:20:10. Oplata 7.50 BYN. BLR SHOP KOPEECHKA. Balance: 96.32 BYN Tel. 7299090",
                      "Karta 4***8780 19-10-26 18:45:33. Oplata 5.20 BYN. BLR SHOP KOPEECHKA 12. Balance: 91.12 BYN Tel. 7299090",
                      "Karta 4***8780 19-10-26 19:05:02. Oplata 33.45 BYN. BLR EVROOPT. Balance: 57.67 BYN Tel. 7299090",
                      "19/10 19:30. Na vashu kartu zachisleno 100.00 BYN. Dostupnaja summa: 157.67 BYN. Tel. 7299090"] {
                _ = SMSImporter.importText(t, ctx: ctx, rates: rates)
            }
        }
        guard CommandLine.arguments.contains("-seedDemo"),
              (try? ctx.fetchCount(FetchDescriptor<Account>())) == 0 else { return }
        if rates.base.isEmpty { rates.base = "BYN" }
        let cal = Calendar.current
        func ago(_ days: Int) -> Date { cal.date(byAdding: .day, value: -days, to: .now)! }
        let cats = (try? ctx.fetch(FetchDescriptor<Category>())) ?? []
        func cat(_ icon: String) -> Category? { cats.first { $0.icon == icon } }

        let byn = Account(name: "BYN card", currency: "BYN", sortID: 0)
        let usd = Account(name: "USD card", currency: "USD", sortID: 1)
        let credit = Account(name: "Credit line", currency: "BYN", kind: .creditLine, sortID: 2)
        credit.creditLimit = 2000; credit.interestRate = 24; credit.statementDay = 1
        credit.graceDays = 30; credit.graceFromStatement = true
        credit.minPercent = 5; credit.minFloor = 20; credit.dueDays = 20
        [byn, usd, credit].forEach(ctx.insert)

        func add(_ amount: Decimal, _ type: TxType, _ acc: Account, day: Int, payee: String = "",
                 category: Category? = nil, transfer: UUID? = nil) {
            let tx = LedgerTransaction(amount: amount, type: type, date: ago(day), payee: payee,
                                       transferID: transfer, account: acc, category: category)
            ctx.insert(tx); rates.stamp(tx)
        }
        add(500, .income, byn, day: 60, payee: "Opening balance")
        add(1000, .income, usd, day: 60, payee: "Opening balance")
        add(2000, .income, byn, day: 20, payee: "Employer", category: cat("banknote"))
        add(-40, .expense, usd, day: 0, payee: "Cafe", category: cat("cup.and.saucer"))
        add(-300, .expense, credit, day: 45, payee: "Shop", category: cat("cart"))
        add(-250, .expense, credit, day: 12, payee: "Market", category: cat("cart"))
        add(-120, .expense, credit, day: 3, payee: "Pharmacy", category: cat("cross.case"))
        let repay = UUID()
        add(-100, .transfer, byn, day: 5, transfer: repay)
        add(100, .transfer, credit, day: 5, transfer: repay)
        let fx = UUID()
        add(-100, .transfer, usd, day: 2, transfer: fx)
        add(300, .transfer, byn, day: 2, transfer: fx)

        let b = Budget(name: "Food", amount: 400, currency: "BYN",
                       startDate: cal.dateInterval(of: .month, for: .now)!.start)
        if let c = cat("cart") { b.categories = [c] }
        ctx.insert(b)
        try? ctx.save()

        // -seedSMS: три настоящих СМС Приорбанка; -seedSMSAlias: карта 8780 уже привязана к «BYN card».
        if CommandLine.arguments.contains("-seedSMS") {
            if CommandLine.arguments.contains("-seedSMSAlias") { ctx.insert(CardAlias(last4: "8780", account: byn)) }
            for t in ["Karta 4***8780 19-10-26 14:51:23. Oplata 10.08 BYN. BLR SHOP KOPEECHKA. Balance: 103.82 BYN Tel. 7299090",
                      "Karta 4***8780 11-10-26 17:44:14. Zachislenie perevoda 1200.00 BYN. BLR Money Transfer Visa. Balance: 1200.16 BYN Tel. 7299090",
                      "08/10 16:49. Na vashu kartu zachisleno 50.00 BYN. Dostupnaja summa: 63.12 BYN. Tel. 7299090"] {
                _ = SMSImporter.importText(t, ctx: ctx, rates: rates)
            }
        }
    }
}

extension OnboardingDraft {
    /// Только для разработки: аргумент -onbDemo заполняет ответы онбординга примерами, -onbStep N открывает нужный шаг.
    func applyDemo() {
        func fill(_ list: inout [PaymentDraft], _ i: Int, _ amount: String, day: Int? = nil, remaining: String = "") {
            list[i].enabled = true; list[i].amountText = amount; list[i].remainingText = remaining
            if let day { list[i].day = day }
            ensureCategory(list[i].categoryKey)
        }
        fill(&incomes, 0, "3347", day: 10)
        fill(&bills, 0, "800", day: 1); fill(&bills, 1, "120", day: 15); fill(&bills, 2, "25"); fill(&bills, 3, "15")
        fill(&loans, 0, "150", day: 20, remaining: "18")
        fill(&subscriptions, 0, "12"); fill(&subscriptions, 1, "8"); fill(&subscriptions, 2, "3")
        credits = [CreditDraft(name: "Credit card", limitText: "2000", aprText: "24", statementDay: 1, dueDays: 20, debtText: "300")]
        accounts[0].balanceText = "500"; accounts[1].balanceText = "80"
    }
}
#endif
