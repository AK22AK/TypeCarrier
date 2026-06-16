package org.typecarrier.android.viewmodel

import org.typecarrier.android.transport.AndroidDiscoveryPrecondition

enum class AndroidSelfCheckSeverity {
    Ok,
    Warning,
    Blocking,
    Unknown,
}

data class AndroidSelfCheckFinding(
    val id: String,
    val severity: AndroidSelfCheckSeverity,
    val title: String,
    val detail: String,
    val actionTitle: String? = null,
    val relatedEventName: String? = null,
)

object AndroidConnectionSelfCheck {
    fun findings(state: AndroidComposerUiState): List<AndroidSelfCheckFinding> {
        when (state.discoveryPrecondition) {
            AndroidDiscoveryPrecondition.NoNetwork -> return listOf(
                AndroidSelfCheckFinding(
                    id = "network.noNetwork",
                    severity = AndroidSelfCheckSeverity.Blocking,
                    title = "当前没有网络连接",
                    detail = "Android 需要连接到与 Mac 相同的局域网，才能自动发现 Mac 接收端。",
                    actionTitle = "连接 Wi-Fi 后重试",
                    relatedEventName = "network.precondition",
                ),
            )
            AndroidDiscoveryPrecondition.NotLocalNetwork -> return listOf(
                AndroidSelfCheckFinding(
                    id = "network.notLocal",
                    severity = AndroidSelfCheckSeverity.Blocking,
                    title = "当前网络无法发现局域网 Mac",
                    detail = "请让 Android 和 Mac 连接到同一个 Wi-Fi；仅使用移动网络时无法发现局域网内的 Mac。",
                    actionTitle = "切换到与 Mac 相同的 Wi-Fi",
                    relatedEventName = "network.precondition",
                ),
            )
            AndroidDiscoveryPrecondition.Available -> Unit
        }

        val latestDiscoveryError = state.diagnostics.lastOrNull { it.name == "discovery.error" }
        if (latestDiscoveryError != null) {
            return listOf(
                AndroidSelfCheckFinding(
                    id = "discovery.error",
                    severity = AndroidSelfCheckSeverity.Warning,
                    title = "自动发现异常",
                    detail = latestDiscoveryError.message,
                    actionTitle = "刷新查找或使用高级连接",
                    relatedEventName = latestDiscoveryError.name,
                ),
            )
        }

        if (state.connectionFailureMessage?.contains("配对已失效") == true) {
            return listOf(
                AndroidSelfCheckFinding(
                    id = "connection.invalidPairing",
                    severity = AndroidSelfCheckSeverity.Blocking,
                    title = "配对已失效",
                    detail = state.connectionFailureMessage,
                    actionTitle = "重新输入 Mac 匹配码",
                    relatedEventName = "connection.rejected",
                ),
            )
        }

        if (state.connectionFailureMessage != null) {
            return listOf(
                AndroidSelfCheckFinding(
                    id = "connection.failed",
                    severity = AndroidSelfCheckSeverity.Warning,
                    title = "连接失败",
                    detail = state.connectionFailureMessage,
                    actionTitle = if (state.canConnect) "重试连接" else "检查连接信息后重试",
                    relatedEventName = state.diagnostics.lastOrNull { it.name.startsWith("connection.") }?.name,
                ),
            )
        }

        if (state.connectionStatus == AndroidConnectionStatus.Connected) {
            val macName = state.selectedMac?.name ?: "Mac"
            return listOf(
                AndroidSelfCheckFinding(
                    id = "connection.connected",
                    severity = AndroidSelfCheckSeverity.Ok,
                    title = "连接可用",
                    detail = "已连接到 $macName，可以发送文本。",
                ),
            )
        }

        if (state.connectionStatus == AndroidConnectionStatus.Searching && state.services.isEmpty()) {
            return listOf(
                AndroidSelfCheckFinding(
                    id = "discovery.noMac",
                    severity = AndroidSelfCheckSeverity.Warning,
                    title = "没有发现 Mac",
                    detail = "请确认 Mac 端 TypeCarrier 正在运行，手机和 Mac 在同一局域网，并允许网络发现。",
                    actionTitle = "检查局域网和 Mac 接收器",
                    relatedEventName = "discovery.services",
                ),
            )
        }

        if (state.selectedMac != null && !state.canConnect && state.connectionStatus != AndroidConnectionStatus.Connected) {
            return listOf(
                AndroidSelfCheckFinding(
                    id = "connection.needsPairingCode",
                    severity = AndroidSelfCheckSeverity.Warning,
                    title = "需要匹配码",
                    detail = "首次连接这台 Mac 需要输入 Mac 上显示的匹配码。",
                    actionTitle = "输入 Mac 匹配码",
                ),
            )
        }

        return listOf(
            AndroidSelfCheckFinding(
                id = "connection.pending",
                severity = AndroidSelfCheckSeverity.Unknown,
                title = "正在确认连接状态",
                detail = "继续等待自动发现，或查看最近调试事件。",
            ),
        )
    }
}
