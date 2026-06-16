package org.typecarrier.android.ui

import org.junit.Assert.assertEquals
import org.junit.Test
import org.typecarrier.android.viewmodel.AndroidComposerUiState
import org.typecarrier.android.viewmodel.AndroidConnectionStatus

class ConnectionDisplayTextTest {
    @Test
    fun searchingStateUsesHeaderTextWhenNoMacWasFound() {
        val state = AndroidComposerUiState(
            connectionStatus = AndroidConnectionStatus.Searching,
            headerStatusText = "未发现 Mac",
            services = emptyList(),
        )

        assertEquals("未发现 Mac", connectionDisplayText(state))
    }
}
