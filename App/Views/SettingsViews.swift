import SwiftUI

/// Выбор основной валюты: при первом запуске и в настройках.
struct BaseCurrencyView: View {
    @Environment(RatesStore.self) private var rates
    @Environment(\.dismiss) private var dismiss
    var isOnboarding = false
    @State private var selected = Currencies.deviceDefault

    var body: some View {
        let content = List {
            if isOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("onboarding.title").font(.app(.largeTitle, .bold)).fixedSize(horizontal: false, vertical: true)
                        Text("onboarding.subtitle").foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }
            Section {
                ForEach(Currencies.all) { c in
                    Button {
                        selected = c.code
                        if !isOnboarding { rates.base = c.code }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(c.name).foregroundStyle(.primary)
                                Text(c.code).font(.app(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            CurrencySymbolView(code: c.code).foregroundStyle(.secondary)
                            if (isOnboarding ? selected : rates.base) == c.code {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } footer: {
                if !isOnboarding { Text("base.footer") }
            }
        }
        .contentMargins(.bottom, isOnboarding ? 90 : 0, for: .scrollContent)

        if isOnboarding {
            content.overlay(alignment: .bottom) {
                Button { rates.base = selected } label: {
                    Text("onboarding.continue").font(.app(.headline)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(Theme.brand).foregroundStyle(Theme.onBrand).padding()
                .background(.bar)
            }
        } else {
            content.navigationTitle("settings.baseCurrency").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SettingsView: View {
    @Environment(RatesStore.self) private var rates
    @Environment(\.dismiss) private var dismiss
    @AppStorage(chaosModeKey) private var chaos = false
    @AppStorage(scheduleWindowKey) private var windowDays = 7
    @State private var showOnboarding = false
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $chaos) {
                        HStack(spacing: 10) {
                            Image("Smiley").resizable().scaledToFit().frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("settings.chaos")
                        }
                    }
                    if chaos {
                        Picker("settings.window", selection: $windowDays) {
                            ForEach(scheduleWindowOptions, id: \.self) { Text(fmt("settings.window.value", $0)).tag($0) }
                        }
                    }
                } footer: { Text("settings.chaosFooter") }
                Section {
                    NavigationLink {
                        BaseCurrencyView()
                    } label: {
                        HStack {
                            Text("settings.baseCurrency"); Spacer()
                            Text(rates.base).foregroundStyle(.secondary)
                            CurrencySymbolView(code: rates.base).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("settings.categories") { CategoriesView() }
                    NavigationLink("sms.title") { SMSSettingsView() }
                    Button { showReset = true } label: {
                        Label("settings.onboarding", systemImage: "wand.and.stars")
                    }
                }
                Section {
                    LabeledContent("rates.updated") {
                        if let d = rates.lastUpdated { Text(d.formatted(date: .abbreviated, time: .shortened)) }
                        else { Text("rates.builtin") }
                    }
                    if rates.lastError {
                        Label("rates.error", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                    }
                    Button {
                        Task { await rates.refresh() }
                    } label: {
                        HStack { Text("rates.refresh"); Spacer(); if rates.isRefreshing { ProgressView() } }
                    }.disabled(rates.isRefreshing)
                } header: { Text("rates.header") } footer: { Text("rates.footer") }
            }
            .themedScreen()
            .navigationTitle("settings.title")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } } }
            .sheet(isPresented: $showReset) {
                ResetConfirmView { showReset = false; showOnboarding = true }
                    .presentationDetents([.medium])
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingFlow(initialCurrency: rates.base, isRerun: true) { showOnboarding = false }
            }
        }
    }
}


/// Подтверждение перед повторным онбордингом: он заменяет все данные, поэтому нужно написать слово.
struct ResetConfirmView: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    private let word = String(localized: "onb.reset.word")
    private var ok: Bool { typed.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(word) == .orderedSame }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("onb.reset.title", systemImage: "exclamationmark.triangle.fill").font(.app(.title2, .bold)).foregroundStyle(.red)
            Text("onb.reset.body").font(.app(.body))
            Text("onb.reset.prompt").font(.app(.footnote)).foregroundStyle(.secondary)
            Text(word).font(.app(.headline)).textSelection(.disabled)
            TextField(word, text: $typed).textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters).autocorrectionDisabled()
            HStack {
                Button("common.cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("onb.reset.go", role: .destructive, action: onConfirm).buttonStyle(.borderedProminent).disabled(!ok)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}
