import Foundation
import TimeKeeperKit

enum AppEnvironment {
    static let db: AppDatabase = {
        try! AppDatabase(path: try! SharedStorage.databasePath())
    }()

    static let timer = TimerController(db: db)
}
