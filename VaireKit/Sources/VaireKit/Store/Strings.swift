import Foundation

/// All user-facing UI strings for the app, widget, and hook scripts, in
/// both supported languages. The active language is read once at process
/// start (`AppLanguage.current()`) and cached — switching languages in
/// Settings writes the new choice and asks the user to restart, rather
/// than making every view observe language state reactively.
public enum Strings {
    public static let language: AppLanguage = AppLanguage.current()

    private static func pick(cs: String, en: String) -> String {
        language == .cs ? cs : en
    }

    // MARK: - ContentView (menu bar dropdown)

    public static var noProjects: String { pick(cs: "Žádné projekty. Přidej je v nastavení.", en: "No projects yet. Add one in Settings.") }
    public static var week: String { pick(cs: "Týden…", en: "Week…") }
    public static var settings: String { pick(cs: "Nastavení…", en: "Settings…") }
    public static var quit: String { pick(cs: "Ukončit", en: "Quit") }
    public static var start: String { pick(cs: "Start", en: "Start") }
    public static var stop: String { pick(cs: "Stop", en: "Stop") }
    public static var unfollow: String { pick(cs: "Odebrat", en: "Remove") }
    public static var resumeTodaysEntry: String { pick(cs: "Navázat na dnešní záznam?", en: "Continue today's entry?") }
    public static var newEntry: String { pick(cs: "Nový záznam", en: "New entry") }
    public static var activityDescription: String { pick(cs: "Popis aktivity (než zapomeneš)", en: "What are you working on (before you forget)") }
    public static var whatWillYouDoPlaceholder: String { pick(cs: "Co budeš dělat…", en: "What will you do…") }
    public static var effortEstimateHours: String { pick(cs: "Odhad pracnosti (h):", en: "Effort estimate (h):") }
    public static var effortExample: String { pick(cs: "např. 2", en: "e.g. 2") }
    public static var withoutNote: String { pick(cs: "Bez poznámky", en: "No note") }
    public static var resume: String { pick(cs: "Navázat", en: "Continue") }
    public static var editTimeAndDescription: String { pick(cs: "Uprav čas a popis", en: "Edit time and description") }
    public static func measuredOnTimer(_ elapsed: String) -> String { pick(cs: "Naměřeno na timeru: \(elapsed)", en: "Measured by timer: \(elapsed)") }
    public static var whatDidYouDoPlaceholder: String { pick(cs: "Co jsi dělal…", en: "What did you do…") }
    public static var estimateWithoutAI: String { pick(cs: "Odhad bez AI", en: "Estimate without AI") }
    public static var estimateLowerThanMeasured: String { pick(cs: "Odhad je nižší než naměřený čas", en: "Estimate is lower than the measured time") }
    public static var discard: String { pick(cs: "Zahodit", en: "Discard") }
    public static var `continue`: String { pick(cs: "Pokračovat", en: "Continue") }
    public static var save: String { pick(cs: "Uložit", en: "Save") }

    // MARK: - TimeSavedView

    public static func timeSavedTitle(_ weekRange: String) -> String { pick(cs: "Úspora času — \(weekRange)", en: "Time saved — \(weekRange)") }
    public static var noEstimatesThisWeek: String { pick(cs: "Žádné odhady tento týden. Claude si je zapisuje sám na konci session s netriviální prací.", en: "No estimates this week. Claude records them itself at the end of sessions with non-trivial work.") }
    public static var actualTime: String { pick(cs: "Reálný čas", en: "Actual time") }
    public static var saved: String { pick(cs: "Ušetřeno", en: "Saved") }
    public static func actualVsEstimate(actual: String, estimate: String) -> String { pick(cs: "Reálně \(actual) · Odhad \(estimate)", en: "Actual \(actual) · Estimate \(estimate)") }
    public static var editEstimate: String { pick(cs: "Upravit odhad…", en: "Edit estimate…") }
    public static var estimateWithoutAIHours: String { pick(cs: "Odhad bez AI (hodiny)", en: "Estimate without AI (hours)") }
    public static var estimateExample: String { pick(cs: "např. 2.5", en: "e.g. 2.5") }
    public static var cancel: String { pick(cs: "Zrušit", en: "Cancel") }

    // MARK: - DailyReviewScheduler

    public static var dailySummaryTitle: String { pick(cs: "Vaire — denní shrnutí", en: "Vaire — daily summary") }
    public static var dailySummaryBody: String { pick(cs: "Zkontroluj a uprav dnešní bloky.", en: "Review and edit today's blocks.") }

    // MARK: - Window titles

    public static var weekWindowTitle: String { pick(cs: "Vaire — Týden", en: "Vaire — Week") }
    public static var settingsWindowTitle: String { pick(cs: "Vaire — Nastavení", en: "Vaire — Settings") }

    // MARK: - SettingsView

    public static var projects: String { pick(cs: "Projekty", en: "Projects") }
    public static var track: String { pick(cs: "Sledovat", en: "Track") }
    public static var importFromGit: String { pick(cs: "Import z gitu", en: "Import from git") }
    public static var name: String { pick(cs: "Název", en: "Name") }
    public static var path: String { pick(cs: "Cesta", en: "Path") }
    public static var choose: String { pick(cs: "Vybrat…", en: "Choose…") }
    public static var add: String { pick(cs: "Přidat", en: "Add") }
    public static var addProjectHint: String { pick(cs: "Nově přidaný projekt se rovnou sleduje pomocí Claude Code hooků. Zaškrtnutí „Sledovat\u{201C} zapíná/vypíná sledování pro existující projekty.", en: "A newly added project is tracked by Claude Code hooks right away. Checking \u{201C}Track\u{201D} turns tracking on/off for existing projects.") }
    public static var exportCSV: String { pick(cs: "Export CSV", en: "Export CSV") }
    public static var exportJSON: String { pick(cs: "Export JSON", en: "Export JSON") }
    public static func addProjectFailed(_ message: String) -> String { pick(cs: "Nepodařilo se přidat projekt: \(message)", en: "Failed to add project: \(message)") }
    public static func trackToggleFailed(_ message: String) -> String { pick(cs: "Nepodařilo se změnit sledování: \(message)", en: "Failed to change tracking: \(message)") }
    public static func exportFailed(_ message: String) -> String { pick(cs: "Export selhal: \(message)", en: "Export failed: \(message)") }
    public static var importing: String { pick(cs: "Importuji…", en: "Importing…") }
    public static func importSummary(commits: Int, blocks: Int) -> String { pick(cs: "Naimportováno \(commits) commitů, \(blocks) bloků.", en: "Imported \(commits) commits, \(blocks) blocks.") }
    public static func importFailed(_ message: String) -> String { pick(cs: "Import selhal: \(message)", en: "Import failed: \(message)") }
    public static var languageLabel: String { pick(cs: "Jazyk", en: "Language") }
    public static var languageCzech: String { pick(cs: "Čeština", en: "Czech") }
    public static var languageEnglish: String { pick(cs: "Angličtina", en: "English") }
    public static var languageRestartHint: String { pick(cs: "Změna jazyka se projeví po restartu aplikace.", en: "Language change takes effect after restarting the app.") }

    // MARK: - HoursMinutesField

    public static var hoursAbbrev: String { pick(cs: "h", en: "h") }
    public static var minutesAbbrev: String { pick(cs: "m", en: "m") }

    // MARK: - WeekView

    public static var today: String { pick(cs: "Dnes", en: "Today") }
    public static var reportBug: String { pick(cs: "Nahlásit bug", en: "Report bug") }
    public static var savings: String { pick(cs: "Úspory", en: "Savings") }
    public static var delete: String { pick(cs: "Smazat", en: "Delete") }
    public static var undo: String { pick(cs: "Zpět", en: "Undo") }
    public static var redo: String { pick(cs: "Znovu", en: "Redo") }
    public static func blockLabel(project: String, duration: String) -> String { "\(project) — \(duration)" }
    public static var edit: String { pick(cs: "Upravit…", en: "Edit…") }
    public static func runningLabel(project: String, hours: String) -> String { pick(cs: "● Běží: \(project) — \(hours)", en: "● Running: \(project) — \(hours)") }
    public static var activityDescriptionLabel: String { pick(cs: "Popis aktivity", en: "Activity description") }
    public static var timeLabel: String { pick(cs: "Čas", en: "Time") }
    public static func actionFailedStale(_ action: String) -> String { pick(cs: "\(action) se nepodařilo — záznam se mezitím aktualizoval (např. živým importem). Zkus to prosím znovu.", en: "\(action) failed — the record was updated in the meantime (e.g. by a live import). Please try again.") }
    public static func actionFailed(action: String, message: String) -> String { pick(cs: "\(action) selhalo: \(message)", en: "\(action) failed: \(message)") }
    public static var actionSaveEdits: String { pick(cs: "Uložení úprav", en: "Saving edits") }
    public static var actionMove: String { pick(cs: "Přesun", en: "Move") }
    public static var actionDelete: String { pick(cs: "Smazání", en: "Delete") }

    // MARK: - Widget

    public static func widgetProjectLine(project: String, hours: String) -> String { "\(project): \(hours)" }
    public static var widgetTodaySuffix: String { pick(cs: "dnes", en: "today") }
    public static var widgetDisplayName: String { "Vaire" }
    public static var widgetDescription: String { pick(cs: "Dnešní odpracovaný čas.", en: "Today's worked time.") }
}
