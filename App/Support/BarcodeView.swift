import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import LedgerCore

/// Штрихкод или QR для кассового сканера: чёрный на белом, без сглаживания краёв.
struct BarcodeView: View {
    let number: String
    let format: BarcodeFormat

    var body: some View {
        switch format {
        case .ean13, .ean8:
            if let m = EAN.modules(number) { EANBars(modules: m) } else { fallback }
        default:
            if let img = BarcodeRender.image(number, format: format) {
                Image(decorative: img, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .modifier(Shape(linear: format.isLinear, ratio: CGFloat(img.width) / CGFloat(max(img.height, 1))))
            } else { fallback }
        }
    }

    private var fallback: some View {
        Image(systemName: "barcode").font(.largeTitle).foregroundStyle(.gray).frame(height: 100)
    }

    /// Линейный код растягиваем по ширине на удобную высоту, двумерный держим квадратным.
    private struct Shape: ViewModifier {
        let linear: Bool
        let ratio: CGFloat
        func body(content: Content) -> some View {
            if linear { content.frame(height: 110) } else { content.aspectRatio(ratio, contentMode: .fit).frame(maxWidth: 240) }
        }
    }
}

/// EAN рисуем сами по модулям: у iPhone нет готового генератора этого формата.
private struct EANBars: View {
    let modules: [Bool]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width / CGFloat(modules.count)
            for (i, on) in modules.enumerated() where on {
                // Чуть шире модуля, чтобы между соседними полосами не было светлых щелей.
                ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w + 0.5, height: size.height)), with: .color(.black))
            }
        }
        .frame(height: 110)
        // Поле тишины: сканеру нужно пустое место слева и справа от полос.
        .padding(.horizontal, 20)
    }
}

enum BarcodeRender {
    private static let context = CIContext()

    static func image(_ number: String, format: BarcodeFormat) -> CGImage? {
        let output: CIImage?
        switch format {
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = Data(number.utf8); f.correctionLevel = "M"
            output = f.outputImage
        case .code128:
            guard let data = number.data(using: .ascii) else { return nil }
            let f = CIFilter.code128BarcodeGenerator()
            f.message = data; f.quietSpace = 10; f.barcodeHeight = 40
            output = f.outputImage
        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = Data(number.utf8)
            output = f.outputImage
        case .aztec:
            let f = CIFilter.aztecCodeGenerator()
            f.message = Data(number.utf8)
            output = f.outputImage
        case .ean13, .ean8:
            return nil
        }
        guard let o = output else { return nil }
        return context.createCGImage(o, from: o.extent)
    }
}
