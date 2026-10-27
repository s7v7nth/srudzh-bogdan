import SwiftUI
import SwiftData
import LedgerCore

func balance(of a: Account, includePending: Bool = true) -> Decimal {
    Balances.balance(a.entries, includePending: includePending)
}

/// Строка с подстановкой значений в переведённый шаблон (%@, %lld).
func fmt(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
    String(format: String(localized: key), arguments: args)
}

extension Color {
    static func category(_ name: String) -> Color {
        switch name {
        case "red": .red; case "orange": .orange; case "yellow": .yellow; case "green": .green; case "mint": .mint
        case "teal": .teal; case "blue": .blue; case "indigo": .indigo; case "purple": .purple; case "pink": .pink
        case "brown": .brown; default: .gray
        }
    }
}

let categoryColorNames = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "brown", "gray"]
let categoryIcons = ["cart", "bus", "house", "cup.and.saucer", "gamecontroller", "cross.case", "tshirt", "percent",
                     "ellipsis.circle", "banknote", "gift", "plus.circle", "fork.knife", "car", "fuelpump", "airplane",
                     "bag", "book", "graduationcap", "pawprint", "wifi", "phone", "bolt", "drop", "film", "music.note",
                     "figure.run", "heart", "wrench.and.screwdriver", "tag"]

struct CategoryBadge: View {
    let category: Category?
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            Circle().fill(Color.category(category?.colorName ?? "gray").opacity(0.18))
            Image(systemName: category?.icon ?? "questionmark").font(.system(size: size * 0.45))
                .foregroundStyle(Color.category(category?.colorName ?? "gray"))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CurrencyPicker: View {
    let title: LocalizedStringKey
    @Binding var code: String
    var body: some View {
        Picker(title, selection: $code) {
            ForEach(Currencies.all) { c in Text("\(c.code) · \(c.name)").tag(c.code) }
        }
    }
}

/// Поле суммы с символом валюты справа.
struct AmountField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let code: String
    /// Сразу ставит курсор в поле и открывает клавиатуру: в новой операции первым делом вводят сумму.
    var autoFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField(title, text: $text).keyboardType(.decimalPad).font(.app(.title3).monospacedDigit())
                .focused($focused)
            CurrencySymbolView(code: code).font(.app(.title3)).foregroundStyle(.secondary)
        }
        .task {
            guard autoFocus else { return }
            // Окно ещё выезжает: фокус, выставленный сразу, iOS игнорирует.
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }
}

extension Date {
    var shortDay: String { formatted(date: .abbreviated, time: .omitted) }
}
