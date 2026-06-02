package org.typecarrier.android.domain

class TextEditHistory(limit: Int = 100) {
    private val undoStack = ArrayDeque<String>()
    private val redoStack = ArrayDeque<String>()
    private val limit = limit.coerceAtLeast(1)

    val canUndo: Boolean
        get() = undoStack.isNotEmpty()

    val canRedo: Boolean
        get() = redoStack.isNotEmpty()

    fun recordChange(from: String, to: String) {
        if (from == to) {
            return
        }

        undoStack.addLast(from)
        while (undoStack.size > limit) {
            undoStack.removeFirst()
        }
        redoStack.clear()
    }

    fun undo(current: String): String? {
        val previous = undoStack.removeLastOrNull() ?: return null
        redoStack.addLast(current)
        return previous
    }

    fun redo(current: String): String? {
        val next = redoStack.removeLastOrNull() ?: return null
        undoStack.addLast(current)
        return next
    }

    fun reset() {
        undoStack.clear()
        redoStack.clear()
    }
}
