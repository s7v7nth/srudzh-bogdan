import SwiftUI
import UIKit
import LedgerCore

extension EveningNotifier {
    /// Время сводки как дата сегодняшнего дня: для DatePicker.
    var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: self.minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); self.minutes = (c.hour ?? 21) * 60 + (c.minute ?? 0) })
    }
}

/// Шаг онбординга «Вечерняя сводка»: пример уведомления и выбор времени.
struct OnbEveningStep: View {
    let currency: String
    @Bindable var notifier = EveningNotifier.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnbHeader(icon: "moon.stars", title: "digest.step.title", subtitle: "digest.step.subtitle")
            EveningPreview(currency: currency)
            OnbCard {
                Toggle(isOn: $notifier.enabled.animation(.snappy)) { Text("digest.toggle").font(.app(.body, .semibold)) }
                    .tint(Theme.brand)
                if notifier.enabled {
                    Divider().overlay(.white.opacity(0.06))
                    DatePicker("digest.time", selection: notifier.timeBinding, displayedComponents: .hourAndMinute)
                        .font(.app(.subheadline))
                }
            }
            if notifier.enabled {
                Text("digest.step.permission").font(.app(.footnote)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Как будет выглядеть уведомление: пример с выдуманными цифрами.
private struct EveningPreview: View {
    let currency: String

    var body: some View {
        let sample = EveningDigest.make(date: .now, spent: 47, pending: 3, budgetLeft: nil, tomorrow: [])
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onBrand)
                .frame(width: 34, height: 34).background(Theme.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("digest.title.review").font(.app(.subheadline, .semibold))
                Text(EveningNotifier.body(sample, base: currency)).font(.app(.subheadline)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Раздел настроек: включить сводку, время и подсказка, если уведомления запрещены.
struct EveningDigestSettingsSection: View {
    @Bindable var notifier = EveningNotifier.shared

    var body: some View {
        Section {
            Toggle("digest.toggle", isOn: $notifier.enabled)
            if notifier.enabled {
                DatePicker("digest.time", selection: notifier.timeBinding, displayedComponents: .hourAndMinute)
                if notifier.authorization == .denied {
                    Button("digest.openSettings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
        } header: { Text("digest.step.title") } footer: {
            Text(notifier.enabled && notifier.authorization == .denied ? "digest.denied" : "digest.footer")
        }
        .task { await notifier.refreshAuthorization() }
        .onChange(of: notifier.enabled) { if notifier.enabled, notifier.authorization == .notDetermined { Task { await notifier.requestPermission() } } }
    }
}
