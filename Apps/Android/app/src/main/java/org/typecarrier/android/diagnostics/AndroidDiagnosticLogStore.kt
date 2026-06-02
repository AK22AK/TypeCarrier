package org.typecarrier.android.diagnostics

import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class AndroidDiagnosticEvent(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: String = Instant.now().toString(),
    val name: String,
    val message: String,
)

class AndroidDiagnosticLogStore(
    private val file: File,
) {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }

    fun append(name: String, message: String) {
        file.parentFile?.mkdirs()
        file.appendText(json.encodeToString(AndroidDiagnosticEvent(name = name, message = message)) + "\n")
    }

    fun recent(limit: Int = 20): List<AndroidDiagnosticEvent> {
        if (!file.exists()) {
            return emptyList()
        }

        return file.readLines()
            .asReversed()
            .mapNotNull { line ->
                runCatching { json.decodeFromString<AndroidDiagnosticEvent>(line) }.getOrNull()
            }
            .take(limit)
    }

    fun exportText(): String {
        if (!file.exists()) {
            return ""
        }
        return file.readText()
    }

    fun exportFile(directory: File): File {
        directory.mkdirs()
        val timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
            .replace(":", "-")
            .replace(".", "-")
        val exported = File(directory, "typecarrier-android-diagnostics-$timestamp.jsonl")
        exported.writeText(exportText())
        return exported
    }
}
