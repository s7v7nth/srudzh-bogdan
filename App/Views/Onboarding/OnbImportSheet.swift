import SwiftUI
import UniformTypeIdentifiers
import LedgerCore

/// Состояние импорта: файл, столбцы, какие названия считаются счетами и что из этого получится.
@Observable final class CSVImportModel {
    var fileName = ""
    var errorKey: LocalizedStringKey?
    private(set) var sections: [[[String]]] = []
    private(set) var columns = CSVColumns()
    private(set) var rows: [CSVRow] = []
    private(set) var names: [CSVName] = []
    private(set) var accountKeys: Set<String> = []
    private(set) var ledger = CSVLedger()
    private var skipped = 0
    private var sidecar = CSVSidecar()

    var header: [String] { sections.first?.first ?? [] }

    /// true: файл прочитан и в нём есть что импортировать.
    func load(_ result: Result<URL, Error>) -> Bool {
        errorKey = nil
        let url: URL
        switch result {
        case .success(let u): url = u
        case .failure(let e):
            if (e as? CocoaError)?.code != .userCancelled { errorKey = "imp.pick.error.read" }
            return false
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = Self.decode(data) else { errorKey = "imp.pick.error.read"; return false }
        let parsed = CSV.sections(CSV.parse(text))
        guard let main = parsed.first, main.count > 1 else { errorKey = "imp.pick.error.empty"; return false }
        fileName = url.lastPathComponent
        sections = parsed
        sidecar = CSV.sidecar(Array(parsed.dropFirst()))
        columns = CSV.guessColumns(header: main[0])
        reparse()
        return true
    }

    private static func decode(_ d: Data) -> String? {
        if d.starts(with: [0xFF, 0xFE]) || d.starts(with: [0xFE, 0xFF]) { return String(data: d, encoding: .utf16) }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1251)
    }

    func setColumn(_ path: WritableKeyPath<CSVColumns, Int?>, _ value: Int?) {
        columns[keyPath: path] = value
        reparse()
    }

    func setAccount(_ key: String, _ on: Bool) {
        if on { accountKeys.insert(key) } else { accountKeys.remove(key) }
        rebuild()
    }

    private func reparse() {
        guard let main = sections.first else { return }
        let r = CSV.rows(table: main, columns: columns)
        rows = r.rows; skipped = r.skipped
        names = CSV.names(rows: rows, sidecar: sidecar)
        accountKeys = CSV.guessAccounts(names)
        rebuild()
    }

    private func rebuild() {
        ledger = CSV.build(rows: rows, accountKeys: accountKeys, sidecar: sidecar, skipped: skipped)
    }
}

/// Три экрана: выбрать файл, показать, что в каком столбце, проверить найденные счета и категории.
struct OnbImportSheet: View {
    let onDone: (CSVLedger) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model = CSVImportModel()
    @State private var stage = Stage.pick
    @State private var picking = false

    private enum Stage { case pick, columns, review }

    init(onDone: @escaping (CSVLedger) -> Void) {
        self.onDone = onDone
        #if DEBUG
        // -csvSheet <путь> [columns|review]: открыть лист сразу на нужном экране с загруженным файлом.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-csvSheet"), i + 1 < args.count {
            let m = CSVImportModel()
            if m.load(.success(URL(fileURLWithPath: args[i + 1]))) {
                _model = State(initialValue: m)
                _stage = State(initialValue: args.contains("review") ? .review : .columns)
            }
        }
        #endif
    }

    private let fields: [(LocalizedStringKey, WritableKeyPath<CSVColumns, Int?>, Bool)] = [
        ("imp.f.date", \.date, true), ("imp.f.amount", \.amount, true), ("imp.f.from", \.from, true),
        ("imp.f.to", \.to, false), ("imp.f.type", \.type, false), ("imp.f.currency", \.currency, false),
        ("imp.f.convAmount", \.convertedAmount, false), ("imp.f.convCurrency", \.convertedCurrency, false),
        ("imp.f.note", \.note, false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch stage {
                    case .pick: pick
                    case .columns: columnsStage
                    case .review: review
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            footer
        }
        .background(Theme.bg.ignoresSafeArea())
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if model.load(result) { withAnimation(.snappy) { stage = .columns } }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Общее

    private var bar: some View {
        HStack {
            Button { back() } label: { Image(systemName: "chevron.left").font(.app(.headline)) }
                .opacity(stage == .pick ? 0 : 1).disabled(stage == .pick)
                .accessibilityLabel(Text("onb.back"))
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").font(.app(.subheadline, .semibold)) }
                .accessibilityLabel(Text("common.cancel"))
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func back() {
        withAnimation(.snappy) { stage = stage == .review ? .columns : .pick }
    }

    private var footer: some View {
        Button(action: advance) {
            Group {
                switch stage {
                case .pick: Text("imp.pick.button")
                case .columns: Text("onb.next")
                case .review: Text("imp.review.confirm \(model.ledger.entries.count)")
                }
            }
            .font(.app(.headline)).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).tint(Theme.brand).foregroundStyle(Theme.onBrand)
        .disabled(!canAdvance)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    private var canAdvance: Bool {
        switch stage {
        case .pick: true
        case .columns: !model.rows.isEmpty
        case .review: !model.ledger.entries.isEmpty
        }
    }

    private func advance() {
        switch stage {
        case .pick: picking = true
        case .columns: withAnimation(.snappy) { stage = .review }
        case .review: onDone(model.ledger); dismiss()
        }
    }

    // MARK: Выбор файла

    @ViewBuilder private var pick: some View {
        OnbHeader(icon: "square.and.arrow.down", title: "imp.pick.title", subtitle: "imp.pick.subtitle")
        if let e = model.errorKey {
            Label(e, systemImage: "exclamationmark.circle").font(.app(.footnote)).foregroundStyle(Theme.warn)
        }
    }

    // MARK: Столбцы

    @ViewBuilder private var columnsStage: some View {
        OnbHeader(icon: "tablecells", title: "imp.cols.title", subtitle: "imp.cols.subtitle")
        Text(verbatim: model.fileName).font(.app(.footnote)).foregroundStyle(.secondary)
        OnbCard {
            ForEach(fields.indices, id: \.self) { i in
                let f = fields[i]
                OnbPickRow(label: f.0) {
                    Picker("", selection: binding(f.1)) {
                        Text("imp.f.none").tag(-1)
                        ForEach(model.header.indices, id: \.self) { c in
                            Text(verbatim: model.header[c].isEmpty ? "#\(c + 1)" : model.header[c]).tag(c)
                        }
                    }
                    .labelsHidden()
                }
                if i < fields.count - 1 { Divider().overlay(.white.opacity(0.06)) }
            }
        }
        if model.rows.isEmpty {
            Label("imp.cols.needs", systemImage: "exclamationmark.circle").font(.app(.footnote)).foregroundStyle(Theme.warn)
        } else {
            Text("imp.cols.preview").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary).padding(.top, 4)
            OnbCard {
                ForEach(Array(model.rows.prefix(3).enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(r.date.formatted(date: .numeric, time: .omitted)) · \(r.amount) \(r.currency)")
                            .font(.app(.footnote).monospacedDigit()).foregroundStyle(.secondary)
                        Text(verbatim: "\(r.from) → \(r.to)").font(.app(.body))
                    }
                }
            }
        }
    }

    private func binding(_ path: WritableKeyPath<CSVColumns, Int?>) -> Binding<Int> {
        Binding(get: { model.columns[keyPath: path] ?? -1 }, set: { model.setColumn(path, $0 < 0 ? nil : $0) })
    }

    // MARK: Проверка

    @ViewBuilder private var review: some View {
        let accounts = model.names.filter { model.accountKeys.contains($0.key) }
        let others = model.names.filter { !model.accountKeys.contains($0.key) }
        OnbHeader(icon: "checklist", title: "imp.review.title", subtitle: "imp.review.subtitle")
        OnbCard {
            HStack {
                Text("imp.review.ops \(model.ledger.entries.count)").font(.app(.body, .semibold))
                Spacer()
                if let a = model.ledger.firstDate, let b = model.ledger.lastDate {
                    Text(verbatim: "\(a.formatted(date: .abbreviated, time: .omitted)) – \(b.formatted(date: .abbreviated, time: .omitted))")
                        .font(.app(.footnote)).foregroundStyle(.secondary)
                }
            }
            if model.ledger.skipped > 0 {
                Label("imp.review.skipped \(model.ledger.skipped)", systemImage: "exclamationmark.triangle")
                    .font(.app(.footnote)).foregroundStyle(Theme.warn)
            }
        }
        Text("imp.review.accounts").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary).padding(.top, 4)
        OnbCard {
            if accounts.isEmpty {
                Label("imp.review.noAccounts", systemImage: "exclamationmark.circle").font(.app(.footnote)).foregroundStyle(Theme.warn)
            }
            ForEach(accounts, id: \.key) { n in
                row(n, caption: Text("imp.row.account \(n.count)"), note: n.listedAsIncome ? Text("imp.row.incomeInFile") : nil)
            }
        }
        Text("imp.review.others").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary).padding(.top, 4)
        OnbCard {
            ForEach(others, id: \.key) { n in
                row(n, caption: Text(roleKey(n)))
            }
        }
        Text("imp.review.hint").font(.app(.footnote)).foregroundStyle(.secondary)
    }

    private func roleKey(_ n: CSVName) -> LocalizedStringKey {
        let gives = n.incomeFrom + n.transferFrom > 0
        if n.expenseTo > 0 && gives { return "imp.role.both" }
        if n.expenseTo > 0 { return "imp.role.expense" }
        return n.listedAsIncome ? "imp.role.incomeListed" : "imp.role.income"
    }

    private func row(_ n: CSVName, caption: Text, note: Text? = nil) -> some View {
        Toggle(isOn: Binding(get: { model.accountKeys.contains(n.key) }, set: { model.setAccount(n.key, $0) })) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: n.name).font(.app(.body, .semibold))
                caption.font(.app(.caption)).foregroundStyle(.secondary)
                if let note { note.font(.app(.caption)).foregroundStyle(Theme.warn) }
            }
        }
        .tint(Theme.accent)
    }
}
