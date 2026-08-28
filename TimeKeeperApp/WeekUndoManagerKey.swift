import SwiftUI

private struct WeekUndoManagerKey: EnvironmentKey {
    static let defaultValue: UndoManager? = nil
}

extension EnvironmentValues {
    var weekUndoManager: UndoManager? {
        get { self[WeekUndoManagerKey.self] }
        set { self[WeekUndoManagerKey.self] = newValue }
    }
}
