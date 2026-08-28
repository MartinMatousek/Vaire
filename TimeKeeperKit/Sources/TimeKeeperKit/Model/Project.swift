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
}
