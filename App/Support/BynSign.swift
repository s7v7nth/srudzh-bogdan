import SwiftUI

/// Знак белорусского рубля: буква «Б» с горизонтальной чертой. В Unicode кода для него нет, поэтому рисуется.
/// Пропорции сняты с официального образца. Если появится официальный векторный файл, заменить этот рисунок.
struct BynSign: View {
    var body: some View {
        ZStack {
            BynBars().fill(style: FillStyle())
            BynBowl().fill(style: FillStyle(eoFill: true))
        }
        .accessibilityHidden(true)
    }
}

/// Размеры в долях рисунка (ширина 0...1, высота 0...1), сняты с образца 500 x 575.
private struct BynBars: Shape {
    func path(in r: CGRect) -> Path {
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
            CGRect(x: r.minX + x0 * r.width, y: r.minY + y0 * r.height, width: (x1 - x0) * r.width, height: (y1 - y0) * r.height)
        }
        var p = Path()
        p.addRect(rect(0.13, 0, 0.284, 1))       // ножка
        p.addRect(rect(0.13, 0, 0.88, 0.113))    // верхняя полка
        p.addRect(rect(0, 0.652, 0.57, 0.769))   // черта, выступает влево и пересекает ножку
        return p
    }
}

private struct BynBowl: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: pt(0.284, 0.426))
        p.addLine(to: pt(0.68, 0.426))
        p.addCurve(to: pt(1.0, 0.704), control1: pt(0.86, 0.426), control2: pt(1.0, 0.55))
        p.addCurve(to: pt(0.68, 1.0), control1: pt(1.0, 0.88), control2: pt(0.86, 1.0))
        p.addLine(to: pt(0.284, 1.0))
        p.closeSubpath()
        p.move(to: pt(0.284, 0.543))
        p.addLine(to: pt(0.62, 0.543))
        p.addCurve(to: pt(0.836, 0.704), control1: pt(0.76, 0.543), control2: pt(0.836, 0.61))
        p.addCurve(to: pt(0.62, 0.887), control1: pt(0.836, 0.80), control2: pt(0.76, 0.887))
        p.addLine(to: pt(0.284, 0.887))
        p.closeSubpath()
        return p
    }
}

/// Символ валюты: для BYN настоящая буква «Б» шрифта приложения с чертой поверх (знак в Unicode не существует), для остальных текст.
/// Так знак всегда в стиле шрифта. Размеры черты сняты с метрик Manrope: высота заглавных 0,72 em, строка 1,366 em, база на 1,066 em.
struct CurrencySymbolView: View {
    let code: String
    /// Жирность соседних цифр: от неё зависит толщина черты (как у дефиса того же начертания).
    var weight: Font.Weight = .regular

    private var barThickness: CGFloat {
        switch weight {
        case .heavy, .black: 0.105
        case .bold: 0.095
        case .semibold: 0.084
        case .medium: 0.072
        default: 0.063
        }
    }

    var body: some View {
        if code == "BYN" {
            Text("Б")
                .overlay {
                    GeometryReader { g in
                        let em = g.size.height / 1.366
                        let capTop = 0.346 * em
                        let cap = 0.72 * em
                        let t = barThickness * em
                        Rectangle()
                            .frame(width: 0.33 * em, height: t)
                            .position(x: 0.165 * em, y: capTop + cap * 0.71)
                    }
                }
                .accessibilityHidden(true)
        } else {
            Text(Currencies.symbol(code))
        }
    }
}
