import SwiftUI
import LedgerCore

/// Шаг «бюджеты»: круговая диаграмма делит доход на обязательное, желания и накопления.
/// Шаблон раскладывает суммы по красивым круглым значениям, любую можно поправить слайдером или числом.
struct OnbBudgetStep: View {
    @Bindable var draft: OnboardingDraft
    @State private var incomeText = ""

    private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

    private var slices: [OnbSlice] {
        let free = max(draft.base - draft.allocated, 0)
        let all = [OnbSlice(id: "needs", value: double(draft.amount(of: .needs)), color: BudgetGroup.needs.tint),
                   OnbSlice(id: "wants", value: double(draft.amount(of: .wants)), color: BudgetGroup.wants.tint),
                   OnbSlice(id: "savings", value: double(draft.amount(of: .savings)), color: BudgetGroup.savings.tint),
                   OnbSlice(id: "free", value: double(free), color: Color.white.opacity(0.12))].filter { $0.value > 0 }
        return all.isEmpty ? [OnbSlice(id: "empty", value: 1, color: Color.white.opacity(0.08))] : all
    }

    private func percent(_ d: Decimal) -> Int {
        draft.base > 0 ? Int((double(d) / double(draft.base) * 100).rounded()) : 0
    }

    private var over: Decimal { max(draft.allocated - draft.base, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnbHeader(icon: "chart.pie", title: "onb.budget.title", subtitle: "onb.budget.subtitle")
            chartCard
            templates
            OnbCard {
                OnbField(label: "onb.budget.income") {
                    HStack {
                        TextField("0", text: $incomeText).keyboardType(.decimalPad).font(.app(.title3).monospacedDigit())
                        CurrencySymbolView(code: draft.currency).font(.app(.title3)).foregroundStyle(.secondary)
                    }
                }
                if draft.base <= 0 {
                    Label("onb.budget.noIncome", systemImage: "exclamationmark.circle").font(.app(.footnote)).foregroundStyle(Theme.warn)
                }
            }
            ForEach([BudgetGroup.needs, .wants], id: \.self) { group in
                let cats = draft.categories.filter { $0.enabled && $0.group == group }
                if !cats.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        groupHeader(group)
                        OnbCard {
                            ForEach(cats) { c in
                                let fixed = draft.fixedByCategory[c.key] ?? 0
                                OnbSliderRow(icon: c.icon, color: c.color, title: c.name, value: binding(c.id),
                                             maxValue: draft.base * 6 / 10, step: draft.step, currency: draft.currency, fixed: fixed)
                                if c.id != cats.last?.id { Divider().overlay(.white.opacity(0.06)) }
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                groupHeader(.savings)
                OnbCard {
                    OnbSliderRow(icon: "leaf", color: "green", title: String(localized: "onb.group.savings"),
                                 value: Binding(get: { draft.savings }, set: { new in
                                     guard draft.savings != new else { return }
                                     draft.savings = new; draft.template = nil
                                 }),
                                 maxValue: draft.base, step: draft.step, currency: draft.currency, fixed: 0)
                }
                Text("onb.budget.savingsHint").font(.app(.footnote)).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            draft.syncBudgets()
            incomeText = "\(draft.monthlyIncome)"
        }
        .onChange(of: incomeText) {
            let v = Decimal.parse(incomeText) ?? 0
            draft.incomeOverride = v == draft.autoMonthlyIncome ? nil : v
            if let t = BudgetSplit.templates.first(where: { $0.id == draft.template }) { draft.applyTemplate(t) }
        }
    }

    private func binding(_ id: UUID) -> Binding<Decimal> {
        Binding(get: { draft.amounts[id] ?? 0 }, set: { new in
            guard draft.amounts[id] != new else { return }
            draft.amounts[id] = new; draft.template = nil
        })
    }

    private func groupHeader(_ group: BudgetGroup) -> some View {
        HStack {
            Circle().fill(group.tint).frame(width: 10, height: 10)
            Text(group.title).font(.app(.subheadline, .semibold))
            Spacer()
            MoneyText(amount: draft.amount(of: group), code: draft.currency).font(.app(.subheadline, .semibold))
            Text("\(percent(draft.amount(of: group)))%").font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    // MARK: Диаграмма

    private var chartCard: some View {
        OnbCard {
            OnbDonut(slices: slices)
                .frame(height: 200)
            .overlay {
                VStack(spacing: 2) {
                    Text(draft.base > 0 ? "\(percent(draft.amount(of: .needs))) · \(percent(draft.amount(of: .wants))) · \(percent(draft.amount(of: .savings)))" : "—")
                        .font(.app(.title2, .bold).monospacedDigit())
                    Text("onb.budget.ofIncome").font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("onb.budget.chartLabel"))
            .accessibilityValue(Text("\(percent(draft.amount(of: .needs))) / \(percent(draft.amount(of: .wants))) / \(percent(draft.amount(of: .savings)))"))

            HStack(spacing: 14) {
                ForEach(BudgetGroup.allCases, id: \.self) { g in
                    HStack(spacing: 5) {
                        Circle().fill(g.tint).frame(width: 8, height: 8)
                        Text(g.title).font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            if over > 0 {
                Label { HStack(spacing: 4) { Text("onb.budget.over"); MoneyText(amount: over, code: draft.currency) } }
                    icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.app(.footnote, .semibold)).foregroundStyle(Theme.expense)
            } else if draft.base > 0, draft.base - draft.allocated > 0 {
                HStack(spacing: 4) { Text("onb.budget.free"); MoneyText(amount: draft.base - draft.allocated, code: draft.currency) }
                    .font(.app(.footnote)).foregroundStyle(.secondary)
            }
        }
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("onb.budget.templates").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BudgetSplit.templates) { t in
                        Button { withAnimation(.snappy) { draft.applyTemplate(t) } } label: {
                            Text(t.id).monospacedDigit().onbChip(selected: draft.template == t.id)
                        }.buttonStyle(.plain)
                    }
                    Text("onb.budget.custom").onbChip(selected: draft.template == nil).opacity(draft.template == nil ? 1 : 0.4)
                }
            }
            Text("onb.budget.order").font(.app(.caption)).foregroundStyle(.secondary)
        }
    }
}

/// Одна категория: название, слайдер и поле для точной суммы. Слайдер и поле всегда показывают одно и то же число.
struct OnbSliderRow: View {
    let icon: String
    let color: String
    let title: String
    @Binding var value: Decimal
    let maxValue: Decimal
    let step: Decimal
    let currency: String
    let fixed: Decimal
    @State private var text = ""
    @FocusState private var focused: Bool

    private var stepD: Double { max(NSDecimalNumber(decimal: step).doubleValue, 1) }
    private var upper: Double { max(NSDecimalNumber(decimal: max(maxValue, value)).doubleValue, stepD) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                OnbCatBadge(icon: icon, color: color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if fixed > 0 {
                        Text(fmt("onb.budget.planned", MoneyText.plain(fixed, code: currency)))
                            .font(.app(.caption)).foregroundStyle(value < fixed ? Theme.warn : Color.secondary)
                    }
                }
                Spacer()
                TextField("0", text: $text)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focused)
                    .font(.app(.body, .semibold).monospacedDigit())
                    .frame(width: 90)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                CurrencySymbolView(code: currency).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { NSDecimalNumber(decimal: value).doubleValue },
                                  set: { value = Decimal(($0 / stepD).rounded()) * step }),
                   in: 0...upper, step: stepD)
                .tint(Theme.brand)
        }
        .padding(.vertical, 2)
        .onAppear { text = "\(value)" }
        .onChange(of: text) { if focused { value = max(Decimal.parse(text) ?? 0, 0) } }
        .onChange(of: value) { if !focused { text = "\(value)" } }
        .onChange(of: focused) { if !focused { text = "\(value)" } }
    }
}

struct OnbSlice: Identifiable { let id: String; let value: Double; let color: Color }

/// Кольцо из цветных дуг. Нарисовано вручную: дуги плавно растут и сжимаются, когда меняются суммы.
struct OnbDonut: View {
    let slices: [OnbSlice]

    private struct Arc: Identifiable { let id: String; let from: Double; let to: Double; let color: Color }

    private var arcs: [Arc] {
        let total = slices.reduce(0) { $0 + max($1.value, 0) }
        guard total > 0 else { return [] }
        let gap = slices.count > 1 ? 0.006 : 0
        var start = 0.0
        return slices.map { s in
            let share = max(s.value, 0) / total
            defer { start += share }
            return Arc(id: s.id, from: start + gap / 2, to: max(start + share - gap / 2, start + gap / 2), color: s.color)
        }
    }

    var body: some View {
        GeometryReader { g in
            let line = min(g.size.width, g.size.height) * 0.14
            ZStack {
                ForEach(arcs) { a in
                    Circle().trim(from: a.from, to: a.to)
                        .stroke(a.color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            .padding(line / 2)
            .frame(width: g.size.width, height: g.size.height)
            .animation(.snappy(duration: 0.35), value: arcs.map(\.to))
        }
    }
}
