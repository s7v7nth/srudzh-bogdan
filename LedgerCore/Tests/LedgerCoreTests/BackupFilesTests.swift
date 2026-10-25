import XCTest
@testable import LedgerCore

final class BackupFilesTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 9) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: hour))! }

    // MARK: Имя файла
    func testNameRoundTrip() {
        let date = d(2026, 10, 25, hour: 14)
        let name = BackupFiles.name(date: date, transactions: 1240)
        XCTAssertEqual(name, "srudzh-20261025-140000-n1240.json")
        let parsed = BackupFiles.parse(name)
        XCTAssertEqual(parsed?.date, date)
        XCTAssertEqual(parsed?.transactions, 1240)
    }

    func testParsesNotDownloadedICloudFile() {
        let parsed = BackupFiles.parse(".srudzh-20261025-140000-n7.json.icloud")
        XCTAssertEqual(parsed?.name, "srudzh-20261025-140000-n7.json")
        XCTAssertEqual(parsed?.transactions, 7)
    }

    func testIgnoresForeignFiles() {
        XCTAssertNil(BackupFiles.parse("notes.json"))
        XCTAssertNil(BackupFiles.parse("srudzh-20261025-140000.json"))
        XCTAssertNil(BackupFiles.parse("srudzh-2026-1025-140000-n1.json"))
        XCTAssertNil(BackupFiles.parse("srudzh-20261025-140000-n1.txt"))
    }

    // MARK: Сколько хранить
    func testKeepsEverythingUnderLimit() {
        let dates = (1...10).map { d(2026, 10, $0) }
        XCTAssertTrue(BackupFiles.expired(dates, keepRecent: 30, calendar: cal).isEmpty)
    }

    func testKeepsRecentAndOnePerOlderMonth() {
        // 5 копий в октябре (свежие), по 3 в сентябре и августе.
        let oct = (20...24).map { d(2026, 10, $0) }
        let sep = [d(2026, 9, 5), d(2026, 9, 28), d(2026, 9, 15)]
        let aug = [d(2026, 8, 1), d(2026, 8, 31), d(2026, 8, 10)]
        let dates = sep + oct + aug
        let gone = BackupFiles.expired(dates, keepRecent: 5, calendar: cal)
        let goneDates = Set(gone.map { dates[$0] })
        // Из старых месяцев остаётся самая свежая копия месяца.
        XCTAssertEqual(goneDates, [d(2026, 9, 5), d(2026, 9, 15), d(2026, 8, 1), d(2026, 8, 10)])
    }

    func testOlderCopiesOfRecentMonthAreDropped() {
        // Свежие копии уже покрывают октябрь, старые октябрьские не нужны.
        let dates = [d(2026, 10, 1), d(2026, 10, 2), d(2026, 10, 3), d(2026, 10, 4)]
        let gone = BackupFiles.expired(dates, keepRecent: 2, calendar: cal)
        XCTAssertEqual(Set(gone.map { dates[$0] }), [d(2026, 10, 1), d(2026, 10, 2)])
    }
}
