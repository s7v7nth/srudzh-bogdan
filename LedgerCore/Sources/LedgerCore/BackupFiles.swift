import Foundation

/// Имена файлов автокопий и правило, какие копии хранить.
public enum BackupFiles {
    public static let ext = "json"
    static let prefix = "srudzh-"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// `srudzh-20261025-143210-n1240.json`: время копии (UTC) и число операций, чтобы список копий не открывал каждый файл.
    public static func name(date: Date, transactions: Int) -> String {
        "\(prefix)\(formatter.string(from: date))-n\(transactions).\(ext)"
    }

    /// Разбирает имя копии. Файлы iCloud, ещё не скачанные на телефон, называются `.имя.icloud`: их тоже узнаём.
    public static func parse(_ fileName: String) -> (date: Date, transactions: Int, name: String)? {
        var name = fileName
        if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(".icloud".count)) }
        guard name.hasPrefix(prefix), name.hasSuffix(".\(ext)") else { return nil }
        let body = name.dropFirst(prefix.count).dropLast(ext.count + 1)
        let parts = body.split(separator: "-")
        guard parts.count == 3, parts[2].hasPrefix("n"), let count = Int(parts[2].dropFirst()),
              let date = formatter.date(from: "\(parts[0])-\(parts[1])") else { return nil }
        return (date, count, name)
    }

    /// Номера копий, которые пора удалить. Остаются `keepRecent` самых свежих и по одной, самой свежей, за каждый более старый месяц.
    public static func expired(_ dates: [Date], keepRecent: Int = 30, calendar: Calendar = .current) -> Set<Int> {
        let order = dates.indices.sorted { dates[$0] > dates[$1] }
        var keptMonths = Set<DateComponents>()
        var result = Set<Int>()
        for (rank, i) in order.enumerated() {
            let month = calendar.dateComponents([.year, .month], from: dates[i])
            if rank < keepRecent { keptMonths.insert(month); continue }
            if keptMonths.insert(month).inserted { continue }
            result.insert(i)
        }
        return result
    }
}
