import Foundation
import Testing
@testable import VaireKit

@Test func exportsRowsWithProjectNamesResolved() throws {
    let db = try AppDatabase.inMemory()
    let project = Project(name: "kvk-fe", path: "/tmp/kvk-fe")
    try db.dbQueue.write { try project.insert($0) }

    let block = Block(
        projectId: project.id,
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 3600),
        source: .manual,
        note: "fixing a bug"
    )
    try db.dbQueue.write { try block.insert($0) }

    let rows = try BlockExporter.exportRows(db: db, from: Date(timeIntervalSince1970: -1), to: Date(timeIntervalSince1970: 7200))
    #expect(rows.count == 1)
    #expect(rows[0].projectName == "kvk-fe")
    #expect(rows[0].hours == 1.0)
}

@Test func csvEscapesQuotesInNotes() {
    let row = ExportedBlock(
        projectName: "p",
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 3600),
        hours: 1,
        source: "manual",
        isManual: true,
        note: #"said "hi""#
    )
    let csv = BlockExporter.csv(rows: [row])
    #expect(csv.contains(#""said ""hi""""#))
}

@Test func jsonRoundTripsExportedBlocks() throws {
    let row = ExportedBlock(
        projectName: "p",
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 3600),
        hours: 1,
        source: "manual",
        isManual: true,
        note: nil
    )
    let data = try BlockExporter.json(rows: [row])
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode([ExportedBlock].self, from: data)
    #expect(decoded.count == 1)
    #expect(decoded[0].projectName == "p")
}
