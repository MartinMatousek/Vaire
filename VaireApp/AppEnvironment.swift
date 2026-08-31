import Foundation
import VaireKit

enum AppEnvironment {
    static let db: AppDatabase = {
        try! AppDatabase(path: try! SharedStorage.databasePath())
    }()

    static let timer = TimerController(db: db)
}
