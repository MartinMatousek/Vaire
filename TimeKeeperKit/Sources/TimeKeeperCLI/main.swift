import Foundation
import TimeKeeperKit

enum CLIError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message): return message
        }
    }
}

func run() throws {
    let arguments = CommandLine.arguments.dropFirst()
    guard let command = arguments.first else {
        throw CLIError.usage("usage: timekeeper-cli <start-session|stop-session|is-tracking> ...")
    }

    let db = try AppDatabase(path: SharedStorage.databasePath())
    let rest = Array(arguments.dropFirst())

    switch command {
    case "start-session":
        try runStartSession(db: db, args: rest)
    case "stop-session":
        try runStopSession(db: db, args: rest)
    case "is-tracking":
        try runIsTracking(db: db, args: rest)
    case "adjust-block":
        try runAdjustBlock(db: db, args: rest)
    default:
        throw CLIError.usage("unknown command: \(command)")
    }
}

func runStartSession(db: AppDatabase, args: [String]) throws {
    guard args.count >= 2 else {
        throw CLIError.usage("usage: start-session <session_id> <cwd> [note]")
    }
    let sessionId = args[0]
    let cwd = args[1]
    let note = args.count > 2 ? args[2] : nil

    let project = try AgentSessionRecorder.start(db: db, sessionId: sessionId, cwd: cwd, note: note)
    print("started tracking session \(sessionId) on project \(project.name)")
}

func runStopSession(db: AppDatabase, args: [String]) throws {
    guard let sessionId = args.first else {
        throw CLIError.usage("usage: stop-session <session_id>")
    }

    guard let result = try AgentSessionRecorder.stop(db: db, sessionId: sessionId) else {
        print("not-tracking")
        return
    }

    let hours = result.block.duration / 3600
    let h = Int(hours)
    let m = Int((hours - Double(h)) * 60)
    print("project=\(result.project.name)")
    print("duration_seconds=\(Int(result.block.duration))")
    print("duration_human=\(h)h \(m)m")
    print("note=\(result.block.note ?? "")")
    print("block_id=\(result.block.id.uuidString)")
}

func runIsTracking(db: AppDatabase, args: [String]) throws {
    guard let sessionId = args.first else {
        throw CLIError.usage("usage: is-tracking <session_id>")
    }
    print(try AgentSessionRecorder.isTracking(db: db, sessionId: sessionId) ? "true" : "false")
}

func runAdjustBlock(db: AppDatabase, args: [String]) throws {
    guard args.count >= 1, let blockId = UUID(uuidString: args[0]) else {
        throw CLIError.usage("usage: adjust-block <block_id> [minutes] [note]")
    }

    let existing = try db.dbQueue.read { conn in
        try Block.fetchOne(conn, key: blockId)
    }
    guard let existing else {
        throw CLIError.usage("block not found: \(args[0])")
    }

    if args.count >= 2, let minutes = Double(args[1]) {
        let newEnd = existing.start.addingTimeInterval(minutes * 60)
        _ = try BlockEditor.setTimes(db: db, blockId: blockId, start: existing.start, end: newEnd)
    }

    if args.count >= 3 {
        _ = try BlockEditor.setNote(db: db, blockId: blockId, note: args[2])
    }

    print("adjusted")
}

do {
    try run()
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
