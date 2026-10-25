import SwiftUI
import SwiftData
import LedgerCore

enum OnbStep: Int, CaseIterable {
    case welcome, accounts, income, categories, bills, loans, subscriptions, budgets, evening, backup, summary
}

/// Пошаговая настройка: валюта, счета, доходы, категории, платежи, кредиты, подписки, бюджеты, итог.
/// Ответы копятся в черновике и попадают в базу только по кнопке «Начать» на последнем шаге.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @State private var draft: OnboardingDraft
    @State private var step: OnbStep = .welcome
    @State private var goingForward = true
    @State private var keyboardUp = false
    /// Повторный запуск из настроек: есть кнопка закрыть.
    let isRerun: Bool
    let onFinish: () -> Void

    init(initialCurrency: String, isRerun: Bool = false, onFinish: @escaping () -> Void) {
        let d = OnboardingDraft(currency: initialCurrency)
        #if DEBUG
        let args = CommandLine.arguments
        if args.contains("-onbDemo") { d.applyDemo() }
        // -onbCSV <путь>: сразу загрузить файл, как будто его выбрали на первом экране.
        if let i = args.firstIndex(of: "-onbCSV"), i + 1 < args.count {
            let m = CSVImportModel()
            if m.load(.success(URL(fileURLWithPath: args[i + 1]))) { d.applyImport(m.ledger) }
        }
        if let i = args.firstIndex(of: "-onbStep"), i + 1 < args.count, let n = Int(args[i + 1]), let s = OnbStep(rawValue: n) { _step = State(initialValue: s) }
        #endif
        _draft = State(initialValue: d)
        self.isRerun = isRerun
        self.onFinish = onFinish
    }

    private var isLast: Bool { step == .summary }

    /// После загрузки CSV счета и категории уже известны, эти шаги пропускаются.
    private var steps: [OnbStep] {
        draft.imported == nil ? OnbStep.allCases : OnbStep.allCases.filter { $0 != .accounts && $0 != .categories }
    }
    private var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    /// Шаг пустой: человек ничего не заполнил, кнопка превращается в «Пропустить».
    private var isEmptyStep: Bool {
        switch step {
        case .income: !draft.incomes.contains(where: \.isActive)
        case .bills: !draft.bills.contains(where: \.isActive)
        case .loans: !draft.loans.contains(where: \.isActive) && draft.credits.isEmpty
        case .subscriptions: !draft.subscriptions.contains(where: \.isActive)
        case .evening: !EveningNotifier.shared.enabled
        case .backup: !AutoBackup.shared.hasFolder
        default: false
        }
    }

    private var canContinue: Bool { step != .accounts || !draft.enabledAccounts.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    content
                        .id(step)
                        .transition(.asymmetric(insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                                                removal: .opacity))
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                if !keyboardUp { footer }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onbKeyboardTools()
        }
        .interactiveDismissDisabled()
    }

    // MARK: Шапка и подвал

    private var header: some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: { Image(systemName: "chevron.left").font(.app(.headline)) }
                .opacity(step == .welcome ? 0 : 1).disabled(step == .welcome)
                .accessibilityLabel(Text("onb.back"))
            ProgressView(value: Double(stepNumber), total: Double(steps.count))
                .progressViewStyle(CapsuleBar(tint: Theme.brand))
            Text("\(stepNumber)/\(steps.count)").font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary)
            if isRerun {
                Button(action: onFinish) { Image(systemName: "xmark").font(.app(.subheadline, .semibold)) }
                    .accessibilityLabel(Text("common.cancel"))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var footer: some View {
        Button(action: advance) {
            Text(buttonTitle).font(.app(.headline)).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).tint(Theme.brand).foregroundStyle(Theme.onBrand)
        .disabled(!canContinue)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    private var buttonTitle: LocalizedStringKey {
        if isLast { return "onb.finish" }
        if step == .welcome { return "onb.start" }
        return isEmptyStep ? "onb.skip" : "onb.next"
    }

    // MARK: Шаги

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: OnbWelcomeStep(draft: draft, isRerun: isRerun, onRestored: onFinish)
        case .accounts: OnbAccountsStep(draft: draft)
        case .income:
            OnbPaymentsStep(header: OnbHeader(icon: "arrow.down.circle", title: "onb.income.title", subtitle: "onb.income.subtitle"),
                            items: $draft.incomes, accounts: draft.enabledAccounts, cadences: [.monthly, .twiceMonthly, .biweekly, .weekly, .yearly],
                            isIncome: true, customCategory: "cat.otherIncome", customIcon: "plus.circle", addTitle: "onb.income.add",
                            footer: draft.autoMonthlyIncome > 0 ? "onb.income.total" : nil,
                            footerAmount: draft.autoMonthlyIncome, currency: draft.currency, onEnable: { _ in })
        case .categories: OnbCategoriesStep(draft: draft)
        case .bills:
            OnbPaymentsStep(header: OnbHeader(icon: "house", title: "onb.bills.title", subtitle: "onb.bills.subtitle"),
                            items: $draft.bills, accounts: draft.enabledAccounts, cadences: [.monthly, .twiceMonthly, .weekly, .yearly],
                            isIncome: false, customCategory: "cat.other", customIcon: "tag", addTitle: "onb.bills.add",
                            footer: nil, footerAmount: 0, currency: draft.currency, onEnable: { draft.ensureCategory($0.categoryKey) })
        case .loans:
            OnbLoansStep(draft: draft)
        case .subscriptions:
            OnbPaymentsStep(header: OnbHeader(icon: "play.rectangle", title: "onb.subs.title", subtitle: "onb.subs.subtitle"),
                            items: $draft.subscriptions, accounts: draft.enabledAccounts, cadences: [.monthly, .yearly, .weekly],
                            isIncome: false, customCategory: "cat.subscriptions", customIcon: "star", addTitle: "onb.subs.add",
                            footer: nil, footerAmount: 0, currency: draft.currency, onEnable: { draft.ensureCategory($0.categoryKey) })
        case .budgets: OnbBudgetStep(draft: draft)
        case .evening: OnbEveningStep(currency: draft.currency)
        case .backup: OnbBackupStep()
        case .summary: OnbSummaryStep(draft: draft)
        }
    }

    // MARK: Переходы

    private func advance() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // Разрешение на уведомления спрашиваем, когда человек выбрал время сводки и понятно, зачем оно.
        if step == .evening, EveningNotifier.shared.enabled { Task { await EveningNotifier.shared.requestPermission() } }
        if isLast { finish() } else { move(1) }
    }

    private func move(_ delta: Int) {
        guard let at = steps.firstIndex(of: step), steps.indices.contains(at + delta) else { return }
        let next = steps[at + delta]
        goingForward = delta > 0
        withAnimation(.snappy(duration: 0.3)) { step = next }
    }

    private func finish() {
        OnboardingCommit.run(draft, ctx: ctx, rates: rates, replaceAll: isRerun)
        onFinish()
    }
}
