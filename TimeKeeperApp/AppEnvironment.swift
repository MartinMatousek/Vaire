import Foundation
import TimeKeeperKit

enum AppEnvironment {
    static let db: AppDatabase = {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let dbPath = supportDir.appendingPathComponent("timekeeper.sqlite").path
        return try! AppDatabase(path: dbPath)
    }()

    static let timer = TimerController(db: db)
}
