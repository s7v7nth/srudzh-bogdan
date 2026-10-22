import SwiftUI
import SwiftData
import LedgerCore

extension RecurringTransaction {
    /// Создаёт операцию на дату платежа и сдвигает расписание.
    @MainActor func execute(in ctx: ModelContext, rates: RatesStore) {
        let tx = LedgerTransaction(amount: amount, type: type, date: nextDate, payee: payee, account: account, category: category)
        ctx.insert(tx); rates.stamp(tx)
        let created = [tx], day = nextDate
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
