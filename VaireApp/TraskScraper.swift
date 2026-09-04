import Foundation
import VaireKit

enum TraskScraperError: Error, LocalizedError {
    case scriptNotFound(String)
    case processFailed(exitCode: Int32, stderr: String)
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case .scriptNotFound(let path):
            return "VaireUpload script not found at \(path)."
        case .processFailed(_, let stderr):
            return stderr.isEmpty ? "The Trask automation script failed." : stderr
        case .malformedOutput:
            return "The Trask automation script returned unexpected output."
        }
    }
}

/// Shells out to VaireUpload's Node/Playwright scripts, the same pattern
/// GitImporter uses for `/usr/bin/git`. VaireUpload is a plain Node project
/// (not part of the Swift package or app bundle) because it drives a real
/// Chrome window over CDP — see VaireUpload/README.md for why. Lives in the
/// app target rather than VaireKit because locating the script on disk is
/// dev-repo-relative for now; this is the seam to revisit if VaireUpload
/// ever needs to ship inside the app bundle for other machines.
enum TraskScraper {
    /// Directory containing package.json/src for VaireUpload, resolved
    /// relative to this source file's location in the repo. Works for a
    /// locally-built/run app; would need revisiting for a distributed build
    /// (see VaireUpload/README.md).
    private static var vaireUploadDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VaireApp/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("VaireUpload")
    }

    /// Runs `scrapeCatalog.mjs` and parses its JSON into scraped-project
    /// structs. Throws with the script's own stderr message on failure —
    /// those messages are already written to be user-facing (e.g. "log in
    /// first", "no tab found").
    static func scrapeCatalog() async throws -> [TraskScrapedProject] {
        let scriptPath = vaireUploadDirectory.appendingPathComponent("src/scrapeCatalog.mjs").path
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw TraskScraperError.scriptNotFound(scriptPath)
        }

        let output = try await runNode(scriptPath: scriptPath, arguments: [])
        return try parseCatalog(json: output)
    }

    /// Checks whether something is listening on the CDP debug port before
    /// starting an upload, so a missing/closed debug Chrome surfaces as one
    /// clear message up front instead of looking like a per-entry fill
    /// failure once the first `fillEntry` call fails deep inside Playwright.
    /// Superseded by `ensureReady()` for the actual upload flow — this
    /// remains as a fast read-only check other call sites can use without
    /// triggering a Chrome launch.
    static func isDebugChromeReachable() async -> Bool {
        guard let url = URL(string: "http://localhost:9222/json/version") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    enum ReadyStatus: String {
        case ready
        case awaitingTwoFactor = "awaiting-2fa"
        case loginRequired = "login-required"
    }

    /// Launches the debug Chrome profile if needed, gets a my.trask.cz tab,
    /// and (if 1Password autofill is enabled and an item is chosen)
    /// attempts to log in — never attempts to clear 2FA itself. This is
    /// what `UploadFlowView` calls before the first `fillEntry`, replacing
    /// the old "tell the user to launch Chrome themselves" message with an
    /// automatic launch plus a specific status for whatever's still
    /// blocking (2FA, or login disabled/unpaired).
    static func ensureReady() async throws -> ReadyStatus {
        let scriptPath = vaireUploadDirectory.appendingPathComponent("src/ensureReady.mjs").path
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw TraskScraperError.scriptNotFound(scriptPath)
        }

        let setting = OnePasswordSetting.current()
        let arguments = (setting.isEnabled ? setting.itemId : nil).map { [$0] } ?? []

        let output = try await runNode(scriptPath: scriptPath, arguments: arguments)
        guard let data = output.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data),
              let statusRaw = decoded["status"],
              let status = ReadyStatus(rawValue: statusRaw) else {
            throw TraskScraperError.malformedOutput
        }
        return status
    }

    /// One already-logged Trask entry, as read by `checkExistingEntries()`.
    /// `note` is the entry's free-text description as Trask's calendar
    /// view shows it, NOT its task category — confirmed live that view
    /// never exposes the task category at all, only "Project | Note".
    struct ExistingEntry: Equatable {
        let projectLabel: String
        let note: String
    }

    /// Runs `checkExistingEntries.mjs` ONCE, reading every already-logged
    /// entry for the currently-visible week in a single pass — the caller
    /// (`UploadFlowView`) uses this up front to skip duplicate fills
    /// locally, rather than each `fillEntry` call re-checking Trask (and
    /// reloading the page) before every single fill, which an earlier
    /// version did and which didn't reliably prevent duplicates in
    /// practice. A date not present as a key in the result wasn't in the
    /// currently-visible week — callers get no dedup guarantee for it.
    static func checkExistingEntries() async throws -> [String: [ExistingEntry]] {
        let scriptPath = vaireUploadDirectory.appendingPathComponent("src/checkExistingEntries.mjs").path
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw TraskScraperError.scriptNotFound(scriptPath)
        }

        let output = try await runNode(scriptPath: scriptPath, arguments: [])
        guard let data = output.data(using: .utf8) else {
            throw TraskScraperError.malformedOutput
        }
        struct RawEntry: Decodable { let projectLabel: String; let note: String }
        let decoded = try JSONDecoder().decode([String: [RawEntry]].self, from: data)
        return decoded.mapValues { entries in
            entries.map { ExistingEntry(projectLabel: $0.projectLabel, note: $0.note) }
        }
    }

    /// Runs `fillEntry.mjs` with the given entry JSON. Fully automatic —
    /// the script fills the form, clicks Save, and confirms Trask
    /// accepted it before returning.
    static func fillEntry(entryJSON: String) async throws {
        let scriptPath = vaireUploadDirectory.appendingPathComponent("src/fillEntry.mjs").path
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw TraskScraperError.scriptNotFound(scriptPath)
        }

        let output = try await runNode(scriptPath: scriptPath, arguments: [entryJSON])
        guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "ready" else {
            throw TraskScraperError.malformedOutput
        }
    }

    private static func runNode(scriptPath: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let quotedArguments = ([scriptPath] + arguments).map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            process.arguments = ["-l", "-c", "node " + quotedArguments.joined(separator: " ")]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let stdoutData = ThreadSafeBox(Data())
            let stderrData = ThreadSafeBox(Data())

            stdout.fileHandleForReading.readabilityHandler = { handle in
                stdoutData.append(handle.availableData)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                stderrData.append(handle.availableData)
            }

            process.terminationHandler = { proc in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                let stdoutString = String(data: stdoutData.value, encoding: .utf8) ?? ""
                let stderrString = String(data: stderrData.value, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdoutString)
                } else {
                    continuation.resume(throwing: TraskScraperError.processFailed(
                        exitCode: proc.terminationStatus,
                        stderr: stderrString
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private struct ScrapedProjectJSON: Decodable {
        let tasks: [String]
    }

    private static func parseCatalog(json: String) throws -> [TraskScrapedProject] {
        guard let data = json.data(using: .utf8) else {
            throw TraskScraperError.malformedOutput
        }
        let decoded = try JSONDecoder().decode([String: ScrapedProjectJSON].self, from: data)
        return decoded.map { label, value in
            TraskScrapedProject(label: label, taskLabels: value.tasks)
        }
    }
}
