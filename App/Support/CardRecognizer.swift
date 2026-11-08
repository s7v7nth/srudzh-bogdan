import Foundation
import CoreImage
import ImageIO
import Vision
import LedgerCore

/// Что удалось вытащить со снимка скидочной карты.
struct CardScan: Sendable {
    var number: String?
    var format: BarcodeFormat?
    var name: String?
    var palettes: [CardPalette] = []
}

/// Читает снимок карты встроенными средствами iPhone: находит саму карту на фото и выравнивает её,
/// читает штрихкод и надписи, считает основные цвета. Всё происходит на телефоне, без интернета.
enum CardRecognizer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> CardScan {
        await Task.detached(priority: .userInitiated) { scan(image, orientation: orientation) }.value
    }

    private static func scan(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CardScan {
        var out = CardScan()
        // Сначала ставим снимок «как видит человек» и уменьшаем: дальше все координаты считаются без поворотов.
        var upright = CIImage(cgImage: image).oriented(orientation)
        let longSide = max(upright.extent.width, upright.extent.height)
        if longSide > 1800 {
            let k = 1800 / longSide
            upright = upright.transformed(by: CGAffineTransform(scaleX: k, y: k))
        }
        guard let full = context.createCGImage(upright, from: upright.extent) else { return out }

        // Код ищем на всём снимке: бывает, что он вылезает за найденный край карты.
        let codes = barcodes(in: full)
        if let best = codes.max(by: { area($0.boundingBox) < area($1.boundingBox) }), let payload = best.payloadStringValue {
            var format = BarcodeFormat.fromSymbology(best.symbology.rawValue)
            var number = payload
            if format == .ean13 || format == .ean8 {
                if let n = EAN.normalized(payload) { number = n } else { format = .code128 }
            }
            if !format.accepts(number) { format = .qr }
            out.number = number
            out.format = format
        }

        let card = cropCard(full, upright: CIImage(cgImage: full)) ?? full
        out.name = CardTitle.guess(textLines(in: card))
        let mask = barcodes(in: card).map(\.boundingBox)
        out.palettes = CardColors.palettes(from: CardColors.dominant(pixels(of: card, skipping: mask)))
        return out
    }

    private static func area(_ r: CGRect) -> CGFloat { r.width * r.height }

    private static func barcodes(in image: CGImage) -> [VNBarcodeObservation] {
        let req = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([req])
        return (req.results ?? []).filter { $0.payloadStringValue?.isEmpty == false }
    }

    /// Вырезает карту по её краям и выпрямляет, если снимали под углом. Нет явного прямоугольника: nil.
    private static func cropCard(_ image: CGImage, upright: CIImage) -> CGImage? {
        let req = VNDetectRectanglesRequest()
        // Карта 85,6 × 54 мм: отношение сторон около 0,63, плюс запас на перспективу.
        req.minimumAspectRatio = 0.45
        req.maximumAspectRatio = 0.85
        req.minimumSize = 0.3
        req.quadratureTolerance = 25
        req.minimumConfidence = 0.6
        req.maximumObservations = 1
        try? VNImageRequestHandler(cgImage: image).perform([req])
        guard let r = req.results?.first else { return nil }
        let w = upright.extent.width, h = upright.extent.height
        func p(_ v: CGPoint) -> CIVector { CIVector(x: v.x * w, y: v.y * h) }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(upright, forKey: kCIInputImageKey)
        filter.setValue(p(r.topLeft), forKey: "inputTopLeft")
        filter.setValue(p(r.topRight), forKey: "inputTopRight")
        filter.setValue(p(r.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(p(r.bottomRight), forKey: "inputBottomRight")
        guard let flat = filter.outputImage else { return nil }
        // Отрезаем по краю немного: скруглённые углы и полоска фона портят цвета.
        let e = flat.extent.insetBy(dx: flat.extent.width * 0.03, dy: flat.extent.height * 0.03)
        return context.createCGImage(flat, from: e)
    }

    private static func textLines(in image: CGImage) -> [CardTextLine] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["ru-RU", "en-US"]
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([req])
        return (req.results ?? []).compactMap { o in
            o.topCandidates(1).first.map { CardTextLine(text: $0.string, height: Double(o.boundingBox.height)) }
        }
    }

    /// Точки уменьшенной карты без области штрихкода (там только чёрно-белые полоски).
    private static func pixels(of image: CGImage, skipping boxes: [CGRect]) -> [RGB] {
        let w = 96
        let h = max(24, min(160, Int(Double(w) * Double(image.height) / Double(max(image.width, 1)))))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }
        let masks = boxes.map { $0.insetBy(dx: -0.03, dy: -0.03) }
        var out: [RGB] = []
        out.reserveCapacity(w * h)
        for y in 0..<h {
            for x in 0..<w {
                // Строки буфера идут сверху вниз, а координаты распознавания снизу вверх.
                let pt = CGPoint(x: (Double(x) + 0.5) / Double(w), y: 1 - (Double(y) + 0.5) / Double(h))
                if masks.contains(where: { $0.contains(pt) }) { continue }
                let i = (y * w + x) * 4
                out.append(RGB(Double(buf[i]) / 255, Double(buf[i + 1]) / 255, Double(buf[i + 2]) / 255))
            }
        }
        return out
    }
}
