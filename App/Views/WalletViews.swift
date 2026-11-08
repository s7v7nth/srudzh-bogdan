import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import LedgerCore

// MARK: - Кошелёк

/// Скидочные и бонусные карты магазинов: сетка плиток, поиск и показ кода на кассе.
struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LoyaltyCard.created) private var cards: [LoyaltyCard]
    @State private var search = ""
    @State private var adding = false
    /// Порядок фиксируется при открытии кошелька: частые карты сверху, но сетка не прыгает, пока ею пользуешься.
    @State private var order: [UUID] = []

    private var shown: [LoyaltyCard] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = cards.enumerated().sorted { a, b in
            (rank[a.element.uuid] ?? order.count + a.offset) < (rank[b.element.uuid] ?? order.count + b.offset)
        }.map(\.element)
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.number.contains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView {
                        Label("wallet.empty", systemImage: "wallet.pass")
                    } description: {
                        Text("wallet.empty.hint")
                    }
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(shown) { c in
                                NavigationLink(value: c) { CardTile(card: c) }.buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                    .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("wallet.title")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: LoyaltyCard.self) { CardDetailView(card: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { adding = true } label: {
                    Label("wallet.add", systemImage: "plus").font(.app(.headline)).frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.borderedProminent).tint(Theme.brand).foregroundStyle(Theme.onBrand)
                .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
            }
            .sheet(isPresented: $adding) { CardFormView() }
            .onAppear {
                order = cards.sorted {
                    if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
                    return $0.created < $1.created
                }.map(\.uuid)
            }
        }
    }
}

// MARK: - Плитка

/// Карта в виде цветной плитки с названием, в пропорциях настоящей пластиковой карты.
struct CardTile: View {
    let name: String
    let background: String
    let title: String
    var large = false

    init(card: LoyaltyCard, large: Bool = false) {
        self.init(name: card.name, background: card.background, title: card.titleColor, large: large)
    }
    init(name: String, background: String, title: String, large: Bool = false) {
        self.name = name; self.background = background; self.title = title; self.large = large
    }

    var body: some View {
        RoundedRectangle(cornerRadius: large ? 18 : 12, style: .continuous)
            .fill(Color(rgb: RGB(hex: background) ?? RGB(0.23, 0.23, 0.24)))
            .overlay {
                Text(name.isEmpty ? " " : name)
                    .font(.manrope(large ? 34 : 22, .heavy, relativeTo: large ? .largeTitle : .title2))
                    .foregroundStyle(Color(rgb: RGB(hex: title) ?? .white))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .padding(large ? 24 : 12)
            }
            .overlay {
                // Тонкая рамка, чтобы тёмная карта не растворялась в тёмном фоне.
                RoundedRectangle(cornerRadius: large ? 18 : 12, style: .continuous).strokeBorder(.white.opacity(0.08))
            }
            .aspectRatio(85.6 / 54, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
    }
}

// MARK: - Показ на кассе

struct CardDetailView: View {
    @Bindable var card: LoyaltyCard
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var savedBrightness: CGFloat?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CardTile(card: card, large: true)
                VStack(spacing: 14) {
                    BarcodeView(number: card.number, format: card.format)
                    Text(verbatim: Self.grouped(card.number))
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button("wallet.copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = card.number }
                }
                Text("wallet.showHint").font(.app(.footnote)).foregroundStyle(.secondary)
                if !card.note.isEmpty {
                    Text(verbatim: card.note).font(.app(.body)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: card.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("common.edit", systemImage: "pencil") { editing = true }
                    Button("wallet.delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) { CardFormView(card: card) }
        .confirmationDialog("wallet.deleteTitle", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                ctx.delete(card)
                try? ctx.save()
                dismiss()
            }
        }
        .onAppear {
            card.useCount += 1
            card.lastUsed = .now
            try? ctx.save()
            brighten(true)
        }
        .onDisappear { brighten(false) }
    }

    /// Кассовый сканер плохо читает код с тусклого экрана: на время показа яркость на максимум.
    private func brighten(_ on: Bool) {
        guard let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen else { return }
        if on {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 1
        } else if let b = savedBrightness {
            screen.brightness = b
            savedBrightness = nil
        }
    }

    /// Цифровой номер по четыре цифры, как на пластике; остальное как есть.
    static func grouped(_ s: String) -> String {
        guard s.count > 6, s.allSatisfy(\.isNumber) else { return s }
        return stride(from: 0, to: s.count, by: 4).map { i in
            let a = s.index(s.startIndex, offsetBy: i)
            return String(s[a..<(s.index(a, offsetBy: 4, limitedBy: s.endIndex) ?? s.endIndex)])
        }.joined(separator: " ")
    }
}

// MARK: - Добавление и правка

struct CardFormView: View {
    var card: LoyaltyCard?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var number = ""
    @State private var format = BarcodeFormat.code128
    @State private var formatTouched = false
    @State private var background = "3A3A3C"
    @State private var titleColor = "FFFFFF"
    @State private var note = ""
    @State private var palettes: [CardPalette] = []
    @State private var scanning = false
    @State private var scanMessage: LocalizedStringKey?
    @State private var showCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var loaded = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var trimmedNumber: String { number.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && format.accepts(trimmedNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardTile(name: name, background: background, title: titleColor)
                        .listRowInsets(EdgeInsets(top: 4, leading: 40, bottom: 4, trailing: 40))
                        .listRowBackground(Color.clear)
                }
                Section {
                    if cameraAvailable {
                        Button("wallet.scan.camera", systemImage: "camera") { showCamera = true }
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("wallet.scan.photo", systemImage: "photo.on.rectangle")
                    }
                    if scanning {
                        HStack(spacing: 10) { ProgressView(); Text("wallet.scan.working") }
                    } else if let m = scanMessage {
                        Text(m).font(.app(.footnote)).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("wallet.scan.hint")
                }
                .disabled(scanning)

                Section {
                    TextField("wallet.field.name", text: $name)
                    TextField("wallet.field.number", text: $number)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .monospacedDigit()
                    Picker("wallet.field.format", selection: Binding(get: { format }, set: { format = $0; formatTouched = true })) {
                        ForEach(BarcodeFormat.allCases, id: \.self) { Text(verbatim: Self.title($0)).tag($0) }
                    }
                    TextField("wallet.field.note", text: $note, axis: .vertical)
                } header: {
                    Text("wallet.section.card")
                } footer: {
                    if !trimmedNumber.isEmpty && !format.accepts(trimmedNumber) { Text("wallet.number.invalid") }
                }

                Section("wallet.section.colors") {
                    if !palettes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(palettes, id: \.self) { p in
                                    Button {
                                        background = p.background.hex; titleColor = p.title.hex
                                    } label: { swatch(p) }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    ColorPicker("wallet.color.background", selection: colorBinding($background), supportsOpacity: false)
                    ColorPicker("wallet.color.title", selection: colorBinding($titleColor), supportsOpacity: false)
                }
            }
            .themedScreen()
            .navigationTitle(card == nil ? "wallet.new" : "wallet.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save", action: save).disabled(!canSave) }
            }
            .onChange(of: number) { _, n in
                if !formatTouched { format = BarcodeFormat.guess(for: n.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    scanning = true
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await apply(img)
                    } else {
                        scanning = false
                    }
                    photo = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in Task { await apply(img) } }.ignoresSafeArea()
            }
            .onAppear(perform: load)
        }
    }

    private func swatch(_ p: CardPalette) -> some View {
        let selected = p.background.hex == background && p.title.hex == titleColor
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(rgb: p.background))
            .frame(width: 64, height: 40)
            .overlay { Text(verbatim: "Aa").font(.manrope(17, .heavy)).foregroundStyle(Color(rgb: p.title)) }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.brand : .white.opacity(0.15), lineWidth: selected ? 2.5 : 1)
            }
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(rgb: RGB(hex: hex.wrappedValue) ?? .black) },
                set: { hex.wrappedValue = RGB(color: $0).hex })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let c = card else { return }
        name = c.name; number = c.number; format = c.format; formatTouched = true
        background = c.background; titleColor = c.titleColor; note = c.note
    }

    @MainActor private func apply(_ img: UIImage) async {
        guard let cg = img.cgImage else { scanning = false; return }
        scanning = true
        let scan = await CardRecognizer.recognize(cg, orientation: CGImagePropertyOrientation(img.imageOrientation))
        scanning = false
        withAnimation(Motion.standard) {
            if let n = scan.number, let f = scan.format {
                number = n; format = f; formatTouched = true
            }
            if let n = scan.name, name.trimmingCharacters(in: .whitespaces).isEmpty { name = n }
            palettes = scan.palettes
            if let p = scan.palettes.first { background = p.background.hex; titleColor = p.title.hex }
        }
        scanMessage = scan.number == nil ? "wallet.scan.noCode" : "wallet.scan.done"
    }

    private func save() {
        var n = trimmedNumber
        if format == .ean13 || format == .ean8, let full = EAN.normalized(n) { n = full }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let c = card {
            c.name = trimmedName; c.number = n; c.format = format
            c.background = background; c.titleColor = titleColor; c.note = note
        } else {
            let c = LoyaltyCard(name: trimmedName, number: n, format: format, background: background, titleColor: titleColor)
            c.note = note
            ctx.insert(c)
        }
        try? ctx.save()
        dismiss()
    }

    static func title(_ f: BarcodeFormat) -> String {
        switch f {
        case .qr: "QR"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .code128: "Code 128"
        case .pdf417: "PDF417"
        case .aztec: "Aztec"
        }
    }
}

// MARK: - Камера

/// Системная камера для одного снимка карты.
private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Цвета

extension Color {
    init(rgb: RGB) { self.init(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

extension RGB {
    init(color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b))
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
