import SwiftUI
import LedgerCore

/// Общий экран для доходов, обязательных платежей, кредитов и подписок: список готовых вариантов,
/// у включённого раскрываются сумма, периодичность, день и счёт.
struct OnbPaymentsStep<Header: View>: View {
    let header: Header
    @Binding var items: [PaymentDraft]
    let accounts: [AccountDraft]
    let cadences: [PaymentCadence]
    let isIncome: Bool
    let customCategory: String
    let customIcon: String
    let addTitle: LocalizedStringKey
    var showRemaining = false
    let footer: LocalizedStringKey?
    let footerAmount: Decimal
    let currency: String
    let onEnable: (PaymentDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ForEach($items) { $p in
                OnbPaymentCard(p: $p, accounts: accounts, cadences: cadences, isIncome: isIncome,
                               showRemaining: showRemaining, onEnable: onEnable) { items.removeAll { $0.id == p.id } }
            }
            Button {
                withAnimation(.snappy) { items.append(PaymentDraft(custom: customCategory, icon: customIcon)) }
            } label: {
                Label(addTitle, systemImage: "plus.circle.fill").font(.app(.subheadline, .semibold))
            }
            .padding(.top, 2)
            if let footer {
                HStack {
                    Text(footer); Spacer(); MoneyText(amount: footerAmount, code: currency).fontWeight(.semibold)
                }
                .font(.app(.subheadline)).padding(14)
                .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text("onb.pay.dayHint").font(.app(.footnote)).foregroundStyle(.secondary)
        }
    }
}

struct OnbPaymentCard: View {
    @Binding var p: PaymentDraft
    let accounts: [AccountDraft]
    let cadences: [PaymentCadence]
    let isIncome: Bool
    let showRemaining: Bool
    let onEnable: (PaymentDraft) -> Void
    let onDelete: () -> Void

    private var account: AccountDraft? { accounts.first { $0.id == p.accountID } ?? accounts.first }

    var body: some View {
        OnbCard {
            Button {
                withAnimation(.snappy) { p.enabled.toggle() }
                if p.enabled { onEnable(p) }
            } label: {
                HStack(spacing: 12) {
                    OnbIcon(name: p.icon, tint: isIncome ? Theme.income : Theme.accent)
                    if p.isCustom && p.enabled {
                        TextField(isIncome ? "onb.pay.incomeName" : "onb.pay.name", text: $p.name).font(.app(.body, .semibold))
                    } else {
                        Text(p.name).font(.app(.body, .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    OnbCheck(on: p.enabled)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if p.enabled {
                if !p.isCustom {
                    OnbField(label: "onb.pay.nameLabel") { TextField("onb.pay.name", text: $p.name) }
                }
                OnbField(label: showRemaining ? "onb.loan.payment" : "field.amount") {
                    HStack {
                        TextField("0", text: $p.amountText).keyboardType(.decimalPad).font(.app(.title3).monospacedDigit())
                        CurrencySymbolView(code: account?.currency ?? "").font(.app(.title3)).foregroundStyle(.secondary)
                    }
                }
                if !showRemaining {
                    OnbPickRow(label: "onb.pay.how") {
                        Picker("onb.pay.how", selection: $p.cadence) {
                            ForEach(cadences, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden()
                    }
                }
                dayPickers
                if showRemaining {
                    OnbField(label: "onb.loan.remaining") {
                        TextField("onb.loan.remainingPlaceholder", text: $p.remainingText).keyboardType(.numberPad)
                    }
                    OnbField(label: "onb.loan.debt") {
                        HStack {
                            TextField("0", text: $p.debtText).keyboardType(.decimalPad).font(.app(.title3).monospacedDigit())
                            CurrencySymbolView(code: account?.currency ?? "").font(.app(.title3)).foregroundStyle(.secondary)
                        }
                    }
                    if p.remainingPayments == nil {
                        Label("onb.loan.needOne", systemImage: "exclamationmark.circle").font(.app(.footnote)).foregroundStyle(Theme.warn)
                    }
                }
                if accounts.count > 1 {
                    OnbPickRow(label: isIncome ? "onb.pay.toAccount" : "onb.pay.fromAccount") {
                        Picker("", selection: Binding(get: { account?.id }, set: { p.accountID = $0 })) {
                            ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                }
                if p.isCustom {
                    Button(role: .destructive, action: onDelete) { Label("common.delete", systemImage: "trash").font(.app(.subheadline)) }
                }
            }
        }
    }

    @ViewBuilder private var dayPickers: some View {
        switch showRemaining ? PaymentCadence.monthly : p.cadence {
        case .monthly:
            OnbPickRow(label: "onb.pay.day") { dayPicker($p.day) }
        case .twiceMonthly:
            OnbPickRow(label: "onb.pay.day") { dayPicker($p.day) }
            OnbPickRow(label: "onb.pay.day2") { dayPicker($p.day2) }
        case .weekly, .biweekly:
            OnbPickRow(label: "onb.pay.weekday") {
                Picker("onb.pay.weekday", selection: $p.weekday) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1].capitalized).tag($0) }
                }.labelsHidden()
            }
        case .yearly:
            DatePicker("onb.pay.date", selection: $p.date, displayedComponents: .date).font(.app(.subheadline))
        }
    }

    private func dayPicker(_ day: Binding<Int>) -> some View {
        Picker("onb.pay.day", selection: day) { ForEach(1...28, id: \.self) { Text("\($0)").tag($0) } }.labelsHidden()
    }
}

/// Шаг «кредиты и рассрочки»: платежи по кредитам плюс кредитные карты и линии.
struct OnbLoansStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnbPaymentsStep(header: OnbHeader(icon: "percent", title: "onb.loans.title", subtitle: "onb.loans.subtitle"),
                            items: $draft.loans, accounts: draft.enabledAccounts, cadences: [.monthly],
                            isIncome: false, customCategory: "cat.loans", customIcon: "banknote", addTitle: "onb.loans.add",
                            showRemaining: true, footer: nil, footerAmount: 0, currency: draft.currency,
                            onEnable: { draft.ensureCategory($0.categoryKey) })

            VStack(alignment: .leading, spacing: 14) {
                Text("onb.credit.title").font(.app(.title3, .bold))
                Text("onb.credit.subtitle").font(.app(.subheadline)).foregroundStyle(.secondary)
                ForEach($draft.credits) { $c in
                    OnbCard {
                        HStack(spacing: 12) {
                            OnbIcon(name: AccountKind.creditLine.icon)
                            TextField("onb.credit.namePlaceholder", text: $c.name).font(.app(.body, .semibold))
                        }
                        OnbField(label: "onb.credit.limit") { moneyField($c.limitText) }
                        OnbField(label: "onb.credit.debt") { moneyField($c.debtText) }
                        OnbField(label: "onb.credit.apr") {
                            HStack {
                                TextField("0", text: $c.aprText).keyboardType(.decimalPad).font(.app(.title3).monospacedDigit())
                                Text("%").font(.app(.title3)).foregroundStyle(.secondary)
                            }
                        }
                        OnbPickRow(label: "onb.credit.statementDay") {
                            Picker("", selection: $c.statementDay) { ForEach(1...28, id: \.self) { Text("\($0)").tag($0) } }.labelsHidden()
                        }
                        Stepper(fmt("onb.credit.dueDays", c.dueDays), value: $c.dueDays, in: 1...60).font(.app(.subheadline))
                        Button(role: .destructive) { draft.credits.removeAll { $0.id == c.id } } label: {
                            Label("common.delete", systemImage: "trash").font(.app(.subheadline))
                        }
                    }
                }
                Button {
                    withAnimation(.snappy) { draft.credits.append(CreditDraft()) }
                } label: {
                    Label("onb.credit.add", systemImage: "plus.circle.fill").font(.app(.subheadline, .semibold))
                }
                if !draft.credits.isEmpty {
                    Text("onb.credit.hint").font(.app(.footnote)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func moneyField(_ text: Binding<String>) -> some View {
        HStack {
            TextField("0", text: text).keyboardType(.decimalPad).font(.app(.title3).monospacedDigit())
            CurrencySymbolView(code: draft.currency).font(.app(.title3)).foregroundStyle(.secondary)
        }
    }
}
