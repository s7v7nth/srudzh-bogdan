import SwiftUI
import SwiftData
import LedgerCore

extension RecurringTransaction {
    /// Создаёт операцию на дату платежа и сдвигает расписание.
    @MainActor func execute(in ctx: ModelContext, rates: RatesStore) {
        var created: [LedgerTransaction] = []
        if type == .transfer, let to = toAccount {
            // Перевод: списание со счёта и поступление на счёт получателя (в его валюте по текущему курсу).
            let out = abs(amount), from = account?.currency ?? to.currency
            let incoming = from == to.currency ? out : (rates.convert(out, from: from, to: to.currency) ?? out)
            let id = UUID()
            created = [LedgerTransaction(amount: -out, type: .transfer, date: nextDate, payee: payee, transferID: id, account: account),
                       LedgerTransaction(amount: incoming, type: .transfer, date: nextDate, payee: payee, transferID: id, account: to)]
        } else {
            created = [LedgerTransaction(amount: amount, type: type, date: nextDate, payee: payee, account: account, category: category)]
        }
        for tx in created { ctx.insert(tx); rates.stamp(tx) }
        let day = nextDate
        Task { await rates.stampHistorical(created, on: day) }
        skip()
    }

    /// Пропускает ближайший платёж: сдвигает дату или завершает расписание.
    func skip() {
        guard let next = Recurrence.nextDate(type: repeatType, duration: duration, from: nextDate, after: nextDate) else {
            active = false; return
        }
        if let end = endDate, next > end { active = false } else { nextDate = next }
    }
}

/// На сколько дней вперёд показывать платежи на главном экране с кружками.
let scheduleWindowKey = "scheduleWindowDays"
let scheduleWindowOptions = [1, 3, 7, 14, 30]
