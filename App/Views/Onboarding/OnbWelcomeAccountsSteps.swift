import SwiftUI
import LedgerCore

struct OnbWelcomeStep: View {
    let draft: OnboardingDraft
    let isRerun: Bool
    #if DEBUG
    @State private var showImport = CommandLine.arguments.contains("-csvSheet")
    #else
    @State private var showImport = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnbHeader(icon: "hand.wave", title: "onb.welcome.title", subtitle: "onb.welcome.subtitle")
            if isRerun {
                Label("onb.rerun.note", systemImage: "info.circle").font(.app(.footnote)).foregroundStyle(Theme.warn)
            }
            importCard
            Text("onb.currency.label").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary).padding(.top, 4)
            OnbCard {
                ForEach(Currencies.all) { c in
                    Button { draft.setCurrency(c.code) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).foregroundStyle(.primary)
                                Text(c.code).font(.app(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            CurrencySymbolView(code: c.code).foregroundStyle(.secondary)
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent).opacity(draft.currency == c.code ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if c.code != Currencies.all.last?.code { Divider().overlay(.white.opacity(0.06)) }
                }
            }
        }
    }
}

extension OnbWelcomeStep {
    /// Загрузка истории из CSV: счета и категории подтянутся из файла, эти шаги онбординга пропустятся.
    @ViewBuilder fileprivate var importCard: some View {
        OnbCard {
            if let l = draft.imported {
                HStack(spacing: 12) {
                    OnbIcon(name: "checkmark.circle.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("onb.import.done").font(.app(.body, .semibold))
                        Text("onb.import.doneDetail \(l.entries.count) \(l.accounts.count)").font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("onb.import.remove") { withAnimation(.snappy) { draft.clearImport() } }.font(.app(.subheadline))
                }
            } else {
                Text("onb.import.title").font(.app(.body, .semibold))
                Text("onb.import.subtitle").font(.app(.footnote)).foregroundStyle(.secondary)
                Button { showImport = true } label: { Label("onb.import.button", systemImage: "square.and.arrow.down").onbChip(selected: true) }
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showImport) { OnbImportSheet { draft.applyImport($0) } }
    }
}

struct OnbAccountsStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnbHeader(icon: "creditcard", title: "onb.accounts.title", subtitle: "onb.accounts.subtitle")
            ForEach($draft.accounts) { $a in
                OnbCard {
                    Button { withAnimation(.snappy) { a.enabled.toggle() } } label: {
                        HStack(spacing: 12) {
                            OnbIcon(name: a.kind.icon)
                            if a.isCustom && a.enabled {
                                TextField("onb.acc.namePlaceholder", text: $a.name).font(.app(.body, .semibold))
                            } else {
                                Text(a.name).font(.app(.body, .semibold)).foregroundStyle(.primary)
                            }
                            Spacer()
                            OnbCheck(on: a.enabled)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if a.enabled {
                        if !a.isCustom {
                            OnbField(label: "onb.acc.name") { TextField("onb.acc.namePlaceholder", text: $a.name) }
                        } else {
                            Picker("onb.acc.type", selection: $a.kind) {
                                ForEach([AccountKind.card, .cash, .savings], id: \.self) { Text($0.label).tag($0) }
                            }
                        }
                        OnbPickRow(label: "account.currency") {
                            Picker("account.currency", selection: $a.currency) {
                                ForEach(Currencies.all) { Text($0.code).tag($0.code) }
                            }.labelsHidden()
                        }
                        OnbField(label: "onb.acc.balance") {
                            HStack {
                                TextField("0", text: $a.balanceText).keyboardType(.decimalPad).font(.app(.title3).monospacedDigit())
                                CurrencySymbolView(code: a.currency).font(.app(.title3)).foregroundStyle(.secondary)
                            }
                        }
                        if a.isCustom {
                            Button(role: .destructive) { draft.accounts.removeAll { $0.id == a.id } } label: {
                                Label("common.delete", systemImage: "trash").font(.app(.subheadline))
                            }
                        }
                    }
                }
            }
            Button {
                withAnimation(.snappy) {
                    var a = AccountDraft(kind: .card, name: "", currency: draft.currency, enabled: true)
                    a.isCustom = true
                    draft.accounts.append(a)
                }
            } label: {
                Label("onb.acc.add", systemImage: "plus.circle.fill").font(.app(.subheadline, .semibold))
            }
            .padding(.top, 2)
            Text("onb.accounts.hint").font(.app(.footnote)).foregroundStyle(.secondary)
            if draft.enabledAccounts.isEmpty {
                Label("onb.accounts.need", systemImage: "exclamationmark.circle").font(.app(.footnote)).foregroundStyle(Theme.warn)
            }
        }
    }
}
