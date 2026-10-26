import SwiftUI
import SwiftData
import CoreText
import LedgerCore

/// Единый «язык» интерфейса: у каждого типа операции свой цвет и своя иконка везде в приложении.
/// Расход красный со стрелкой вниз, доход зелёный со стрелкой вверх, перевод синий со стрелками туда-сюда.
/// Цвета дизайн-системы «тёмный премиум». Приложение всегда тёмное; светлые значения нужны на случай возврата к системной теме.
enum Theme {
    static func hex(_ v: UInt32) -> Color { Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255) }
    static let bg = Color(light: hex(0xf5f4f0), dark: hex(0x0b0d12))
    static let surface = Color(light: hex(0xffffff), dark: hex(0x12151c))
    static let raised = Color(light: hex(0xecebe6), dark: hex(0x1a1f2a))
    /// Фирменный лайм: заливки (главная кнопка, плюс). Текст на нём только onBrand.
    static let brand = hex(0xc5f56b)
    static let onBrand = hex(0x0b0d12)
    /// Акцент для текста и значков: на светлом фоне темнее ради контраста.
    static let accent = Color(light: hex(0x2f6b00), dark: hex(0xc5f56b))
    static let expense = Color(light: hex(0xd63b32), dark: hex(0xff7a70))
    static let income = Color(light: hex(0x12805a), dark: hex(0x4ade9a))
    static let transfer = Color(light: hex(0x2f63d9), dark: hex(0x7aa7ff))
    static let warn = Color(light: hex(0xb86e00), dark: hex(0xffc15a))
}

extension TxType: Identifiable {
    var id: String { rawValue }
    var tint: Color {
        switch self {
        case .expense: Theme.expense
        case .income: Theme.income
        case .transfer: Theme.transfer
        }
    }
    var glyph: String {
        switch self { case .expense: "arrow.down"; case .income: "arrow.up"; case .transfer: "arrow.left.arrow.right" }
    }
}

/// Состояние бюджета: спокойно, близко к лимиту, превышен.
enum BudgetState {
    case ok, warn, over
    init(ratio: Double) { self = ratio >= 1 ? .over : (ratio >= 0.8 ? .warn : .ok) }
    var tint: Color {
        switch self {
        case .ok: Theme.income
        case .warn: Theme.warn
        case .over: Theme.expense
        }
    }
    var icon: String {
        switch self { case .ok: "checkmark.circle.fill"; case .warn: "exclamationmark.circle.fill"; case .over: "xmark.octagon.fill" }
    }
}

/// Цвета «уебанского» режима: счета жёлтые, доходы голубые, расходы зелёные.
enum ChaosPalette {
    static let income = Color(red: 0.22, green: 0.70, blue: 0.98)
    static let account = Color(red: 1.00, green: 0.74, blue: 0.05)
    static let expense = Color(red: 0.10, green: 0.78, blue: 0.52)

    /// Тёмные варианты для текста на цветной подложке: яркий цвет кружка на своём же фоне не читается.
    static let incomeText = Color(light: Color(red: 0.04, green: 0.36, blue: 0.62), dark: Color(red: 0.55, green: 0.82, blue: 1.00))
    static let accountText = Color(light: Color(red: 0.52, green: 0.33, blue: 0.00), dark: Color(red: 1.00, green: 0.82, blue: 0.35))
    static let expenseText = Color(light: Color(red: 0.02, green: 0.40, blue: 0.26), dark: Color(red: 0.45, green: 0.92, blue: 0.72))
    /// Подписи на подложке: чуть темнее серого, чтобы держать контраст.
    static let label = Color.primary.opacity(0.72)

    /// Цветная подложка зоны: стеклу нужно, что преломлять. Бледная, чтобы не спорить с балансом.
    static func zone(_ tint: Color) -> some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(tint.opacity(0.22)).frame(width: 180).blur(radius: 40).offset(x: -110, y: -30)
            Circle().fill(tint.opacity(0.14)).frame(width: 150).blur(radius: 40).offset(x: 130, y: 40)
        }
        .clipped()
    }
}

extension Color {
    /// Цвет, который сам меняется между светлой и тёмной темой.
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

extension View {
    /// Жидкое стекло (iOS 26) с оттенком. На iOS 17-25 запасной вариант: матовое стекло с бликом по краю.
    @ViewBuilder func liquidGlass(tint: Color) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.85)), in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().fill(tint.opacity(0.35)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: tint.opacity(0.3), radius: 6, y: 3)
        }
    }
}

/// Круглая иконка типа операции для списков.
struct TxTypeBadge: View {
    let type: TxType
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            Circle().fill(type.tint.opacity(0.16))
            Image(systemName: type.glyph)
                .font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(type.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Сколько потрачено и каков лимит по бюджету в текущем периоде.
struct BudgetProgress {
    let spent: Decimal
    let limit: Decimal
    let remaining: Decimal
    let currency: String
    let periodEnd: Date
    var ratio: Double { NSDecimalNumber(decimal: spent / max(limit, 1)).doubleValue }
    var state: BudgetState { BudgetState(ratio: ratio) }

    @MainActor static func make(_ b: Budget, transactions: [LedgerTransaction], rates: RatesStore) -> BudgetProgress? {
        let cur = b.currency.isEmpty ? rates.base : b.currency
        guard let p = Budgets.period(start: b.startDate, type: b.repeatType, duration: 1, containing: .now) else { return nil }
        let monitored: Set<UUID>? = b.categories.isEmpty ? nil : Set(b.categories.flatMap { $0.familyIDs })
        let txs = transactions.filter { $0.type != .transfer && $0.account != nil }.map {
            BudgetTransaction(amount: $0.amount, date: $0.date, categoryID: $0.category?.uuid,
                              pending: $0.pending, rate: rates.rate(of: $0, to: cur) ?? 1)
        }
        let r = Budgets.evaluate(limit: b.amount, period: p, transactions: txs, rules: BudgetRules(monitoredCategories: monitored))
        return BudgetProgress(spent: r.spent, limit: b.amount, remaining: r.remaining, currency: cur, periodEnd: p.end)
    }
}

let chaosModeKey = "chaosInterface"

/// Значок категории с маленькой меткой типа операции (стрелка вниз, вверх) в углу.
struct TxCategoryBadge: View {
    let category: Category?
    let type: TxType
    var body: some View {
        CategoryBadge(category: category)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: type.glyph).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 14, height: 14).background(type.tint, in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5)).offset(x: 4, y: 4)
            }
    }
}

extension View {
    /// Фон экрана со списком: цвет темы вместо системного серого.
    func themedScreen() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
    }
}

/// Толстая полоса прогресса с круглыми концами: расход бюджета, использование лимита.
struct CapsuleBar: ProgressViewStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        CapsuleFill(value: configuration.fractionCompleted ?? 0, tint: tint)
    }
}

/// Полоса наполняется от нуля при появлении и плавно доезжает до нового значения при изменении.
private struct CapsuleFill: View {
    let value: Double
    let tint: Color
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(tint).frame(width: max(g.size.height, g.size.width * shown))
            }
        }
        .frame(maxWidth: .infinity).frame(height: 8)
        .onAppear {
            if reduceMotion { shown = value } else { withAnimation(.spring(duration: 0.8, bounce: 0.15).delay(0.1)) { shown = value } }
        }
        .onChange(of: value) { withAnimation(.snappy) { shown = value } }
    }
}

/// Однократная тряска при появлении, если `active`: так выделяется превышенный бюджет.
struct NudgeOnAppear: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.modifier(ShakeEffect(animatableData: phase))
            .onAppear {
                guard active, !reduceMotion, phase == 0 else { return }
                withAnimation(.linear(duration: 0.45).delay(0.8)) { phase = 1 }
            }
    }
}

/// График проявляется слева направо при открытии и заново при каждой смене `trigger` (период, разрез, горизонт).
struct ChartReveal<T: Equatable>: ViewModifier {
    let trigger: T
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) { GeometryReader { g in Rectangle().frame(width: g.size.width * progress) } }
            .onAppear(perform: reveal)
            .onChange(of: trigger) {
                progress = 0
                DispatchQueue.main.async(execute: reveal)
            }
    }

    private func reveal() {
        if reduceMotion { progress = 1 } else { withAnimation(.easeOut(duration: 0.8)) { progress = 1 } }
    }
}

/// Кольцевая диаграмма раскручивается и вырастает из центра.
struct DonutReveal<T: Equatable>: ViewModifier {
    let trigger: T
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.7 + 0.3 * progress)
            .rotationEffect(.degrees(-90 * (1 - progress)))
            .opacity(progress)
            .onAppear(perform: reveal)
            .onChange(of: trigger) {
                progress = 0
                DispatchQueue.main.async(execute: reveal)
            }
    }

    private func reveal() {
        if reduceMotion { progress = 1 } else { withAnimation(.spring(duration: 0.7, bounce: 0.2)) { progress = 1 } }
    }
}

extension View {
    func chartReveal<T: Equatable>(trigger: T = 0) -> some View { modifier(ChartReveal(trigger: trigger)) }
    func donutReveal<T: Equatable>(trigger: T = 0) -> some View { modifier(DonutReveal(trigger: trigger)) }
}

/// Крупная галочка поверх формы после сохранения, перед закрытием окна.
struct SavedBadge: View {
    let tint: Color
    @State private var bounce = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 76, weight: .bold))
            .foregroundStyle(tint)
            .symbolEffect(.bounce, value: bounce)
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .onAppear { bounce = true }
            .accessibilityHidden(true)
    }
}

// MARK: Шрифт Manrope (пять статических начертаний в Resources/Fonts, лицензия OFL)

enum AppFont {
    private static let names = ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]

    /// Регистрируем шрифты из пакета до показа первого экрана и настраиваем заголовки UIKit (навигация, вкладки).
    static func setUp() {
        for n in names {
            if let url = Bundle.main.url(forResource: "Manrope-\(n)", withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: ui(34, .heavy)]
        UINavigationBar.appearance().titleTextAttributes = [.font: ui(17, .bold)]
        UITabBarItem.appearance().setTitleTextAttributes([.font: ui(10, .semibold)], for: .normal)
    }

    static func postScript(_ w: Font.Weight) -> String {
        switch w {
        case .medium: "Manrope-Medium"
        case .semibold: "Manrope-SemiBold"
        case .bold: "Manrope-Bold"
        case .heavy, .black: "Manrope-ExtraBold"
        default: "Manrope-Regular"
        }
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        UIFont(name: postScript(weight), size: size) ?? .systemFont(ofSize: size)
    }
}

extension Font {
    /// Manrope в размерах системных стилей, с масштабированием под настройку размера шрифта.
    static func app(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        let size: CGFloat = switch style {
        case .largeTitle: 34; case .title: 28; case .title2: 22; case .title3: 20; case .headline: 17
        case .body: 17; case .callout: 16; case .subheadline: 15; case .footnote: 13; case .caption: 12; default: 11
        }
        let w = style == .headline && weight == .regular ? Font.Weight.semibold : weight
        return .custom(AppFont.postScript(w), size: size, relativeTo: style)
    }
    static func manrope(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> Font {
        .custom(AppFont.postScript(weight), size: size, relativeTo: relativeTo)
    }
}

/// Горизонтальная тряска: за один целый шаг `animatableData` текст качается влево-вправо и возвращается на место.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// Красная подпись ошибки в форме: появляется и трясётся, а при каждом новом `tick` (повторная попытка сохранить) трясётся снова.
struct FormError: View {
    let key: LocalizedStringKey
    let tick: Int
    @State private var phase: CGFloat = 0

    init(_ key: LocalizedStringKey, tick: Int) { self.key = key; self.tick = tick }

    var body: some View {
        Text(key).font(.app(.caption)).foregroundStyle(.red)
            .modifier(ShakeEffect(animatableData: phase))
            .onAppear(perform: shake)
            .onChange(of: tick) { shake() }
    }

    private func shake() { withAnimation(.linear(duration: 0.45)) { phase += 1 } }
}

/// Тактильный отклик. Вызывается напрямую, потому что экран часто закрывается в тот же момент, и `.sensoryFeedback` не успел бы сработать.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func delete() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}
