package org.typecarrier.android.domain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.typecarrier.android.protocol.CarrierDeliveryReceipt

class EditorTextReplacementPolicyTest {
    @Test
    fun deliveryReceiptClearsEditorForEveryPasteStatus() {
        assertTrue(EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(CarrierDeliveryReceipt.PasteStatus.Received))
        assertTrue(EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(CarrierDeliveryReceipt.PasteStatus.Posted))
        assertTrue(EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(CarrierDeliveryReceipt.PasteStatus.UnverifiedPosted))
        assertTrue(EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(CarrierDeliveryReceipt.PasteStatus.Failed))
    }

    @Test
    fun draftSaveClearsEditorOnlyAfterLocalPersistenceSucceeds() {
        assertTrue(EditorTextReplacementPolicy.shouldClearEditorAfterDraftSave(succeeded = true))
        assertFalse(EditorTextReplacementPolicy.shouldClearEditorAfterDraftSave(succeeded = false))
    }
}
