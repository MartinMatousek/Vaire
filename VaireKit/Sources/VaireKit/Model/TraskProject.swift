import Foundation
import GRDB

/// A project from Trask's timesheet catalog (my.trask.cz), scraped from the
/// live "Log time" form since Trask has no API. `id` is the stable trailing
/// code from the scraped label (e.g. "ET97" from "ČEZ Prodej - Produkty a
/// KVK - FY27 - ET97") — the client/fiscal-year prefix changes yearly, but
/// this code was confirmed stable across the scrape. `active` is flipped
/// off by a re-scrape that no longer sees this project, rather than
/// deleting the row, so a project already paired to a Vaire project can be
/// detected as stale instead of silently pointing at nothing.
public struct TraskProject: Identifiable, Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var label: String
    public var active: Bool

    public init(id: String, label: String, active: Bool = true) {
        self.id = id
        self.label = label
        self.active = active
    }

    public static let databaseTableName = "traskProject"
}
