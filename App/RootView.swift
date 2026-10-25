import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(RatesStore.self) private var rates
    @AppStorage(chaosModeKey) private var chaos = false
    @State private var addType: TxType?
    @State private var fanOpen = false
    @State private var tab = 0
    @Environment(\.scenePhase) private var phase
    @Query(filter: #Predicate<LedgerTransaction> { $0.smsReview != 0 }) private var pendingSMS: [LedgerTransaction]
    @State private var showReview = false
    @State private var askBackup = false
    @AppStorage("onboardingDone") private var onboardingDone = false
    @Query private var accounts: [Account]

    /// Знакомство показываем на пустом приложении или если не выбрана основная валюта.
    private var needsOnboarding: Bool { rates.base.isEmpty || (!onboardingDone && accounts.isEmpty) }

    /// При заходе в приложение показываем разбор, если накопились СМС банка.
    private func openReviewIfNeeded() {
        if !pendingSMS.isEmpty, !rates.base.isEmpty, addType == nil { showReview = true }
        else if !needsOnboarding, !AutoBackup.shared.asked, !AutoBackup.shared.hasFolder { askBackup = true }
    }

    var body: some View {
        TabView(selection: $tab) {
            Group {
                if chaos { ChaosHomeView() } else { AccountsView() }
            }
            .tabItem { Label("tab.accounts", systemImage: chaos ? "circle.grid.2x2.fill" : "creditcard") }.tag(0)
            ActivityView().tabItem { Label("tab.activity", systemImage: "list.bullet") }.tag(1)
            BudgetsView().tabItem { Label("tab.budgets", systemImage: "chart.pie") }.tag(2)
            ScheduledView().tabItem { Label("tab.scheduled", systemImage: "repeat") }.tag(3)
            ReportsView().tabItem { Label("tab.reports", systemImage: "chart.xyaxis.line") }.tag(4)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .overlay {
            if fanOpen { Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { withAnimation(.spring(duration: 0.25)) { fanOpen = false } } }
        }
        .overlay(alignment: .bottomTrailing) {
            if !(chaos && tab == 0) { addMenu }
        }
        .sheet(item: $addType) { AddTransactionView(type: $0) }
        .sheet(isPresented: $showReview) { SMSReviewView() }
        .sheet(isPresented: $askBackup, onDismiss: { AutoBackup.shared.asked = true }) { BackupPromptSheet() }
        .onAppear(perform: openReviewIfNeeded)
        .onChange(of: phase) {
            if phase == .active { openReviewIfNeeded(); EveningNotifier.shared.reschedule() }
            if phase == .background { AutoBackup.shared.flush() }
        }
        .fullScreenCover(isPresented: Binding(get: { needsOnboarding }, set: { _ in })) {
            OnboardingFlow(initialCurrency: rates.base.isEmpty ? Currencies.deviceDefault : rates.base) { onboardingDone = true }
        }
    }

    /// «+» раскрывается в три кнопки: у каждого типа операции свой цвет и стрелка.
    private var addMenu: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if fanOpen {
                ForEach([TxType.expense, .income, .transfer], id: \.self) { t in
                    Button {
                        fanOpen = false; addType = t
                    } label: {
                        HStack(spacing: 10) {
                            Text(t.label).font(.app(.subheadline, .semibold)).foregroundStyle(.primary)
                            Image(systemName: t.glyph).font(.app(.headline, .bold)).foregroundStyle(Theme.onBrand)
                                .frame(width: 40, height: 40).background(t.tint, in: Circle())
                        }
                        .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 4)
                        .background(Theme.raised, in: Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.08))).shadow(radius: 6, y: 3)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            Button {
                withAnimation(.spring(duration: 0.3)) { fanOpen.toggle() }
            } label: {
                Image(systemName: "plus").font(.app(.title2, .bold)).foregroundStyle(Theme.onBrand)
                    .rotationEffect(.degrees(fanOpen ? 45 : 0))
                    .frame(width: 56, height: 56).background(Theme.brand, in: Circle()).shadow(color: Theme.brand.opacity(0.35), radius: 14, y: 6)
            }
            .accessibilityLabel(Text("add.title"))
        }
        .padding(.trailing, 20).padding(.bottom, 64)
    }
}
