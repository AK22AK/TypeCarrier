package org.typecarrier.android.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Test
import org.typecarrier.android.diagnostics.AndroidDiagnosticEvent
import org.typecarrier.android.transport.AndroidDiscoveryPrecondition
import org.typecarrier.android.transport.MacService

class AndroidConnectionSelfCheckTest {
    @Test
    fun noNetworkBlocksDiscoveryBeforeGenericNoMacGuidance() {
        val findings = AndroidConnectionSelfCheck.findings(
            AndroidComposerUiState(
                connectionStatus = AndroidConnectionStatus.Searching,
                headerStatusText = "未发现 Mac",
                services = emptyList(),
                discoveryPrecondition = AndroidDiscoveryPrecondition.NoNetwork,
            ),
        )

        assertEquals(AndroidSelfCheckSeverity.Blocking, findings.first().severity)
        assertEquals("当前没有网络连接", findings.first().title)
        assertEquals("连接 Wi-Fi 后重试", findings.first().actionTitle)
        assertEquals("network.precondition", findings.first().relatedEventName)
    }

    @Test
    fun nonLocalNetworkExplainsWifiRequirementBeforeGenericNoMacGuidance() {
        val findings = AndroidConnectionSelfCheck.findings(
            AndroidComposerUiState(
                connectionStatus = AndroidConnectionStatus.Searching,
                headerStatusText = "未发现 Mac",
                services = emptyList(),
                discoveryPrecondition = AndroidDiscoveryPrecondition.NotLocalNetwork,
            ),
        )

        assertEquals(AndroidSelfCheckSeverity.Blocking, findings.first().severity)
        assertEquals("当前网络无法发现局域网 Mac", findings.first().title)
        assertEquals("切换到与 Mac 相同的 Wi-Fi", findings.first().actionTitle)
        assertEquals("network.precondition", findings.first().relatedEventName)
    }

    @Test
    fun searchingWithoutServicesExplainsDiscoveryPrerequisites() {
        val findings = AndroidConnectionSelfCheck.findings(
            AndroidComposerUiState(
                connectionStatus = AndroidConnectionStatus.Searching,
                headerStatusText = "未发现 Mac",
                services = emptyList(),
            ),
        )

        assertEquals(AndroidSelfCheckSeverity.Warning, findings.first().severity)
        assertEquals("没有发现 Mac", findings.first().title)
        assertEquals("检查局域网和 Mac 接收器", findings.first().actionTitle)
        assertEquals("discovery.services", findings.first().relatedEventName)
    }

    @Test
    fun discoveryErrorExplainsRefreshAndFallback() {
        val findings = AndroidConnectionSelfCheck.findings(
            AndroidComposerUiState(
                connectionStatus = AndroidConnectionStatus.Searching,
                diagnostics = listOf(
                    AndroidDiagnosticEvent(name = "discovery.error", message = "解析服务失败：3"),
                ),
            ),
        )

        assertEquals(AndroidSelfCheckSeverity.Warning, findings.first().severity)
        assertEquals("自动发现异常", findings.first().title)
        assertEquals("刷新查找或使用高级连接", findings.first().actionTitle)
        assertEquals("discovery.error", findings.first().relatedEventName)
    }

    @Test
    fun invalidPairingRequiresRepairing() {
        val findings = AndroidConnectionSelfCheck.findings(
            AndroidComposerUiState(
                connectionStatus = AndroidConnectionStatus.Idle,
                connectionFailureMessage = "配对已失效，请重新输入 Mac 匹配码。",
                selectedMac = MacService(name = "MacBook Pro", host = "127.0.0.1", port = 17641),
            ),
        )

        assertEquals(AndroidSelfCheckSeverity.Blocking, findings.first().severity)
        assertEquals("配对已失效", findings.first().title)
        assertEquals("重新输入 Mac 匹配码", findings.first().actionTitle)
    }

    @Test
    fun connectedStateReportsReady() {
        val findings = AndroidConnectionSelfCheck.findings(
            AndroidComposerUiState(
                connectionStatus = AndroidConnectionStatus.Connected,
                selectedMac = MacService(name = "MacBook Pro", host = "127.0.0.1", port = 17641),
            ),
        )

        assertEquals(AndroidSelfCheckSeverity.Ok, findings.first().severity)
        assertEquals("连接可用", findings.first().title)
        assertEquals(null, findings.first().actionTitle)
    }
}
