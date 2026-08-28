import Foundation
import GRDB

public struct ExportedBlock: Codable, Sendable {
    public let projectName: String
    public let start: Date
    public let end: Date
    public let hours: Double
    public let source: String
    public let isManual: Bool
    public let note: String?
}

public enum BlockExporter {
    public static func exportRows(db: AppDatabase, from start: Date, to end: Date) throws -> [ExportedBlock] {
        try db.dbQueue.read { conn in
            let projects = try Project.fetchAll(conn)
            let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })

            let blocks = try Block
                .filter(Column("start") < end && Column("end") > start)
                .fetchAll(conn)

            return blocks.map { block in
                ExportedBlock(
                    projectName: projectsById[block.projectId]?.name ?? "unknown",
                    start: block.start,
                    end: block.end,
                    hours: block.duration / 3600,
                    source: block.source.rawValue,
                    isManual: block.isManual,
                    note: block.note
                )
            }
        }
    }

    public static func csv(rows: [ExportedBlock]) -> String {
        let isoFormatter = ISO8601DateFormatter()
        var lines = ["project,start,end,hours,source,isManual,note"]
        for row in rows {
            let note = (row.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let escapedNote = note.isEmpty ? "" : "\"\(note)\""
            lines.append([
                row.projectName,
                isoFormatter.string(from: row.start),
                isoFormatter.string(from: row.end),
                String(format: "%.2f", row.hours),
                row.source,
                row.isManual ? "true" : "false",
                escapedNote
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    public static func json(rows: [ExportedBlock]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }
}
