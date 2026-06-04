package org.typecarrier.android.diagnostics

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AndroidDiagnosticLogStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun exportFileCreatesShareableJsonlCopy() {
        val source = temporaryFolder.newFile("events.jsonl").also(File::delete)
        val exportDir = temporaryFolder.newFolder("exports")
        val store = AndroidDiagnosticLogStore(file = source)

        store.append("connection.failed", "timeout")

        val exported = store.exportFile(exportDir)

        assertTrue(exported.name.startsWith("typecarrier-android-diagnostics-"))
        assertTrue(exported.name.endsWith(".jsonl"))
        assertEquals(store.exportText(), exported.readText())
    }
}
