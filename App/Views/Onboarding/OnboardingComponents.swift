import SwiftUI
import LedgerCore

/// Заголовок шага: крупная иконка, фраза-вопрос и пояснение.
struct OnbHeader: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.onBrand)
                .frame(width: 56, height: 56).background(Theme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(.app(.largeTitle, .bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.app(.body)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }
}

/// Карточка на тёмной подложке.
struct OnbCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// Кружок-галочка для строк, которые включаются и выключаются.
struct OnbCheck: View {
    let on: Bool
    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24)).foregroundStyle(on ? Theme.accent : Color.secondary.opacity(0.6))
            .accessibilityHidden(true)
    }
}

/// Круглая иконка строки в цвете акцента.
struct OnbIcon: View {
    let name: String
    var tint: Color = Theme.accent
    var body: some View {
        Image(systemName: name).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 34, height: 34).background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Поле суммы на тёмной плашке внутри карточки.
struct OnbField<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.app(.caption)).foregroundStyle(.secondary)
            content
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Строка «подпись слева, выбор справа» внутри карточки.
struct OnbPickRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        HStack { Text(label).font(.app(.subheadline)); Spacer(); content }
    }
}

extension View {
    /// Кнопка-плашка в стиле онбординга.
    func onbChip(selected: Bool) -> some View {
        self.font(.app(.subheadline, .semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(selected ? Theme.onBrand : Color.primary)
            .background(selected ? Theme.brand : Theme.raised, in: Capsule())
    }
}
