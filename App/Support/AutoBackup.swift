import Foundation
import Observation
import SwiftData
import UIKit
import LedgerCore

/// Автокопия: после каждого изменения базы через пару секунд в выбранную папку (обычно iCloud Drive) пишется свежий файл.
/// Папку человек выбирает один раз, доступ к ней запоминается закладкой.
@MainActor @Observable final class AutoBackup {
    static let shared = AutoBackup()

    /// Папка с копиями внутри выбранной: в корне iCloud Drive мусорить не хотим.
    static let folderName = "Срудж Богдан"

    struct Entry: Identifiable, Hashable {
        let url: URL
        let date: Date
        let transactions: Int
        let size: Int?
        var id: URL { url }
    }

    private(set) var folderTitle: String?
    private(set) var lastSuccess: Date?
    /// Последняя попытка не удалась: папка недоступна или iCloud Drive выключен.
    private(set) var failed = false
    private(set) var isWorking = false
    var enabled: Bool { didSet { ud.set(enabled, forKey: Keys.enabled); if enabled { schedule() } } }
    /// В базе есть изменения, которые ещё не попали в копию.
    private(set) var dirty: Bool { didSet { ud.set(dirty, forKey: Keys.dirty) } }

    /// Хранится отдельным свойством, а не читается из настроек на лету: иначе экраны не узнают, что папку только что выбрали.
    private(set) var hasFolder: Bool

    /// Плашка на главном экране: копии не настроены, не пишутся или давно не обновлялись.
    var needsAttention: Bool {
        guard enabled else { return false }
        if !hasFolder || failed { return true }
        guard let last = lastSuccess else { return false }
        return dirty && last < Date().addingTimeInterval(-3 * 86400)
    }

    private enum Keys {
        static let bookmark = "backup.bookmark", sub = "backup.subfolder", title = "backup.title"
        static let last = "backup.last", enabled = "backup.enabled", dirty = "backup.dirty", asked = "backup.asked"
    }
    private let ud = UserDefaults.standard
    private var pending: Task<Void, Never>?
    private var context: ModelContext?
    private var baseCurrency: () -> String = { "" }

    /// Спросили ли уже про копии (в онбординге или отдельным окном).
    var asked: Bool {
        get { ud.bool(forKey: Keys.asked) }
        set { ud.set(newValue, forKey: Keys.asked) }
    }

    private init() {
        enabled = ud.object(forKey: Keys.enabled) as? Bool ?? true
        dirty = ud.bool(forKey: Keys.dirty)
        lastSuccess = ud.object(forKey: Keys.last) as? Date
        folderTitle = ud.string(forKey: Keys.title)
        hasFolder = ud.data(forKey: Keys.bookmark) != nil
    }

    /// Подключается к базе: каждое сохранение помечает данные изменёнными и откладывает копию.
    func start(container: ModelContainer, rates: RatesStore) {
        guard context == nil else { return }
        context = container.mainContext
        baseCurrency = { rates.base }
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AutoBackup.shared.dirty = true
                AutoBackup.shared.schedule()
            }
        }
        if dirty { schedule() }
    }

    /// Копия через 3 секунды тишины: серия правок даёт один файл.
    func schedule(delay: Duration = .seconds(3)) {
        pending?.cancel()
        guard enabled, hasFolder else { return }
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await backupNow()
        }
    }

    /// При уходе приложения в фон пишем сразу, не дожидаясь паузы.
    func flush() {
        guard dirty, enabled, hasFolder else { return }
        pending?.cancel()
        let id = UIApplication.shared.beginBackgroundTask()
        Task {
            await backupNow()
            UIApplication.shared.endBackgroundTask(id)
        }
    }

    // MARK: Папка

    /// Запоминает выбранную папку. Если это не наша папка, копии лягут в подпапку «Срудж Богдан».
    func setFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let own = url.lastPathComponent == Self.folderName || !Self.scan(url).isEmpty
        ud.set(bookmark, forKey: Keys.bookmark)
        hasFolder = true
        ud.set(own ? "" : Self.folderName, forKey: Keys.sub)
        let title = own ? url.lastPathComponent : "\(url.lastPathComponent)/\(Self.folderName)"
        ud.set(title, forKey: Keys.title)
        folderTitle = title
        failed = false
        asked = true
        dirty = true
        schedule(delay: .zero)
    }

    /// Открывает доступ к папке копий на время `body`.
    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        let r = try Self.inFolder(bookmark: ud.data(forKey: Keys.bookmark), sub: ud.string(forKey: Keys.sub) ?? "", body)
        if let fresh = r.fresh { ud.set(fresh, forKey: Keys.bookmark) }
        return r.value
    }

    /// То же без обращения к настройкам, чтобы работать и в фоне. `fresh` это обновлённая закладка, если старая устарела.
    private nonisolated static func inFolder<T>(bookmark: Data?, sub: String, _ body: (URL) throws -> T) throws -> (value: T, fresh: Data?) {
        guard let data = bookmark else { throw CocoaError(.fileNoSuchFile) }
        var stale = false
        let root = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fresh = stale ? try? root.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        let folder = sub.isEmpty ? root : root.appendingPathComponent(sub, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try body(folder), fresh)
    }

    // MARK: Запись

    /// Пишет копию сейчас. Пустую базу (до онбординга) не сохраняем, чтобы не плодить пустые файлы.
    @discardableResult func backupNow() async -> Bool {
        guard let ctx = context, hasFolder, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        // Копия собирается из того, что уже на диске, поэтому сначала дописываем свежие правки.
        SaveGuard.shared.saveNow()
        let settings = BackupSnapshot.currentSettings(base: baseCurrency())
        let container = ctx.container
        let snapshot: BackupSnapshot
        // Сборка копии перебирает всю базу: делаем это в фоне, чтобы экран не замирал.
        do { snapshot = try await Task.detached(priority: .utility) { try BackupSnapshot.make(ctx: ModelContext(container), settings: settings) }.value }
        catch { failed = true; return false }
        guard !snapshot.accounts.isEmpty || !snapshot.transactions.isEmpty else { dirty = false; return true }
        dirty = false
        let name = BackupFiles.name(date: snapshot.created, transactions: snapshot.transactions.count)
        do {
            // Упаковка и запись в iCloud Drive идут в фоне: на главном потоке они подвешивали экран
            // через три секунды после каждой правки.
            let bookmark = ud.data(forKey: Keys.bookmark), sub = ud.string(forKey: Keys.sub) ?? ""
            let fresh = try await Task.detached(priority: .utility) {
                let data = try snapshot.encoded()
                return try Self.inFolder(bookmark: bookmark, sub: sub) { folder in
                    try Self.coordinatedWrite(data, to: folder.appendingPathComponent(name))
                    Self.prune(folder)
                }.fresh
            }.value
            if let fresh { ud.set(fresh, forKey: Keys.bookmark) }
            lastSuccess = snapshot.created
            ud.set(snapshot.created, forKey: Keys.last)
            failed = false
            // Пока файл писался, данные могли измениться ещё раз: эта правка попадёт в следующую копию.
            if dirty { schedule() }
            return true
        } catch {
            dirty = true
            failed = true
            return false
        }
    }

    private nonisolated static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }

    /// Удаляет лишние старые копии по правилу из LedgerCore.
    private nonisolated static func prune(_ folder: URL) {
        let entries = scan(folder)
        for i in BackupFiles.expired(entries.map(\.date)) {
            NSFileCoordinator().coordinate(writingItemAt: entries[i].url, options: .forDeleting, error: nil) { u in
                try? FileManager.default.removeItem(at: u)
            }
        }
    }

    // MARK: Список и чтение

    private nonisolated static func scan(_ folder: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .totalFileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { f in
            guard let p = BackupFiles.parse(f.lastPathComponent) else { return nil }
            let v = try? f.resourceValues(forKeys: Set(keys))
            return Entry(url: folder.appendingPathComponent(p.name), date: p.date, transactions: p.transactions,
                         size: v?.fileSize ?? v?.totalFileSize)
        }
        .sorted { $0.date > $1.date }
    }

    func list() throws -> [Entry] { try withFolder { Self.scan($0) } }

    /// Читает копию. Если файл ещё в облаке, координатор сначала скачает его.
    func load(_ entry: Entry) throws -> BackupSnapshot {
        try withFolder { _ in
            try? FileManager.default.startDownloadingUbiquitousItem(at: entry.url)
            var coordError: NSError?
            var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
            NSFileCoordinator().coordinate(readingItemAt: entry.url, options: [], error: &coordError) { u in
                result = Result { try Data(contentsOf: u) }
            }
            if let coordError { throw coordError }
            return try BackupSnapshot.decode(result.get())
        }
    }

    /// Заменяет данные копией. Перед этим текущие данные сохраняются отдельной копией, чтобы ошибку можно было откатить.
    func restore(_ entry: Entry, rates: RatesStore) async throws {
        guard let ctx = context else { return }
        let snapshot = try load(entry)
        pending?.cancel()
        // Дожидаемся копии, которая пишется прямо сейчас: иначе страховочная копия перед заменой не создастся.
        while isWorking { try? await Task.sleep(for: .milliseconds(100)) }
        dirty = true
        guard await backupNow() || !hasFolder else { throw CocoaError(.fileWriteUnknown) }
        try snapshot.restore(into: ctx, rates: rates)
        asked = true
    }
}
