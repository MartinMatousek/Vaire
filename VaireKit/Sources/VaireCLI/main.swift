import Foundation
import VaireKit

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
        throw CLIError.usage("usage: vaire <start-session|stop-session|is-tracking|delete-block> ...")
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
    case "find-active":
        try runFindActive(db: db, args: rest)
    case "continue-session":
        try runContinueSession(db: db, args: rest)
    case "set-estimate":
        try runSetEstimate(db: db, args: rest)
    case "has-estimate":
        try runHasEstimate(db: db, args: rest)
    case "adjust-estimate":
        try runAdjustEstimate(db: db, args: rest)
    case "delete-block":
        try runDeleteBlock(db: db, args: rest)
    case "is-hooks-enabled":
        try runIsHooksEnabled(db: db, args: rest)
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
    DataChangeNotifier.post()
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
    if let estimate = result.block.estimatedHoursWithoutAI {
        print("estimated_hours_without_ai=\(estimate)")
    }
    DataChangeNotifier.post()
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
    DataChangeNotifier.post()
}

func runFindActive(db: AppDatabase, args: [String]) throws {
    guard let cwd = args.first else {
        throw CLIError.usage("usage: find-active <cwd>")
    }
    guard let tracking = try AgentSessionRecorder.findActiveTracking(db: db, cwd: cwd) else {
        print("none")
        return
    }
    let elapsedSeconds = Int(Date().timeIntervalSince(tracking.start))
    print("session_id=\(tracking.sessionId)")
    print("note=\(tracking.note ?? "")")
    print("elapsed_seconds=\(elapsedSeconds)")
}

func runContinueSession(db: AppDatabase, args: [String]) throws {
    guard args.count >= 2 else {
        throw CLIError.usage("usage: continue-session <old_session_id> <new_session_id>")
    }
    try AgentSessionRecorder.continueTracking(db: db, oldSessionId: args[0], newSessionId: args[1])
    print("continued")
    DataChangeNotifier.post()
}

func runSetEstimate(db: AppDatabase, args: [String]) throws {
    guard args.count >= 2, let hours = Double(args[1]) else {
        throw CLIError.usage("usage: set-estimate <session_id> <hours>")
    }
    guard try AgentSessionRecorder.isTracking(db: db, sessionId: args[0]) else {
        print("not-tracking")
        return
    }
    try AgentSessionRecorder.setEstimate(db: db, sessionId: args[0], hours: hours)
    print("estimate set")
}

func runHasEstimate(db: AppDatabase, args: [String]) throws {
    guard let sessionId = args.first else {
        throw CLIError.usage("usage: has-estimate <session_id>")
    }
    print(try AgentSessionRecorder.hasEstimate(db: db, sessionId: sessionId) ? "true" : "false")
}

func runAdjustEstimate(db: AppDatabase, args: [String]) throws {
    guard args.count >= 1, let blockId = UUID(uuidString: args[0]) else {
        throw CLIError.usage("usage: adjust-estimate <block_id> [hours]")
    }
    let hours = args.count >= 2 ? Double(args[1]) : nil
    _ = try BlockEditor.setEstimate(db: db, blockId: blockId, hours: hours)
    print("estimate adjusted")
    DataChangeNotifier.post()
}

func runIsHooksEnabled(db: AppDatabase, args: [String]) throws {
    guard let cwd = args.first else {
        throw CLIError.usage("usage: is-hooks-enabled <cwd>")
    }
    print(try Project.hooksEnabled(forPath: cwd, db: db) ? "true" : "false")
}

func runDeleteBlock(db: AppDatabase, args: [String]) throws {
    guard let blockId = args.first.flatMap(UUID.init) else {
        throw CLIError.usage("usage: delete-block <block_id>")
    }
    try BlockEditor.delete(db: db, blockId: blockId)
    print("deleted")
    DataChangeNotifier.post()
}

do {
    try run()
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
