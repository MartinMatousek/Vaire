import Foundation
import GRDB

public struct Project: Identifiable, Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var name: String
    public var path: String
    public var colorHex: String
    public var mdHoursPerDay: Double

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        colorHex: String = "#34C759",
        mdHoursPerDay: Double = 8.0
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.colorHex = colorHex
        self.mdHoursPerDay = mdHoursPerDay
    }

    public static let databaseTableName = "project"

    public static func find(byPath path: String, db: AppDatabase) throws -> Project? {
        try db.dbQueue.read { conn in
            try Project.filter(Column("path") == path).fetchOne(conn)
        }
    }

    /// Finds the project at `path`, creating one named after the path's last
    /// component if none exists yet. Used by integrations (CLI, hooks) that
    /// must never block on missing setup in the app.
    public static func findOrCreate(byPath path: String, db: AppDatabase) throws -> Project {
        if let existing = try find(byPath: path, db: db) {
            return existing
        }
        let name = (path as NSString).lastPathComponent
        let project = Project(name: name, path: path)
        try db.dbQueue.write { conn in
            try project.insert(conn)
        }
        return project
    }
}
