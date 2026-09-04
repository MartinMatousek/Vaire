import Foundation

/// Accumulates `Data` written from a `Pipe`'s `readabilityHandler`, which
/// fires on a background queue — reading `Process` output this way (rather
/// than `readDataToEndOfFile()` after `terminationHandler`) avoids the
/// classic deadlock where output larger than the pipe's buffer blocks the
/// child process on write while nothing is draining the pipe yet.
final class ThreadSafeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data

    init(_ data: Data) {
        self.data = data
    }

    func append(_ newData: Data) {
        lock.withLock { data.append(newData) }
    }

    var value: Data {
        lock.withLock { data }
    }
}
