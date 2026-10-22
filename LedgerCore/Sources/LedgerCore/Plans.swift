import Foundation

public enum Plans {
    /// Сумма пункта плана на месяц. `repeatMonths`: 1 каждый месяц, 3 раз в квартал, 12 раз в год;
    /// nil означает разовый платёж, который попадает только в месяц `paymentDate`.
    public static func monthlyAmount(
        annualAmount: Decimal,
        repeatMonths: Int?,
        paymentDate: Date? = nil,
        month: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        guard let repeatMonths else {
            guard let paymentDate, calendar.isDate(paymentDate, equalTo: month, toGranularity: .month) else { return 0 }
            return annualAmount
        }
        guard repeatMonths > 0, 12 % repeatMonths == 0 else { return 0 }
        // Годовая сумма делится на число платежей в году.
        let payment = Money.round(annualAmount / (Decimal(12) / Decimal(repeatMonths)))
        guard repeatMonths > 1, let paymentDate else { return payment }
        // Редкие платежи (квартал, год) попадают только в месяцы, кратные периоду от даты первого платежа.
        let c = calendar.dateComponents([.year, .month], from: paymentDate)
        let m = calendar.dateComponents([.year, .month], from: month)
        let diff = (m.year! - c.year!) * 12 + (m.month! - c.month!)
        return diff % repeatMonths == 0 ? payment : 0
    }
}
