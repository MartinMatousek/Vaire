import Foundation
import EventKit

public struct MeetingCandidate: Equatable, Sendable {
    public let eventIdentifier: String
    public let title: String
    public let start: Date
    public let end: Date

    public init(eventIdentifier: String, title: String, start: Date, end: Date) {
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.start = start
        self.end = end
    }
}

public enum MeetingImporterError: Error {
    case accessDenied
}

public enum MeetingImporter {
    /// Default title of the calendar that carries real meeting content,
    /// used until the user configures their own in Settings
    /// (`CalendarSetting`). A synced Exchange account can also expose
    /// delegate/shared calendars (e.g. a colleague's, viewed for scheduling)
    /// that only return free/busy placeholders ("Free"/"Tentative" as the
    /// title) — those must be excluded rather than filtered after the fact,
    /// since there's no reliable per-event signal that distinguishes them.
    public static let defaultCalendarTitle = "Work"

    /// Requests calendar access if needed, then fetches "real meeting"
    /// events for `day`: canceled and all-day events are dropped, as are
    /// events with neither a location nor another attendee — those are
    /// personal busy-time blocks (e.g. a recurring focus slot), not
    /// meetings someone else called. `calendarTitles` scopes the search to
    /// specific calendars (e.g. the work Exchange calendar) since a synced
    /// account can also carry delegate/shared calendars that only expose
    /// free/busy placeholders.
    /// Requests calendar access if needed, then returns the titles of all
    /// event calendars available to the user (across every synced
    /// account), sorted for display in a picker. Includes delegate/shared
    /// calendars that only expose free/busy placeholders — Settings can't
    /// tell those apart from a real one without inspecting events, so it's
    /// up to the user to pick the right title, same as before when they
    /// typed it in by hand.
    public static func fetchCalendarTitles() async throws -> [String] {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw MeetingImporterError.accessDenied
        }
        return store.calendars(for: .event).map(\.title).sorted()
    }

    public static func fetchMeetings(
        day: Date,
        calendarTitles: Set<String>,
        calendar: Calendar = .current
    ) async throws -> [MeetingCandidate] {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw MeetingImporterError.accessDenied
        }

        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let matchingCalendars = store.calendars(for: .event).filter { calendarTitles.contains($0.title) }
        guard !matchingCalendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: matchingCalendars)
        let events = store.events(matching: predicate)

        return events.compactMap { event -> MeetingCandidate? in
            guard event.status != .canceled, !event.isAllDay else { return nil }
            let hasLocation = !(event.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            let hasOtherAttendee = (event.attendees ?? []).contains { !$0.isCurrentUser }
            guard hasLocation || hasOtherAttendee else { return nil }
            guard let start = event.startDate, let end = event.endDate else { return nil }

            return MeetingCandidate(
                eventIdentifier: event.eventIdentifier,
                title: event.title ?? "",
                start: start,
                end: end
            )
        }.sorted { $0.start < $1.start }
    }
}
