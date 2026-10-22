import SwiftUI
import SwiftData

// MARK: - Выбор категории при вводе операции

struct CategoryPickerRow: View {
    @Binding var selection: Category?
    let isIncome: Bool
    var body: some View {
        NavigationLink {
            CategoryPickerView(selection: $selection, isIncome: isIncome)
        } label: {
            HStack {
                Text("field.category"); Spacer()
                if let c = selection { CategoryBadge(category: c, size: 24); Text(c.name).foregroundStyle(.secondary) }
                else { Text("category.none").foregroundStyle(.secondary) }
            }
        }
    }
}

struct CategoryPickerView: View {
    @Binding var selection: Category?
    let isIncome: Bool
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortID) private var all: [Category]
    @State private var search = ""
    @State private var showNew = false

    private var pool: [Category] { all.filter { $0.isIncome == isIncome && !$0.archived } }
    private var recent: [Category] {
        Array(pool.filter { $0.lastUsed != nil }.sorted { $0.lastUsed! > $1.lastUsed! }.prefix(5))
    }
    private var tree: [(Category, Int)] {
        pool.filter { $0.parent == nil }.flatMap { p in
            [(p, 0)] + p.children.filter { !$0.archived }.sorted { $0.sortID < $1.sortID }.map { ($0, 1) }
        }
    }

    var body: some View {
        List {
            if search.isEmpty {
                Button { selection = nil; dismiss() } label: {
                    HStack { Text("category.none").foregroundStyle(.primary); Spacer(); if selection == nil { Image(systemName: "checkmark") } }
                }
                if !recent.isEmpty {
                    Section("category.recent") { ForEach(recent) { row($0, level: 0) } }
                }
                Section("category.all") { ForEach(tree, id: \.0.uuid) { row($0.0, level: $0.1) } }
            } else {
                ForEach(pool.filter { $0.name.localizedCaseInsensitiveContains(search) }) { row($0, level: 0) }
            }
        }
        .searchable(text: $search, prompt: Text("category.search"))
        .themedScreen()
        .navigationTitle("field.category").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("category.new", systemImage: "plus") { showNew = true } }
        .sheet(isPresented: $showNew) {
            CategoryFormView(isIncome: isIncome) { new in selection = new; dismiss() }
        }
    }

    private func row(_ c: Category, level: Int) -> some View {
        Button { selection = c; dismiss() } label: {
            HStack {
                CategoryBadge(category: c, size: 28)
                Text(c.name).foregroundStyle(.primary)
                Spacer()
                if selection === c { Image(systemName: "checkmark") }
            }.padding(.leading, CGFloat(level) * 24)
        }
    }
}

// MARK: - Управление категориями

struct CategoriesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Category.sortID) private var all: [Category]
    @State private var income = false
    @State private var editing: Category?
    @State private var creating = false
    @State private var deleting: Category?
    @State private var showOrder = false

    private var top: [Category] { all.filter { $0.parent == nil && $0.isIncome == income } }

    var body: some View {
        List {
            Picker("field.type", selection: $income) { Text("tx.expense").tag(false); Text("tx.income").tag(true) }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
            if top.isEmpty { ContentUnavailableView("category.empty", systemImage: "tag") }
            Section {
                ForEach(top) { p in
                    row(p)
                    ForEach(p.children.sorted { $0.sortID < $1.sortID }) { row($0).padding(.leading, 24) }
                }
            }
        }
        .themedScreen()
        .navigationTitle("settings.categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("category.new", systemImage: "plus") { creating = true } }
            ToolbarItem(placement: .topBarTrailing) { Button("category.order", systemImage: "arrow.up.arrow.down") { showOrder = true } }
        }
        .sheet(isPresented: $creating) { CategoryFormView(isIncome: income) }
        .sheet(item: $editing) { CategoryFormView(category: $0, isIncome: $0.isIncome) }
        .sheet(item: $deleting) { CategoryDeleteView(category: $0) }
        .sheet(isPresented: $showOrder) { CategoryOrderView(isIncome: income) }
    }

    private func row(_ c: Category) -> some View {
        HStack {
            CategoryBadge(category: c, size: 30)
            Text(c.name)
            if c.archived { Text("category.archived").font(.app(.caption)).foregroundStyle(.secondary) }
            Spacer()
        }
        .opacity(c.archived ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editing = c }
        .swipeActions {
            Button("common.delete", role: .destructive) { deleting = c }
            Button("common.edit") { editing = c }.tint(.blue)
        }
    }
}

struct CategoryFormView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortID) private var all: [Category]
    var category: Category? = nil
    @State var isIncome: Bool
    var onSaved: ((Category) -> Void)? = nil

    @State private var name = ""
    @State private var parent: Category?
    @State private var icon = "tag"
    @State private var color = "blue"
    @State private var submitted = false
    @State private var loaded = false

    init(category: Category? = nil, isIncome: Bool, onSaved: ((Category) -> Void)? = nil) {
        self.category = category; self._isIncome = State(initialValue: isIncome); self.onSaved = onSaved
    }

    private var parents: [Category] {
        all.filter { $0.parent == nil && $0.isIncome == isIncome && !$0.archived && $0 !== category }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { CategoryBadge(category: Category(name: name, isIncome: isIncome, icon: icon, colorName: color), size: 36)
                        TextField("field.name", text: $name) }
                    if submitted && name.trimmingCharacters(in: .whitespaces).isEmpty { Text("error.name").font(.app(.caption)).foregroundStyle(.red) }
                    if category == nil {
                        Picker("field.type", selection: $isIncome) { Text("tx.expense").tag(false); Text("tx.income").tag(true) }
                            .onChange(of: isIncome) { parent = nil }
                    }
                    if category?.children.isEmpty ?? true {
                        Picker("category.parent", selection: $parent) {
                            Text("category.topLevel").tag(Category?.none)
                            ForEach(parents) { Text($0.name).tag(Category?.some($0)) }
                        }
                    }
                }
                Section("category.icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(categoryIcons, id: \.self) { i in
                            Button { icon = i } label: {
                                Image(systemName: i).frame(width: 40, height: 40)
                                    .background(icon == i ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section("category.color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(categoryColorNames, id: \.self) { c in
                            Button { color = c } label: {
                                Circle().fill(Color.category(c)).frame(width: 30, height: 30)
                                    .overlay { if color == c { Image(systemName: "checkmark").foregroundStyle(.white) } }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .themedScreen()
            .navigationTitle(category == nil ? "category.newTitle" : "category.editTitle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save", action: save) }
            }
            .onAppear {
                guard !loaded, let c = category else { return }; loaded = true
                name = c.name; parent = c.parent; icon = c.icon; color = c.colorName
            }
        }
    }

    private func save() {
        submitted = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let c = category {
            c.name = trimmed; c.icon = icon; c.colorName = color; c.parent = parent
            onSaved?(c)
        } else {
            let siblings = all.filter { $0.parent === parent && $0.isIncome == isIncome }
            let c = Category(name: trimmed, isIncome: isIncome, icon: icon, colorName: color,
                             sortID: (siblings.map(\.sortID).max() ?? -1) + 1, parent: parent)
            ctx.insert(c)
            onSaved?(c)
        }
        dismiss()
    }
}

/// Порядок категорий: верхний уровень или подкатегории выбранной.
struct CategoryOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortID) private var all: [Category]
    let isIncome: Bool
    @State private var parent: Category?

    private var items: [Category] { all.filter { $0.parent === parent && $0.isIncome == isIncome } }
    private var parents: [Category] { all.filter { $0.parent == nil && $0.isIncome == isIncome && !$0.children.isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                Picker("category.orderOf", selection: $parent) {
                    Text("category.topLevel").tag(Category?.none)
                    ForEach(parents) { Text($0.name).tag(Category?.some($0)) }
                }
                Section {
                    ForEach(items) { c in HStack { CategoryBadge(category: c, size: 28); Text(c.name) } }
                        .onMove { from, to in
                            var list = items; list.move(fromOffsets: from, toOffset: to)
                            for (i, c) in list.enumerated() { c.sortID = i }
                        }
                }
            }
            .environment(\.editMode, .constant(.active))
            .themedScreen()
            .navigationTitle("category.order").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("common.done") { dismiss() } }
        }
    }
}

/// Удаление: перенести операции в другую категорию (это же слияние) или спрятать в архив.
struct CategoryDeleteView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortID) private var all: [Category]
    let category: Category
    @State private var target: Category?

    private var targets: [Category] { all.filter { $0.isIncome == category.isIncome && !$0.archived && $0 !== category } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { CategoryBadge(category: category); Text(category.name).font(.app(.headline)) }
                    Text(fmt("category.usage", usageCount())).foregroundStyle(.secondary)
                    if !category.children.isEmpty { Text("category.hasChildren").font(.app(.caption)).foregroundStyle(.secondary) }
                }
                Section {
                    Picker("category.moveTo", selection: $target) {
                        Text("category.none").tag(Category?.none)
                        ForEach(targets) { Text($0.name).tag(Category?.some($0)) }
                    }
                } footer: { Text("category.moveFooter") }
                Section {
                    Button("category.moveAndDelete", role: .destructive) { moveAndDelete() }
                    Button("category.archive") { category.archived = true; dismiss() }
                }
            }
            .themedScreen()
            .navigationTitle("category.deleteTitle").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
    }

    private func txs() -> [LedgerTransaction] {
        ((try? ctx.fetch(FetchDescriptor<LedgerTransaction>())) ?? []).filter { $0.category === category }
    }
    private func usageCount() -> Int { txs().count }

    private func moveAndDelete() {
        txs().forEach { $0.category = target }
        for r in (try? ctx.fetch(FetchDescriptor<RecurringTransaction>())) ?? [] where r.category === category { r.category = target }
        for p in (try? ctx.fetch(FetchDescriptor<PlanItem>())) ?? [] where p.category === category { p.category = target }
        for b in (try? ctx.fetch(FetchDescriptor<Budget>())) ?? [] where b.categories.contains(where: { $0 === category }) {
            b.categories.removeAll { $0 === category }
            if let t = target, !b.categories.contains(where: { $0 === t }) { b.categories.append(t) }
        }
        category.children.forEach { $0.parent = nil }
        ctx.delete(category)
        dismiss()
    }
}
