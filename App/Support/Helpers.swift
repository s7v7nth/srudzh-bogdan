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
    let icon: String
    let colorName: String
    var size: CGFloat = 30

    init(category: Category?, size: CGFloat = 30) {
        self.init(icon: category?.icon, colorName: category?.colorName, size: size)
    }

    init(info: ReportCategory?, size: CGFloat = 30) {
        self.init(icon: info?.icon, colorName: info?.colorName, size: size)
    }

    init(icon: String?, colorName: String?, size: CGFloat = 30) {
        self.icon = icon ?? "questionmark"; self.colorName = colorName ?? "gray"; self.size = size
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.category(colorName).opacity(0.18))
            Image(systemName: icon).font(.system(size: size * 0.45))
                .foregroundStyle(Color.category(colorName))
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
                .toolbar {
                    // Кнопки калькулятора над клавиатурой, пока курсор в этом поле.
                    ToolbarItemGroup(placement: .keyboard) {
                        if focused {
                            ForEach(["+", "−", "×", "÷"], id: \.self) { op in
                                Button(op) { text += op }.font(.app(.title3))
                            }
                            Spacer()
                            Button("=") {
                                if Calculator.hasOperator(text), let r = Calculator.resultText(text, currency: code) { text = r }
                            }
                            .font(.app(.title3).bold())
                        }
                    }
                }
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
    /// «11 дек.»; год пишем, только если дата не в этом году.
    var shortDay: String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return formatted(Calendar.current.isDate(self, equalTo: .now, toGranularity: .year) ? style : style.year())
    }
}

/// Замер тяжёлых расчётов. В отладочной сборке с аргументом -perfLog печатает в консоль, сколько занял расчёт.
func perf<T>(_ name: String, _ work: () -> T) -> T {
    #if DEBUG
    guard perfLogEnabled else { return work() }
    let start = CFAbsoluteTimeGetCurrent()
    let result = work()
    print("perf \(name): \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000)) ms")
    return result
    #else
    return work()
    #endif
}
#if DEBUG
private let perfLogEnabled = CommandLine.arguments.contains("-perfLog")
#endif
