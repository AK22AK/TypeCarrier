public struct TextEditHistory: Sendable {
    private var undoStack: [String]
    private var redoStack: [String]
    private let limit: Int

    public init(limit: Int = 100) {
        self.undoStack = []
        self.redoStack = []
        self.limit = max(1, limit)
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public mutating func recordChange(from oldValue: String, to newValue: String) {
        guard oldValue != newValue else {
            return
        }

        undoStack.append(oldValue)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    public mutating func undo(current: String) -> String? {
        guard let previous = undoStack.popLast() else {
            return nil
        }

        redoStack.append(current)
        return previous
    }

    public mutating func redo(current: String) -> String? {
        guard let next = redoStack.popLast() else {
            return nil
        }

        undoStack.append(current)
        return next
    }

    public mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
