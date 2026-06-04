package org.typecarrier.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TextEditHistoryTest {
    @Test
    fun undoAndRedoFollowTextChanges() {
        val history = TextEditHistory()

        history.recordChange("", "a")
        history.recordChange("a", "ab")

        assertTrue(history.canUndo)
        assertEquals("a", history.undo(current = "ab"))
        assertTrue(history.canRedo)
        assertEquals("ab", history.redo(current = "a"))
    }

    @Test
    fun newChangeClearsRedoStack() {
        val history = TextEditHistory()
        history.recordChange("", "a")
        assertEquals("", history.undo(current = "a"))

        history.recordChange("", "b")

        assertFalse(history.canRedo)
        assertNull(history.redo(current = "b"))
    }

    @Test
    fun limitKeepsMostRecentUndoEntries() {
        val history = TextEditHistory(limit = 2)

        history.recordChange("", "a")
        history.recordChange("a", "ab")
        history.recordChange("ab", "abc")

        assertEquals("ab", history.undo(current = "abc"))
        assertEquals("a", history.undo(current = "ab"))
        assertNull(history.undo(current = "a"))
    }
}
