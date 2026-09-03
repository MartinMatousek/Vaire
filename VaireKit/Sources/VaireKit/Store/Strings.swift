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
    public static var effortEstimateHours: String { pick(cs: "Odhad pracnosti:", en: "Effort estimate:") }
    public static var withoutNote: String { pick(cs: "Bez poznámky", en: "No note") }
    public static var dontLog: String { pick(cs: "Nelogovat", en: "Don't log") }
    public static var resume: String { pick(cs: "Navázat", en: "Continue") }
    public static func logTimeFor(_ project: String) -> String { pick(cs: "Logovat čas pro \(project)", en: "Log time for \(project)") }
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
    public static var estimateWithoutAIHours: String { pick(cs: "Odhad bez AI", en: "Estimate without AI") }
    public static var cancel: String { pick(cs: "Zrušit", en: "Cancel") }
    public static var close: String { pick(cs: "Zavřít", en: "Close") }

    // MARK: - DailyReviewScheduler

    public static var dailySummaryTitle: String { pick(cs: "Vaire — denní shrnutí", en: "Vaire — daily summary") }
    public static var dailySummaryBody: String { pick(cs: "Zkontroluj a uprav dnešní bloky.", en: "Review and edit today's blocks.") }

    // MARK: - Window titles

    public static var weekWindowTitle: String { pick(cs: "Vaire — Týden", en: "Vaire — Week") }
    public static var settingsWindowTitle: String { pick(cs: "Vaire — Nastavení", en: "Vaire — Settings") }

    // MARK: - SettingsView

    public static var projects: String { pick(cs: "Projekty", en: "Projects") }
    public static var track: String { pick(cs: "Sledovat", en: "Track") }
    public static var name: String { pick(cs: "Název", en: "Name") }
    public static var path: String { pick(cs: "Cesta", en: "Path") }
    public static var choose: String { pick(cs: "Vybrat…", en: "Choose…") }
    public static var add: String { pick(cs: "Přidat", en: "Add") }
    public static var addProjectHint: String { pick(cs: "Nově přidaný projekt se rovnou sleduje pomocí Claude Code hooků. Zaškrtnutí „Sledovat\u{201C} zapíná/vypíná sledování pro existující projekty.", en: "A newly added project is tracked by Claude Code hooks right away. Checking \u{201C}Track\u{201D} turns tracking on/off for existing projects.") }
    public static var gitImportMovedHint: String { pick(cs: "Import z gitu najdeš v okně Týden.", en: "Import from git now lives in the Week window.") }
    public static var exportCSV: String { pick(cs: "Export CSV", en: "Export CSV") }
    public static var exportJSON: String { pick(cs: "Export JSON", en: "Export JSON") }
    public static func addProjectFailed(_ message: String) -> String { pick(cs: "Nepodařilo se přidat projekt: \(message)", en: "Failed to add project: \(message)") }
    public static func trackToggleFailed(_ message: String) -> String { pick(cs: "Nepodařilo se změnit sledování: \(message)", en: "Failed to change tracking: \(message)") }
    public static func exportFailed(_ message: String) -> String { pick(cs: "Export selhal: \(message)", en: "Export failed: \(message)") }
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
    public static var deleteBlockConfirmTitle: String { pick(cs: "Smazat záznam?", en: "Delete this entry?") }
    public static var deleteBlockConfirmMessage: String { pick(cs: "Tuto akci lze vzít zpět tlačítkem Zpět.", en: "You can undo this with the Undo button.") }
    public static var actionMove: String { pick(cs: "Přesun", en: "Move") }
    public static var actionDelete: String { pick(cs: "Smazání", en: "Delete") }

    // MARK: - Git import review sheet

    public static var importFromGit: String { pick(cs: "Import z gitu…", en: "Import from git…") }
    public static var importFromGitHelp: String { pick(cs: "Projde commity za zobrazený týden a necháš tě je před uložením zkontrolovat.", en: "Walks through commits for the shown week and lets you review them before saving.") }
    public static var gitImportSheetTitle: String { pick(cs: "Import z gitu", en: "Import from git") }
    public static var gitImportProjectLabel: String { pick(cs: "Projekt", en: "Project") }
    public static var gitImportLoading: String { pick(cs: "Načítám commity…", en: "Loading commits…") }
    public static func gitImportFailed(_ message: String) -> String { pick(cs: "Nepodařilo se načíst commity: \(message)", en: "Failed to load commits: \(message)") }
    public static var gitImportNoCommits: String { pick(cs: "Žádné commity tohoto autora v tomto týdnu.", en: "No commits by you in this week.") }
    public static var gitImportReplaceExisting: String { pick(cs: "Nahradit dříve importované bloky za tento týden", en: "Replace previously imported blocks for this week") }
    public static var gitImportDiscard: String { pick(cs: "Zahodit", en: "Discard") }
    public static var gitImportInclude: String { pick(cs: "Zahrnout", en: "Include") }
    public static func gitImportCandidateCount(_ count: Int) -> String { pick(cs: "\(count) záznamů k importu", en: "\(count) entries to import") }
    public static var gitImportCommit: String { pick(cs: "Importovat", en: "Import") }
    public static func gitImportSuccess(_ count: Int) -> String { pick(cs: "Naimportováno \(count) záznamů.", en: "Imported \(count) entries.") }

    // MARK: - Finish day/week flow

    public static var finishDay: String { pick(cs: "Doplň den…", en: "Fill day…") }
    public static var finishDayHelp: String { pick(cs: "Projde návrhy, jak doplnit den do cílových hodin.", en: "Walks through suggestions to fill the day up to target hours.") }
    public static var finishWeek: String { pick(cs: "Doplň týden…", en: "Fill week…") }
    public static var finishWeekHelp: String { pick(cs: "Projde dny v týdnu, které ještě nedosáhly cíle.", en: "Walks through the week's days that haven't hit target yet.") }
    public static func finishDayHeader(logged: String, target: String) -> String { pick(cs: "Odpracováno \(logged) z \(target)", en: "Logged \(logged) of \(target)") }
    public static func finishDayRemaining(_ remaining: String) -> String { pick(cs: "Zbývá \(remaining)", en: "\(remaining) remaining") }
    public static var finishDayComplete: String { pick(cs: "Den je hotový.", en: "Day is complete.") }
    public static var finishDayNoMoreSuggestions: String { pick(cs: "Žádné další návrhy — doplň zbytek ručně.", en: "No more suggestions — fill the rest manually.") }
    public static var finishDaySuggestionGitCommit: String { pick(cs: "Nezalogovaný commit", en: "Unlogged commit") }
    public static func finishDaySuggestionProlong(_ project: String) -> String { pick(cs: "Prodloužit poslední záznam (\(project))", en: "Prolong last entry (\(project))") }
    public static var finishDaySuggestionManual: String { pick(cs: "Ruční záznam", en: "Manual entry") }
    public static var finishDaySkip: String { pick(cs: "Přeskočit", en: "Skip") }
    public static var finishDayAddAndNext: String { pick(cs: "Přidat a další", en: "Add & next") }
    public static var finishDayDone: String { pick(cs: "Hotovo", en: "Done") }
    public static var finishWeekSkipDay: String { pick(cs: "Přeskočit den", en: "Skip day") }
    public static var finishWeekBack: String { pick(cs: "Zpět", en: "Back") }
    public static var finishWeekNextDay: String { pick(cs: "Další den", en: "Next day") }
    public static var finishWeekAllCaughtUp: String { pick(cs: "Všechny dny jsou na cíli.", en: "All days are at target.") }
    public static var finishWeekTitle: String { pick(cs: "Doplň týden", en: "Fill week") }

    // MARK: - Trask pairing (Settings)

    public static var traskSectionTitle: String { pick(cs: "Trask", en: "Trask") }
    public static var traskProjectLabel: String { pick(cs: "Trask projekt", en: "Trask project") }
    public static var traskDefaultTaskLabel: String { pick(cs: "Výchozí úkol", en: "Default task") }
    public static var traskNoPairing: String { pick(cs: "Nespárováno", en: "Not paired") }
    public static var traskRefreshCatalog: String { pick(cs: "Obnovit katalog Trask…", en: "Refresh Trask catalog…") }
    public static var traskRefreshing: String { pick(cs: "Načítám z Trask…", en: "Refreshing from Trask…") }
    public static func traskRefreshFailed(_ message: String) -> String { pick(cs: "Obnovení selhalo: \(message)", en: "Refresh failed: \(message)") }
    public static func traskRefreshSummary(newProjects: Int, newTasks: Int, deactivated: Int) -> String {
        pick(
            cs: "Nové projekty: \(newProjects), nové úkoly: \(newTasks), deaktivováno: \(deactivated)",
            en: "New projects: \(newProjects), new tasks: \(newTasks), deactivated: \(deactivated)"
        )
    }
    public static var traskPairingStaleProject: String { pick(cs: "Trask projekt už neexistuje — přeparuj prosím.", en: "Trask project no longer exists — please re-pair.") }
    public static var traskPairingStaleTask: String { pick(cs: "Výchozí úkol už neexistuje — přeparuj prosím.", en: "Default task no longer exists — please re-pair.") }

    // MARK: - Trask upload flow

    public static var uploadDay: String { pick(cs: "Nahrát den…", en: "Upload day…") }
    public static var uploadWeek: String { pick(cs: "Nahrát týden…", en: "Upload week…") }
    public static var uploadNeedsRepairing: String { pick(cs: "Tyto projekty je potřeba přeparovat s Trask, než bude možné nahrát čas:", en: "These projects need re-pairing with Trask before time can be uploaded:") }
    public static var uploadOpenSettings: String { pick(cs: "Otevřít nastavení", en: "Open Settings") }
    public static func uploadEntryProgress(current: Int, total: Int) -> String { pick(cs: "Záznam \(current) z \(total)", en: "Entry \(current) of \(total)") }
    public static var uploadEntryFilled: String { pick(cs: "Vyplněno — zkontroluj okno Chrome, klikni tam na Uložit, pak pokračuj.", en: "Filled — check the Chrome window, click Save there, then continue.") }
    public static var uploadNext: String { pick(cs: "Další", en: "Next") }
    public static var uploadSkipEntry: String { pick(cs: "Přeskočit záznam", en: "Skip entry") }
    public static var uploadCancel: String { pick(cs: "Zrušit nahrávání", en: "Cancel upload") }
    public static func uploadFillFailed(_ message: String) -> String { pick(cs: "Vyplnění selhalo: \(message)", en: "Filling failed: \(message)") }
    public static var uploadComplete: String { pick(cs: "Nahrávání dokončeno.", en: "Upload complete.") }

    // MARK: - 1Password login autofill (Settings)

    public static var onePasswordUseForLogin: String { pick(cs: "Použít 1Password pro přihlášení do Trask", en: "Use 1Password to fill Trask login") }
    public static var onePasswordChooseItem: String { pick(cs: "Vybrat položku 1Password pro přihlášení…", en: "Choose 1Password item for Trask login…") }
    public static func onePasswordSelectedItem(_ title: String) -> String { pick(cs: "Vybráno: \(title)", en: "Selected: \(title)") }
    public static var onePasswordNoneSelected: String { pick(cs: "Zatím nevybráno", en: "Not yet chosen") }
    public static var onePasswordPickerTitle: String { pick(cs: "Vybrat položku 1Password", en: "Choose 1Password item") }
    public static var onePasswordPickerSearch: String { pick(cs: "Hledat…", en: "Search…") }
    public static var uploadAwaiting2FA: String { pick(cs: "Vyplněno uživatelské jméno a heslo — dokonči prosím dvoufázové ověření v okně Chrome, pak zkus znovu.", en: "Username/password filled — please complete 2FA in the Chrome window, then try again.") }
    public static var uploadLoginRequired: String { pick(cs: "Přihlas se prosím do Trask v okně Chrome, nebo zapni automatické vyplnění pomocí 1Password v Nastavení.", en: "Please log into Trask in the Chrome window, or enable 1Password autofill in Settings.") }
    public static func uploadEnsureReadyFailed(_ message: String) -> String { pick(cs: "Příprava nahrávání selhala: \(message)", en: "Preparing the upload failed: \(message)") }

    // MARK: - Widget

    public static func widgetProjectLine(project: String, hours: String) -> String { "\(project): \(hours)" }
    public static var widgetTodaySuffix: String { pick(cs: "dnes", en: "today") }
    public static var widgetDisplayName: String { "Vaire" }
    public static var widgetDescription: String { pick(cs: "Dnešní odpracovaný čas.", en: "Today's worked time.") }
}
