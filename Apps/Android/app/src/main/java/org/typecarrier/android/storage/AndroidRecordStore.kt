package org.typecarrier.android.storage

import java.io.File
import java.time.Instant
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.typecarrier.android.domain.AndroidCarrierRecord
import org.typecarrier.android.domain.AndroidRecordKind

class AndroidRecordStore(
    private val file: File,
    private val limit: Int = 200,
) {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    var records: List<AndroidCarrierRecord> = loadRecords()
        private set

    val drafts: List<AndroidCarrierRecord>
        get() = records.filter { it.kind == AndroidRecordKind.Draft }

    val outgoingHistory: List<AndroidCarrierRecord>
        get() = records.filter { it.kind == AndroidRecordKind.Outgoing }

    fun upsert(record: AndroidCarrierRecord) {
        records = records
            .filterNot { it.id == record.id }
            .plus(record)
            .sortedWith(recordComparator)
            .take(limit)
        save()
    }

    fun delete(id: String) {
        records = records.filterNot { it.id == id }
        save()
    }

    fun deleteAll(kind: AndroidRecordKind) {
        records = records.filterNot { it.kind == kind }
        save()
    }

    private fun loadRecords(): List<AndroidCarrierRecord> {
        if (!file.exists()) {
            return emptyList()
        }

        return runCatching {
            json.decodeFromString(ListSerializer(AndroidCarrierRecord.serializer()), file.readText())
                .sortedWith(recordComparator)
                .take(limit)
        }.getOrElse {
            emptyList()
        }
    }

    private fun save() {
        file.parentFile?.mkdirs()
        file.writeText(json.encodeToString(ListSerializer(AndroidCarrierRecord.serializer()), records))
    }

    private companion object {
        val recordComparator = compareByDescending<AndroidCarrierRecord> { Instant.parse(it.updatedAt) }
            .thenByDescending { Instant.parse(it.createdAt) }
    }
}
