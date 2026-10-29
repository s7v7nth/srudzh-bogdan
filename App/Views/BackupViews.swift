import SwiftUI
import UniformTypeIdentifiers

/// Выбор папки для копий: системное окно «Файлы», доступ к папке запоминается.
private struct BackupFolderImporter: ViewModifier {
    @Binding var isPresented: Bool
    var onPicked: () -> Void = {}
    @State private var error = false

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                do { try AutoBackup.shared.setFolder(url); onPicked() } catch { self.error = true }
            }
            .alert("backup.error.folder", isPresented: $error) { Button("common.ok", role: .cancel) {} }
    }
}

extension View {
    func backupFolderImporter(isPresented: Binding<Bool>, onPicked: @escaping () -> Void = {}) -> some View {
        modifier(BackupFolderImporter(isPresented: isPresented, onPicked: onPicked))
    }
}

/// Строка состояния копий: когда была последняя или что сломалось.
struct BackupStatusLabel: View {
    var backup = AutoBackup.shared

    var body: some View {
        if !backup.hasFolder {
            Label("backup.status.noFolder", systemImage: "icloud.slash").foregroundStyle(Theme.warn)
        } else if backup.failed {
            Label("backup.status.failed", systemImage: "exclamationmark.icloud").foregroundStyle(.red)
        } else if let d = backup.lastSuccess {
            Label(fmt("backup.status.ok", d.formatted(date: .abbreviated, time: .shortened)), systemImage: "checkmark.icloud")
                .foregroundStyle(Theme.accent)
        } else {
            Label("backup.status.none", systemImage: "icloud").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Первая настройка

/// Карточка «выбери папку»: в онбординге и в отдельном окне для тех, кто онбординг уже прошёл.
struct BackupSetupCard: View {
    var backup = AutoBackup.shared
    @State private var picking = false

    var body: some View {
        OnbCard {
            if let title = backup.folderTitle, backup.hasFolder {
                HStack(spacing: 12) {
                    OnbIcon(name: "checkmark.circle.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("backup.chosen").font(.app(.body, .semibold))
                        Text(title).font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("backup.change") { picking = true }.font(.app(.subheadline))
                }
            } else {
                Text("backup.pick.hint").font(.app(.footnote)).foregroundStyle(.secondary)
                Button { picking = true } label: { Label("backup.pick", systemImage: "folder.badge.plus").onbChip(selected: true) }
                    .buttonStyle(.plain)
            }
        }
        .backupFolderImporter(isPresented: $picking)
    }
}

/// Шаг онбординга «Где хранить копии».
struct OnbBackupStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnbHeader(icon: "icloud.and.arrow.up", title: "backup.step.title", subtitle: "backup.step.subtitle")
            BackupSetupCard()
        }
        .onAppear { AutoBackup.shared.asked = true }
    }
}

/// Отдельное окно для тех, кто прошёл онбординг до появления копий.
struct BackupPromptSheet: View {
    var backup = AutoBackup.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { OnbBackupStep().padding(20) }
            Button { dismiss() } label: {
                Text(backup.hasFolder ? "common.done" : "backup.later").font(.app(.headline)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Theme.brand).foregroundStyle(Theme.onBrand)
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        // Папку выбрали: окно больше не нужно.
        .onChange(of: backup.hasFolder) { if backup.hasFolder { dismiss() } }
    }
}

// MARK: - Настройки

struct BackupSettingsView: View {
    @Bindable var backup = AutoBackup.shared
    @State private var picking = false

    var body: some View {
        Form {
            Section { BackupStatusLabel() }
            Section {
                Button { picking = true } label: {
                    HStack {
                        Text(backup.hasFolder ? "backup.folder" : "backup.pick"); Spacer()
                        if let t = backup.folderTitle, backup.hasFolder { Text(t).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                Toggle("backup.auto", isOn: $backup.enabled)
            } footer: { Text("backup.auto.footer") }
            if backup.hasFolder {
                Section {
                    Button {
                        Task { await backup.backupNow() }
                    } label: {
                        HStack { Text("backup.now"); Spacer(); if backup.isWorking { ProgressView() } }
                    }
                    .disabled(backup.isWorking)
                    NavigationLink("backup.restore") { BackupListView() }
                }
            }
        }
        .themedScreen()
        .navigationTitle("backup.title")
        .backupFolderImporter(isPresented: $picking)
    }
}

// MARK: - Восстановление

/// Список копий в папке, свежие сверху. Нажатие на копию заменяет данные после подтверждения.
struct BackupListView: View {
    var onRestored: () -> Void = {}
    @Environment(RatesStore.self) private var rates
    @Environment(\.dismiss) private var dismiss
    var backup = AutoBackup.shared
    @State private var entries: [AutoBackup.Entry] = []
    @State private var loaded = false
    @State private var picking = false
    @State private var chosen: AutoBackup.Entry?
    @State private var restoring = false
    @State private var errorKey: LocalizedStringKey?
    @State private var done = false

    var body: some View {
        List {
            if !backup.hasFolder {
                Section {
                    Button("backup.pick") { picking = true }
                } footer: { Text("onb.restore.pickFolder") }
            } else {
                Section {
                    if loaded && entries.isEmpty {
                        Text("backup.list.empty").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { e in
                        Button { chosen = e } label: { row(e) }.disabled(restoring)
                    }
                } header: {
                    if let t = backup.folderTitle { Text(t) }
                } footer: {
                    Button("backup.change") { picking = true }.font(.app(.footnote))
                }
            }
        }
        .themedScreen()
        .navigationTitle("backup.list.title")
        .overlay { if restoring { ProgressView().controlSize(.large) } }
        .task { reload() }
        .refreshable { reload() }
        .backupFolderImporter(isPresented: $picking) { reload() }
        .confirmationDialog("backup.confirm.title", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { e in
            Button("backup.confirm.action", role: .destructive) { restore(e) }
        } message: { e in
            Text(fmt("backup.confirm.message", e.date.formatted(date: .long, time: .shortened)))
        }
        .alert(errorKey ?? "", isPresented: Binding(get: { errorKey != nil }, set: { if !$0 { errorKey = nil } })) {
            Button("common.ok", role: .cancel) {}
        }
        .alert("backup.restored", isPresented: $done) {
            Button("common.ok") { onRestored(); dismiss() }
        }
    }

    private func row(_ e: AutoBackup.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.primary)
            let size = e.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—"
            Text(fmt("backup.list.row", e.transactions, size)).font(.app(.caption)).foregroundStyle(.secondary)
        }
    }

    private func reload() {
        guard backup.hasFolder else { return }
        entries = (try? backup.list()) ?? []
        loaded = true
    }

    private func restore(_ e: AutoBackup.Entry) {
        restoring = true
        Task {
            defer { restoring = false }
            do {
                try await backup.restore(e, rates: rates)
                done = true
            } catch BackupSnapshot.Failure.newerVersion {
                errorKey = "backup.error.newer"
            } catch let error as CocoaError where error.code == .fileWriteUnknown {
                errorKey = "backup.error.safety"
            } catch {
                errorKey = "backup.error.read"
            }
        }
    }
}

/// Восстановление с первого экрана онбординга.
struct BackupRestoreSheet: View {
    let onRestored: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BackupListView(onRestored: onRestored)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
    }
}

// MARK: - Плашка на главном экране

/// Видна, только когда с копиями что-то не так. Ведёт в настройки копий.
struct BackupBanner: View {
    var backup = AutoBackup.shared
    /// Короткая плашка в одну строку для шапки главного экрана, где на полный баннер нет места.
    var compact = false
    @State private var open = false

    var body: some View {
        if backup.needsAttention {
            Button { open = true } label: {
                if compact {
                    Label { Text(title).lineLimit(1).minimumScaleFactor(0.8) } icon: {
                        Image(systemName: backup.hasFolder ? "exclamationmark.icloud" : "icloud.slash")
                    }
                    .font(.app(.caption, .semibold)).foregroundStyle(Theme.warn)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Theme.warn.opacity(0.14), in: Capsule())
                } else {
                HStack(spacing: 12) {
                    Image(systemName: backup.hasFolder ? "exclamationmark.icloud" : "icloud.slash")
                        .font(.app(.title3)).foregroundStyle(Theme.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.app(.subheadline, .semibold)).foregroundStyle(.primary)
                        Text(subtitle).font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.app(.caption, .semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $open) {
                NavigationStack {
                    BackupSettingsView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { open = false } } }
                }
            }
        }
    }

    private var title: LocalizedStringKey {
        if !backup.hasFolder { return "backup.banner.noFolder" }
        return backup.failed ? "backup.banner.failed" : "backup.banner.stale"
    }
    private var subtitle: LocalizedStringKey { backup.hasFolder ? "backup.banner.fix" : "backup.banner.setup" }
}
