package org.typecarrier.android.domain

import org.typecarrier.android.protocol.CarrierDeliveryReceipt

object EditorTextReplacementPolicy {
    fun shouldClearEditorAfterDeliveryReceipt(
        pasteStatus: CarrierDeliveryReceipt.PasteStatus,
    ): Boolean = true

    fun shouldClearEditorAfterDraftSave(succeeded: Boolean): Boolean = succeeded
}
