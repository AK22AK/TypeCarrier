package org.typecarrier.android.storage

import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.typecarrier.android.domain.AndroidCarrierRecord
import org.typecarrier.android.domain.AndroidRecordKind
import org.typecarrier.android.domain.AndroidRecordStatus

class AndroidRecordStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun upsertSortsNewestFirstAndPersistsRecords() {
        val file = temporaryFolder.newFile("records.json").also(File::delete)
        val store = AndroidRecordStore(file = file)
        val older = record(text = "older", updatedAt = "2026-06-01T01:00:00Z")
        val newer = record(text = "newer", updatedAt = "2026-06-01T02:00:00Z")

        store.upsert(older)
        store.upsert(newer)

        assertEquals(listOf("newer", "older"), store.records.map { it.text })
        assertEquals(listOf("newer", "older"), AndroidRecordStore(file = file).records.map { it.text })
    }

    @Test
    fun deleteRemovesRecordAndSavesFile() {
        val file = temporaryFolder.newFile("records.json").also(File::delete)
        val store = AndroidRecordStore(file = file)
        val record = record(text = "delete me")
        store.upsert(record)

        store.delete(record.id)

        assertTrue(store.records.isEmpty())
        assertTrue(AndroidRecordStore(file = file).records.isEmpty())
    }

    @Test
    fun limitPrunesOldestRecords() {
        val file = temporaryFolder.newFile("records.json").also(File::delete)
        val store = AndroidRecordStore(file = file, limit = 2)

        store.upsert(record(text = "one", updatedAt = "2026-06-01T01:00:00Z"))
        store.upsert(record(text = "two", updatedAt = "2026-06-01T02:00:00Z"))
        store.upsert(record(text = "three", updatedAt = "2026-06-01T03:00:00Z"))

        assertEquals(listOf("three", "two"), store.records.map { it.text })
    }

    @Test
    fun draftsAndOutgoingHistoryAreFilteredSeparately() {
        val file = temporaryFolder.newFile("records.json").also(File::delete)
        val store = AndroidRecordStore(file = file)

        store.upsert(record(text = "draft", kind = AndroidRecordKind.Draft, status = AndroidRecordStatus.Draft))
        store.upsert(record(text = "sent", kind = AndroidRecordKind.Outgoing, status = AndroidRecordStatus.Sent))

        assertEquals(listOf("draft"), store.drafts.map { it.text })
        assertEquals(listOf("sent"), store.outgoingHistory.map { it.text })
    }

    private fun record(
        text: String,
        kind: AndroidRecordKind = AndroidRecordKind.Outgoing,
        status: AndroidRecordStatus = AndroidRecordStatus.Sent,
        updatedAt: String = Instant.now().toString(),
    ): AndroidCarrierRecord =
        AndroidCarrierRecord(
            id = UUID.randomUUID().toString(),
            payloadID = UUID.randomUUID().toString(),
            kind = kind,
            status = status,
            text = text,
            createdAt = updatedAt,
            updatedAt = updatedAt,
            detail = null,
        )
}
