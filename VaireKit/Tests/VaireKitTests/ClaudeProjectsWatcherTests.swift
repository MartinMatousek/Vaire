import Foundation
import Testing
@testable import VaireKit

@Test func detectsChangesToJSONLFilesInWatchedDirectory() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let detectedPath = SendableBox<String?>(nil)
    let watcher = ClaudeProjectsWatcher(debounceInterval: 0.1) { path in
        detectedPath.value = path
    }
    watcher.start(watching: dir.path)
    defer { watcher.stop() }

    // Give FSEvents a moment to register the watch before we write.
    try await Task.sleep(nanoseconds: 300_000_000)

    let fileURL = dir.appendingPathComponent("session.jsonl")
    try #"{"type":"user","timestamp":"2026-08-21T08:00:00Z"}"#.write(to: fileURL, atomically: true, encoding: .utf8)

    // FSEvents delivery + debounce can take a bit; poll instead of a single sleep.
    for _ in 0..<20 {
        if detectedPath.value != nil { break }
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    #expect(detectedPath.value?.hasSuffix("session.jsonl") == true)
}

private final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
