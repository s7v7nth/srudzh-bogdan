import SwiftUI
import LedgerCore

/// Шаг «категории расходов»: три набора на выбор, дальше каждую можно включить, переименовать или добавить свою.
struct OnbCategoriesStep: View {
    @Bindable var draft: OnboardingDraft
    @State private var editingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnbHeader(icon: "square.grid.2x2", title: "onb.cats.title", subtitle: "onb.cats.subtitle")
            HStack(spacing: 8) {
                ForEach([(1, "onb.cats.minimal"), (2, "onb.cats.standard"), (3, "onb.cats.detailed")], id: \.0) { level, title in
                    Button { withAnimation(.snappy) { draft.setLevel(level) } } label: {
                        Text(LocalizedStringKey(title)).onbChip(selected: draft.level == level)
                    }.buttonStyle(.plain)
                }
            }
            ForEach([BudgetGroup.needs, .wants], id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title).font(.app(.subheadline, .semibold)).foregroundStyle(group.tint)
                    OnbCard {
                        let ids = draft.categories.filter { $0.group == group }.map(\.id)
                        ForEach(ids, id: \.self) { id in
                            if let i = draft.categories.firstIndex(where: { $0.id == id }) {
                                row(i)
                                if id != ids.last { Divider().overlay(.white.opacity(0.06)) }
                            }
                        }
                    }
                }
            }
            Button {
                let c = CategoryDraft(key: UUID().uuidString, name: "", icon: "tag", color: "blue", group: .wants, weight: 8, level: 3,
                                      enabled: true, isCustom: true)
                draft.categories.append(c)
                editingID = c.id
            } label: {
                Label("onb.cats.add", systemImage: "plus.circle.fill").font(.app(.subheadline, .semibold))
            }
            Text("onb.cats.hint").font(.app(.footnote)).foregroundStyle(.secondary)
        }
        .sheet(item: Binding(get: { editingID.map { IDBox(id: $0) } }, set: { editingID = $0?.id })) { box in
            if let i = draft.categories.firstIndex(where: { $0.id == box.id }) {
                OnbCategoryEditor(category: $draft.categories[i]) {
                    draft.categories.removeAll { $0.id == box.id }
                }
                .presentationDetents([.large])
            }
        }
    }

    private struct IDBox: Identifiable { let id: UUID }

    private func row(_ i: Int) -> some View {
        let c = draft.categories[i]
        let required = draft.requiredCategoryKeys.contains(c.key)
        return HStack(spacing: 12) {
            Button {
                guard !required else { return }
                withAnimation(.snappy) { draft.categories[i].enabled.toggle() }
            } label: {
                HStack(spacing: 12) {
                    OnbCatBadge(icon: c.icon, color: c.color, size: 34)
                    Text(c.name.isEmpty ? String(localized: "onb.cats.noName") : c.name).foregroundStyle(.primary)
                    Spacer()
                    OnbCheck(on: c.enabled)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if c.enabled {
                Button { editingID = c.id } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).accessibilityLabel(Text("common.edit"))
            }
        }
    }
}

struct OnbCategoryEditor: View {
    @Binding var category: CategoryDraft
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("field.name", text: $category.name)
                    Picker("onb.cats.group", selection: $category.group) {
                        Text(BudgetGroup.needs.title).tag(BudgetGroup.needs)
                        Text(BudgetGroup.wants.title).tag(BudgetGroup.wants)
                    }
                }
                Section("onb.cats.icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(categoryIcons, id: \.self) { icon in
                            Button { category.icon = icon } label: {
                                Image(systemName: icon).font(.system(size: 18))
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(category.icon == icon ? Theme.onBrand : Color.primary)
                                    .background(category.icon == icon ? Theme.brand : Theme.raised, in: Circle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }
                Section("onb.cats.color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(categoryColorNames, id: \.self) { name in
                            Button { category.color = name } label: {
                                Circle().fill(Color.category(name)).frame(width: 34, height: 34)
                                    .overlay { if category.color == name { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) } }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }
                if category.isCustom {
                    Section { Button("common.delete", role: .destructive) { onDelete(); dismiss() } }
                }
            }
            .themedScreen()
            .navigationTitle("onb.cats.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } } }
        }
    }
}

/// Круглая иконка категории по названию значка и цвета (без объекта из базы: категория ещё черновик).
struct OnbCatBadge: View {
    let icon: String
    let color: String
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            Circle().fill(Color.category(color).opacity(0.18))
            Image(systemName: icon).font(.system(size: size * 0.45)).foregroundStyle(Color.category(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
