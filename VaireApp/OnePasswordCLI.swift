import Foundation

enum OnePasswordCLIError: Error, LocalizedError {
    case notInstalled
    case processFailed(stderr: String)
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The 1Password CLI (op) is not installed. Install it with: brew install --cask 1password-cli, then enable \"Integrate with 1Password CLI\" in 1Password.app > Settings > Developer."
        case .processFailed(let stderr):
            return stderr.isEmpty ? "The 1Password CLI failed." : stderr
        case .malformedOutput:
            return "The 1Password CLI returned unexpected output."
        }
    }
}

struct OnePasswordItem: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Thin `Process` wrapper around the `op` CLI, same shell-out pattern as
/// `GitImporter`/`TimesheetScraper`. Only ever lists item titles for the
/// Settings picker — never fetches or handles a secret value; that only
/// happens on the VaireUpload/Node side (`loginIfNeeded.mjs`), gated by the
/// same biometric per-call prompt either way.
enum OnePasswordCLI {
    static func listItems() async throws -> [OnePasswordItem] {
        let output = try await run(arguments: ["item", "list", "--format", "json"])
        guard let data = output.data(using: .utf8) else {
            throw OnePasswordCLIError.malformedOutput
        }

        struct RawItem: Decodable {
            let id: String
            let title: String
        }
        let items = try JSONDecoder().decode([RawItem].self, from: data)
        return items.map { OnePasswordItem(id: $0.id, title: $0.title) }
    }

    private static func run(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let quotedArguments = arguments.map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            process.arguments = ["-l", "-c", "op " + quotedArguments.joined(separator: " ")]

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
                    continuation.resume(throwing: OnePasswordCLIError.processFailed(stderr: stderrString))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: OnePasswordCLIError.notInstalled)
            }
        }
    }
}
