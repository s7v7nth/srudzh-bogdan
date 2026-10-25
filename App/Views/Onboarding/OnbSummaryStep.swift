import SwiftUI
import LedgerCore

/// Последний шаг: что будет создано и простая картина месяца.
struct OnbSummaryStep: View {
    let draft: OnboardingDraft

    private var accountCount: Int {
        draft.enabledAccounts.count + draft.credits.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
    private var paymentCount: Int {
        (draft.incomes + draft.bills + draft.countedLoans + draft.subscriptions).filter(\.isActive)
            .reduce(0) { $0 + ($1.cadence == .twiceMonthly ? 2 : 1) }
    }
    private var budgetCount: Int { draft.expenseCategories.filter { (draft.amounts[$0.id] ?? 0) > 0 }.count }
    private var budgetTotal: Decimal { draft.categories.filter(\.enabled).reduce(0) { $0 + (draft.amounts[$1.id] ?? 0) } }
    private var left: Decimal { draft.monthlyIncome - draft.monthlyFixedExpenses }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnbHeader(icon: "checkmark.seal", title: "onb.summary.title", subtitle: "onb.summary.subtitle")
            OnbCard {
                if let l = draft.imported { countRow("list.bullet.rectangle", "onb.summary.transactions", l.entries.count) }
                countRow("creditcard", "onb.summary.accounts", accountCount)
                countRow("square.grid.2x2", "onb.summary.categories", draft.expenseCategories.count)
                countRow("chart.pie", "onb.summary.budgets", budgetCount)
                countRow("repeat", "onb.summary.payments", paymentCount)
            }
            OnbCard {
                LabeledMoney(label: "onb.summary.income", amount: draft.monthlyIncome, code: draft.currency, color: Theme.income)
                LabeledMoney(label: "onb.summary.fixed", amount: draft.monthlyFixedExpenses, code: draft.currency)
                Divider().overlay(.white.opacity(0.06))
                LabeledMoney(label: "onb.summary.left", amount: left, code: draft.currency, color: left < 0 ? Theme.expense : nil)
                    .font(.app(.body, .semibold))
                LabeledMoney(label: "onb.summary.budgets.total", amount: budgetTotal, code: draft.currency)
                LabeledMoney(label: "onb.summary.savings", amount: draft.savings, code: draft.currency, color: Theme.income)
            }
            Label("onb.summary.note", systemImage: "hand.tap").font(.app(.footnote)).foregroundStyle(.secondary)
        }
    }

    private func countRow(_ icon: String, _ title: LocalizedStringKey, _ count: Int) -> some View {
        HStack(spacing: 12) {
            OnbIcon(name: icon)
            Text(title)
            Spacer()
            Text("\(count)").font(.app(.body, .semibold).monospacedDigit())
        }
    }
}
