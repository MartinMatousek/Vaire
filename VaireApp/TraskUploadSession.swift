import Foundation
import VaireKit

/// Owns one long-lived `node src/session.mjs` process for the whole
/// duration of an upload (`UploadFlowView`), replacing the old pattern of
/// spawning a fresh node+Playwright process — with a fresh CDP connect —
/// for every single `ensureReady`/`checkExistingEntries`/`fillEntry` call.
/// That per-call spawn was the source of a long pause after every logged
/// entry during upload; this reuses one process and one Playwright
/// `browser`/`page` handle across the whole batch instead.
///
/// An actor because it owns mutable state (the process, its pipes, and the
/// map of in-flight requests) touched from multiple `Task`s in
/// `UploadFlowView` (the initial `ensureReady` call, then one `fillEntry`
/// call per block as the user advances/retries).
actor TraskUploadSession {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextId = 0
    private var stdoutBuffer = Data()
    private var stderrBox = ThreadSafeBox(Data())

    private static let requestTimeoutNanoseconds: UInt64 = 45_000_000_000 // 45s, above attach.mjs's own internal timeout ceiling (15s)

    /// Starts the session process if not already started, and performs the
    /// first `ensureReady` login check — mirrors what `TraskScraper.ensureReady()`
    /// did per-call, but now runs against a process that stays alive for
    /// every subsequent call this session makes.
    func start(onePasswordItemId: String?) async throws -> TraskScraper.ReadyStatus {
        if process == nil {
            try launchProcess()
        }
        let args: [String: Any] = onePasswordItemId.map { ["onePasswordItemId": $0] } ?? [:]
        let result = try await send(op: "ensureReady", args: args)
        guard let statusRaw = result["status"] as? String,
              let status = TraskScraper.ReadyStatus(rawValue: statusRaw) else {
            throw TraskScraperError.malformedOutput
        }
        return status
    }

    func checkExistingEntries() async throws -> [String: [TraskScraper.ExistingEntry]] {
        let result = try await send(op: "checkExistingEntries", args: [:])
        var byDate: [String: [TraskScraper.ExistingEntry]] = [:]
        for (date, rawEntries) in result {
            guard let rawEntries = rawEntries as? [[String: Any]] else { continue }
            byDate[date] = rawEntries.compactMap { raw in
                guard let projectLabel = raw["projectLabel"] as? String,
                      let note = raw["note"] as? String else { return nil }
                return TraskScraper.ExistingEntry(projectLabel: projectLabel, note: note)
            }
        }
        return byDate
    }

    func fillEntry(payload: [String: Any]) async throws {
        _ = try await send(op: "fillEntry", args: payload)
    }

    /// Idempotent: safe to call multiple times (e.g. an explicit Cancel
    /// button racing with `.onDisappear`) and safe to call before `start()`
    /// ever ran (a no-op in that case).
    func stop() {
        guard let process, process.isRunning else {
            self.process = nil
            failAllPending(with: TraskScraperError.processFailed(exitCode: -1, stderr: "Upload session stopped."))
            return
        }
        // Best-effort graceful shutdown; terminate() below is the backstop
        // regardless of whether the process acknowledges it in time.
        try? stdinHandle?.write(contentsOf: Data("{\"id\":\"shutdown\",\"op\":\"shutdown\",\"args\":{}}\n".utf8))
        process.terminate()
        self.process = nil
        self.stdinHandle = nil
        failAllPending(with: TraskScraperError.processFailed(exitCode: -1, stderr: "Upload session stopped."))
    }

    private func failAllPending(with error: Error) {
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
    }

    private func send(op: String, args: [String: Any]) async throws -> [String: Any] {
        guard let stdinHandle else {
            throw TraskScraperError.malformedOutput
        }
        let id = String(nextId)
        nextId += 1

        let request: [String: Any] = ["id": id, "op": op, "args": args]
        let data = try JSONSerialization.data(withJSONObject: request)

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.requestTimeoutNanoseconds)
            await self?.timeoutRequest(id: id)
        }

        do {
            let result = try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                do {
                    try stdinHandle.write(contentsOf: data)
                    try stdinHandle.write(contentsOf: Data("\n".utf8))
                } catch {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
            timeoutTask.cancel()
            return result
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }

    private func timeoutRequest(id: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: TraskScraperError.processFailed(
            exitCode: -1,
            stderr: "The Trask automation script did not respond in time."
        ))
    }

    private func launchProcess() throws {
        let scriptPath = TraskScraper.vaireUploadDirectory.appendingPathComponent("src/session.mjs").path
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw TraskScraperError.scriptNotFound(scriptPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let quotedScriptPath = "'\(scriptPath.replacingOccurrences(of: "'", with: "'\\''"))'"
        process.arguments = ["-l", "-c", "node " + quotedScriptPath]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.handleStdout(data) }
        }
        let stderrBox = self.stderrBox
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBox.append(handle.availableData)
        }

        process.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let stderrString = String(data: stderrBox.value, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task {
                await self?.handleProcessExit(exitCode: proc.terminationStatus, stderr: stderrString)
            }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
    }

    private func handleProcessExit(exitCode: Int32, stderr: String) {
        process = nil
        stdinHandle = nil
        failAllPending(with: TraskScraperError.processFailed(exitCode: exitCode, stderr: stderr))
    }

    private func handleStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[..<newlineIndex]
            stdoutBuffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else { continue }
            handleLine(Data(lineData))
        }
    }

    private func handleLine(_ lineData: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let id = json["id"] as? String,
              let continuation = pending.removeValue(forKey: id) else {
            return // stray/malformed line — ignore per protocol contract
        }

        let ok = json["ok"] as? Bool ?? false
        if ok {
            continuation.resume(returning: (json["result"] as? [String: Any]) ?? [:])
        } else {
            let message = json["error"] as? String ?? "The Trask automation script returned an error with no message."
            continuation.resume(throwing: TraskScraperError.processFailed(exitCode: 1, stderr: message))
        }
    }
}
