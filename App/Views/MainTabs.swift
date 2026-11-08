import SwiftUI

/// Вкладка нижней панели.
struct MainTab: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let icon: String
}

/// Экраны приложения с нижней панелью. При переключении новый экран перелетает сбоку
/// (справа, если вкладка правее, и слева, если левее), а старый уезжает в другую сторону.
/// Экраны живут всё время после первого открытия, поэтому прокрутка и открытые подэкраны не теряются.
struct MainTabs<Page: View>: View {
    @Binding var selection: Int
    let tabs: [MainTab]
    @ViewBuilder let page: (Int) -> Page

    /// Экран, с которого улетаем: только он и новый двигаются, остальные стоят за краем.
    @State private var from: Int?
    @State private var opened: Set<Int> = []
    @State private var keyboardUp = false
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack {
                ForEach(tabs) { t in
                    if opened.contains(t.id) || t.id == selection { screen(t.id, width: g.size.width) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardUp { bar }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func screen(_ i: Int, width: CGFloat) -> some View {
        let current = i == selection
        let moving = current || i == from
        let side: CGFloat = current ? 0 : (i < selection ? -1 : 1)
        return page(i)
            .offset(x: reduceMotion ? 0 : side * width)
            .opacity(reduceMotion && !current ? 0 : 1)
            // Экраны, которые не участвуют в перелёте, перескакивают на свою сторону мгновенно и за краем,
            // иначе при прыжке через несколько вкладок они пролетали бы через видимую область.
            .transaction { if !moving { $0.animation = nil } }
            .allowsHitTesting(current)
            .accessibilityHidden(!current)
    }

    private func select(_ i: Int) {
        guard i != selection else { return }
        if opened.contains(i) {
            go(to: i)
        } else {
            // Новый экран сначала строится за краем, а перелетает со следующего кадра.
            opened.insert(i)
            DispatchQueue.main.async { go(to: i) }
        }
    }

    private func go(to i: Int) {
        opened.insert(selection)
        withAnimation(Motion.large) {
            from = selection
            selection = i
        }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { t in
                let on = t.id == selection
                VStack(spacing: 3) {
                    Image(systemName: t.icon).font(.system(size: 18, weight: .semibold)).frame(height: 22)
                    Text(t.title).font(.app(.caption2, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(on ? Theme.brand : Color.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background {
                    if on { Capsule().fill(Theme.brand.opacity(0.16)).matchedGeometryEffect(id: "pill", in: pill) }
                }
                .contentShape(Capsule())
                // Как у системной панели: вкладка переключается в момент касания, а не когда палец отпущен.
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in select(t.id) })
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { select(t.id) }
            }
        }
        .padding(5)
        .modifier(BarGlass())
        // Чуть заходит на полосу «домой», как системная панель: так она не висит над краем.
        .padding(.horizontal, 16).padding(.bottom, -12)
    }
}

/// Стеклянная подложка панели: на iOS 26 настоящее стекло, раньше матовая капсула.
private struct BarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
    }
}
