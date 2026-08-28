import Foundation
import CoreServices

/// Watches `~/.claude/projects/` for changes to session JSONL files and
/// invokes a callback with the changed file's path, debounced so a burst of
/// writes to the same session (every turn appends a line) triggers one
/// reimport instead of dozens.
public final class ClaudeProjectsWatcher {
    private var stream: FSEventStreamRef?
    private let callback: (String) -> Void
    private let debounceInterval: TimeInterval
    private var pendingPaths: Set<String> = []
    private var debounceTimer: Timer?

    public init(debounceInterval: TimeInterval = 5.0, callback: @escaping (String) -> Void) {
        self.callback = callback
        self.debounceInterval = debounceInterval
    }

    public func start(watching directory: String) {
        stop()

        let context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callbackTrampoline: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let clientCallBackInfo else { return }
            let watcher = Unmanaged<ClaudeProjectsWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

            let cPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            var paths: [String] = []
            paths.reserveCapacity(numEvents)
            for i in 0..<numEvents {
                paths.append(String(cString: cPaths[i]))
            }
            watcher.handleEvents(paths: paths)
        }

        var contextCopy = context
        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callbackTrampoline,
            &contextCopy,
            [directory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.main)
        FSEventStreamStart(newStream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    private func handleEvents(paths: [String]) {
        for path in paths where path.hasSuffix(".jsonl") {
            pendingPaths.insert(path)
        }
        guard !pendingPaths.isEmpty else { return }

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            let paths = self.pendingPaths
            self.pendingPaths.removeAll()
            for path in paths {
                self.callback(path)
            }
        }
    }

    deinit {
        stop()
    }
}
