package org.typecarrier.android.viewmodel

import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.typecarrier.android.diagnostics.AndroidDiagnosticEvent
import org.typecarrier.android.diagnostics.AndroidDiagnosticLogStore
import org.typecarrier.android.domain.AndroidCarrierRecord
import org.typecarrier.android.domain.AndroidRecordKind
import org.typecarrier.android.domain.AndroidRecordStatus
import org.typecarrier.android.domain.CarrierPayloadPolicy
import org.typecarrier.android.domain.EditorTextReplacementPolicy
import org.typecarrier.android.domain.TextEditHistory
import org.typecarrier.android.protocol.AndroidBridgeResponseStatus
import org.typecarrier.android.protocol.AndroidPairingCode
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.storage.AndroidRecordStore
import org.typecarrier.android.transport.AndroidCarrierRepository
import org.typecarrier.android.transport.MacService
import org.typecarrier.android.transport.manualService

data class AndroidComposerUiState(
    val text: String = "",
    val sendState: AndroidSendState = AndroidSendState.Idle,
    val connectionStatus: AndroidConnectionStatus = AndroidConnectionStatus.Searching,
    val headerStatusText: String = "正在查找 Mac",
    val connectionFailureMessage: String? = null,
    val canSend: Boolean = false,
    val canSaveDraft: Boolean = false,
    val canUndo: Boolean = false,
    val canRedo: Boolean = false,
    val draftCount: Int = 0,
    val records: List<AndroidCarrierRecord> = emptyList(),
    val drafts: List<AndroidCarrierRecord> = emptyList(),
    val outgoingHistory: List<AndroidCarrierRecord> = emptyList(),
    val services: List<MacService> = emptyList(),
    val localPairingCode: String = "",
    val trustedMacs: List<MacService> = emptyList(),
    val selectedMac: MacService? = null,
    val manualHost: String = "",
    val manualPort: String = "17641",
    val pairingCode: String = "",
    val senderDisplayName: String = "",
    val launchesIntoInputMode: Boolean = true,
    val deviceName: String = "Android",
    val canConnect: Boolean = false,
    val isBusy: Boolean = false,
    val diagnostics: List<AndroidDiagnosticEvent> = emptyList(),
)

sealed interface AndroidSendState {
    data object Idle : AndroidSendState
    data object Sending : AndroidSendState
    data object Sent : AndroidSendState
    data class Failed(val message: String) : AndroidSendState
}

enum class AndroidConnectionStatus {
    Idle,
    Searching,
    Connecting,
    Connected,
}

class AndroidComposerViewModel(
    private val repository: AndroidCarrierRepository,
    private val recordStore: AndroidRecordStore,
    private val diagnosticLogStore: AndroidDiagnosticLogStore,
    private val scope: CoroutineScope,
) {
    private val textHistory = TextEditHistory()
    private var connectedMac: MacService? = null
    private var lastServicesDiagnosticSignature: String? = null
    private var lastDiscoveryError: String? = null

    private val _uiState = MutableStateFlow(
        AndroidComposerUiState(
            manualHost = repository.manualHost,
            manualPort = repository.manualPort,
            senderDisplayName = repository.senderDisplayName,
            launchesIntoInputMode = repository.launchesIntoInputMode,
            deviceName = repository.deviceName,
            records = recordStore.records,
            drafts = recordStore.drafts,
            outgoingHistory = recordStore.outgoingHistory,
            draftCount = recordStore.drafts.size,
            diagnostics = diagnosticLogStore.recent(),
            localPairingCode = repository.localPairingCode,
            trustedMacs = repository.trustedMacs,
        ),
    )
    val uiState: StateFlow<AndroidComposerUiState> = _uiState

    private val servicesJob: Job = scope.launch {
        repository.services.collect { services ->
            recordServicesDiagnostic(services)
            val trustedMacs = repository.trustedMacs
            _uiState.update { current ->
                val selected = current.selectedMac?.let { selected ->
                    services.firstOrNull { it.id == selected.id }
                        ?: selected.takeIf { connectedMac?.id == selected.id }
                }
                current.copy(
                    services = services,
                    trustedMacs = trustedMacs,
                    selectedMac = selected,
                    connectionStatus = if (connectedMac != null) current.connectionStatus else if (selected == null) AndroidConnectionStatus.Searching else AndroidConnectionStatus.Idle,
                    headerStatusText = when {
                        connectedMac != null -> current.headerStatusText
                        selected != null -> selected.name
                        services.isEmpty() -> "未发现 Mac"
                        else -> "发现 ${services.size} 台 Mac"
                    },
                ).withDerivedValues(repository)
            }
        }
    }

    private val discoveryErrorJob: Job = scope.launch {
        repository.discoveryError.collect { message ->
            if (!message.isNullOrBlank() && message != lastDiscoveryError) {
                lastDiscoveryError = message
                recordDiagnostic("discovery.error", message)
            }
        }
    }

    fun start() {
        repository.startDiscovery()
        recordDiagnostic("app.start", "Android sender started.")
    }

    fun refreshDiscovery() {
        repository.refreshDiscovery()
        _uiState.update {
            it.copy(
                connectionStatus = AndroidConnectionStatus.Searching,
                headerStatusText = "正在查找 Mac",
                connectionFailureMessage = null,
            ).withDerivedValues(repository)
        }
        recordDiagnostic("discovery.refresh", "Restarted Mac discovery.")
    }

    fun selectMac(service: MacService) {
        repository.closeConnection()
        connectedMac = null
        _uiState.update {
            it.copy(
                selectedMac = service,
                connectionStatus = AndroidConnectionStatus.Idle,
                headerStatusText = service.name,
                connectionFailureMessage = null,
            ).withDerivedValues(repository)
        }
    }

    fun updateManualHost(value: String) {
        repository.manualHost = value
        repository.closeConnection()
        connectedMac = null
        _uiState.update {
            it.copy(
                selectedMac = null,
                manualHost = repository.manualHost,
                connectionStatus = AndroidConnectionStatus.Idle,
                headerStatusText = "手动 Mac",
            ).withDerivedValues(repository)
        }
    }

    fun updateManualPort(value: String) {
        repository.manualPort = value
        repository.closeConnection()
        connectedMac = null
        _uiState.update {
            it.copy(
                selectedMac = null,
                manualPort = repository.manualPort,
                connectionStatus = AndroidConnectionStatus.Idle,
                headerStatusText = "手动 Mac",
            ).withDerivedValues(repository)
        }
    }

    fun updatePairingCode(value: String) {
        _uiState.update { it.copy(pairingCode = value.filter(Char::isDigit).take(6)).withDerivedValues(repository) }
    }

    fun updateSenderDisplayName(value: String) {
        repository.senderDisplayName = value
        _uiState.update { it.copy(senderDisplayName = repository.senderDisplayName).withDerivedValues(repository) }
        recordDiagnostic("settings.senderName.updated", "Updated sender display name.")
    }

    fun updateLaunchesIntoInputMode(value: Boolean) {
        repository.launchesIntoInputMode = value
        _uiState.update { it.copy(launchesIntoInputMode = value).withDerivedValues(repository) }
        recordDiagnostic("settings.launchesIntoInputMode.updated", "launchesIntoInputMode=$value")
    }

    fun updateText(value: String) {
        val oldValue = _uiState.value.text
        textHistory.recordChange(from = oldValue, to = value)
        _uiState.update {
            it.copy(text = value, sendState = AndroidSendState.Idle).withDerivedValues(repository)
        }
    }

    fun clearText(): Job = scope.launch {
        val current = _uiState.value.text
        if (current.isBlank()) {
            return@launch
        }
        textHistory.recordChange(from = current, to = "")
        _uiState.update { it.copy(text = "", sendState = AndroidSendState.Idle).withDerivedValues(repository) }
        recordDiagnostic("editor.clear", "Cleared editor text.")
    }

    fun undoTextChange() {
        val previous = textHistory.undo(current = _uiState.value.text) ?: return
        _uiState.update { it.copy(text = previous, sendState = AndroidSendState.Idle).withDerivedValues(repository) }
    }

    fun redoTextChange() {
        val next = textHistory.redo(current = _uiState.value.text) ?: return
        _uiState.update { it.copy(text = next, sendState = AndroidSendState.Idle).withDerivedValues(repository) }
    }

    fun copyText() {
        if (_uiState.value.text.isBlank()) {
            return
        }
        recordDiagnostic("editor.copy", "Copied editor text.")
    }

    fun connect(): Job = scope.launch {
        val service = effectiveService() ?: return@launch
        if (!_uiState.value.canConnect) {
            return@launch
        }
        val pairingCode = _uiState.value.pairingCode.takeIf(AndroidPairingCode::isValid)
        connectToService(service, requestedPairingCode = pairingCode)
    }

    private suspend fun connectToService(
        service: MacService,
        requestedPairingCode: String?,
    ) {
        _uiState.update {
            it.copy(
                isBusy = true,
                connectionStatus = AndroidConnectionStatus.Connecting,
                headerStatusText = connectingStatusText(service),
                connectionFailureMessage = null,
                selectedMac = service,
            ).withDerivedValues(repository)
        }

        val shouldUseSavedTrust = repository.hasSavedTrustToken(service)
        val usesPairingCode = requestedPairingCode != null
        recordDiagnostic(
            "connection.attempt",
            "target=${service.name} host=${service.host} port=${service.port} macID=${service.macID ?: "unknown"} savedTrust=$shouldUseSavedTrust auth=${if (usesPairingCode) "pairingCode" else if (shouldUseSavedTrust) "trustToken" else "none"} discovered=${_uiState.value.services.size}",
        )

        runCatching {
            repository.connect(
                service = service,
                pairingCode = requestedPairingCode,
            )
        }.onSuccess { response ->
            if (response.status == AndroidBridgeResponseStatus.Accepted) {
                val trustedMacs = repository.trustedMacs
                val connectedService = trustedMacs.firstOrNull { trusted ->
                    response.macID?.let { trusted.macID == it } == true ||
                        (trusted.host == service.host && trusted.port == service.port)
                } ?: service
                connectedMac = connectedService
                _uiState.update {
                    it.copy(
                        isBusy = false,
                        connectionStatus = AndroidConnectionStatus.Connected,
                        headerStatusText = connectedService.name,
                        connectionFailureMessage = null,
                        pairingCode = "",
                        selectedMac = connectedService,
                        trustedMacs = trustedMacs,
                    ).withDerivedValues(repository)
                }
                recordDiagnostic("connection.accepted", "Connected to ${connectedService.name}.")
            } else {
                val trustTokenRejected = response.status == AndroidBridgeResponseStatus.InvalidPairing && !usesPairingCode && shouldUseSavedTrust
                if (trustTokenRejected) {
                    repository.forgetTrustedMac(service)
                }
                val trustedMacs = repository.trustedMacs
                val message = if (trustTokenRejected) {
                    "配对已失效，请重新输入 Mac 匹配码。"
                } else {
                    response.message ?: response.status.name
                }
                repository.closeConnection()
                connectedMac = null
                _uiState.update {
                    it.copy(
                        isBusy = false,
                        connectionStatus = AndroidConnectionStatus.Idle,
                        headerStatusText = "连接失败",
                        connectionFailureMessage = message,
                        trustedMacs = trustedMacs,
                    ).withDerivedValues(repository)
                }
                recordDiagnostic("connection.rejected", message)
            }
        }.onFailure { error ->
            repository.closeConnection()
            connectedMac = null
            val rawMessage = error.localizedMessage ?: "连接失败"
            _uiState.update {
                it.copy(
                    isBusy = false,
                    connectionStatus = AndroidConnectionStatus.Idle,
                    headerStatusText = "连接失败",
                    connectionFailureMessage = connectionFailureMessage(service, rawMessage),
                ).withDerivedValues(repository)
            }
            recordDiagnostic("connection.failed", rawMessage)
        }
    }

    fun send(): Job = scope.launch {
        val state = _uiState.value
        if (!state.canSend) {
            failSend("文本为空")
            return@launch
        }

        val textToSend = state.text
        val payloadID = UUID.randomUUID().toString().uppercase()
        val now = Instant.now().toString()
        val record = AndroidCarrierRecord(
            id = UUID.randomUUID().toString(),
            payloadID = payloadID,
            kind = AndroidRecordKind.Outgoing,
            status = AndroidRecordStatus.Queued,
            text = textToSend,
            createdAt = now,
            updatedAt = now,
            detail = "等待发送",
        )

        recordStore.upsert(record)
        syncRecords()
        _uiState.update { it.copy(isBusy = true, sendState = AndroidSendState.Sending).withDerivedValues(repository) }

        runCatching {
            refreshTrustedConnectionBeforeSend(state)
            repository.sendText(textToSend, state.senderDisplayName.ifBlank { state.deviceName })
        }.onSuccess { receipt ->
            val detail = receipt?.detail ?: "已发送"
            updateRecord(
                record.copy(
                    status = statusForReceipt(receipt),
                    detail = detail,
                    updatedAt = Instant.now().toString(),
                ),
            )
            _uiState.update {
                it.copy(
                    text = if (receipt == null || EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(receipt.pasteStatus)) "" else it.text,
                    isBusy = false,
                    sendState = AndroidSendState.Sent,
                    connectionFailureMessage = null,
                ).withDerivedValues(repository)
            }
            textHistory.reset()
            recordDiagnostic("send.succeeded", detail)
        }.onFailure { error ->
            val message = error.localizedMessage ?: "发送失败"
            repository.closeConnection()
            connectedMac = null
            updateRecord(
                record.copy(
                    status = AndroidRecordStatus.Failed,
                    detail = message,
                    updatedAt = Instant.now().toString(),
                ),
            )
            _uiState.update {
                it.copy(
                    isBusy = false,
                    sendState = AndroidSendState.Failed(message),
                    connectionStatus = AndroidConnectionStatus.Idle,
                    headerStatusText = "发送失败",
                    connectionFailureMessage = message,
                ).withDerivedValues(repository)
            }
            recordDiagnostic("send.failed", message)
        }
    }

    private suspend fun refreshTrustedConnectionBeforeSend(state: AndroidComposerUiState) {
        val service = state.selectedMac ?: connectedMac ?: manualService(state.manualHost, state.manualPort) ?: return
        if (!repository.hasSavedTrustToken(service)) {
            return
        }

        _uiState.update {
            it.copy(
                connectionStatus = AndroidConnectionStatus.Connecting,
                headerStatusText = connectingStatusText(service),
                connectionFailureMessage = null,
                selectedMac = service,
            ).withDerivedValues(repository)
        }
        recordDiagnostic(
            "connection.presendAttempt",
            "target=${service.name} host=${service.host} port=${service.port} macID=${service.macID ?: "unknown"} auth=trustToken",
        )

        val response = repository.connect(service = service, pairingCode = null)
        if (response.status != AndroidBridgeResponseStatus.Accepted) {
            val message = response.message ?: response.status.name
            if (response.status == AndroidBridgeResponseStatus.InvalidPairing) {
                repository.forgetTrustedMac(service)
            }
            repository.closeConnection()
            connectedMac = null
            _uiState.update {
                it.copy(
                    connectionStatus = AndroidConnectionStatus.Idle,
                    headerStatusText = "连接失败",
                    connectionFailureMessage = message,
                    trustedMacs = repository.trustedMacs,
                ).withDerivedValues(repository)
            }
            recordDiagnostic("connection.rejected", message)
            throw IllegalStateException(message)
        }

        val trustedMacs = repository.trustedMacs
        val connectedService = trustedMacs.firstOrNull { trusted ->
            response.macID?.let { trusted.macID == it } == true ||
                (trusted.host == service.host && trusted.port == service.port)
        } ?: service
        connectedMac = connectedService
        _uiState.update {
            it.copy(
                connectionStatus = AndroidConnectionStatus.Connected,
                headerStatusText = connectedService.name,
                connectionFailureMessage = null,
                selectedMac = connectedService,
                trustedMacs = trustedMacs,
            ).withDerivedValues(repository)
        }
        recordDiagnostic("connection.accepted", "Connected to ${connectedService.name}.")
    }

    fun saveDraft(): Job = scope.launch {
        val state = _uiState.value
        if (!CarrierPayloadPolicy.canSend(state.text)) {
            failSend("文本为空")
            return@launch
        }

        if (state.draftCount >= maximumDraftCount) {
            failSend("请先处理或删除一些草稿，再保存新的草稿。")
            return@launch
        }

        val now = Instant.now().toString()
        recordStore.upsert(
            AndroidCarrierRecord(
                id = UUID.randomUUID().toString(),
                kind = AndroidRecordKind.Draft,
                status = AndroidRecordStatus.Draft,
                text = state.text,
                createdAt = now,
                updatedAt = now,
                detail = "已保存草稿",
            ),
        )
        val nextText = if (EditorTextReplacementPolicy.shouldClearEditorAfterDraftSave(succeeded = true)) "" else state.text
        textHistory.reset()
        _uiState.update {
            it.copy(text = nextText, sendState = AndroidSendState.Sent).withDerivedValues(repository)
        }
        syncRecords()
        recordDiagnostic("draft.saved", "Saved draft.")
    }

    fun loadIntoEditor(record: AndroidCarrierRecord) {
        textHistory.reset()
        _uiState.update {
            it.copy(text = record.text, sendState = AndroidSendState.Idle).withDerivedValues(repository)
        }
    }

    fun send(record: AndroidCarrierRecord): Job {
        loadIntoEditor(record)
        return send()
    }

    fun updateText(forRecord: AndroidCarrierRecord, text: String) {
        updateRecord(
            forRecord.copy(
                text = text,
                updatedAt = Instant.now().toString(),
                detail = if (forRecord.kind == AndroidRecordKind.Draft) "已更新草稿" else "已编辑历史文本",
            ),
        )
    }

    fun delete(record: AndroidCarrierRecord) {
        recordStore.delete(record.id)
        syncRecords()
    }

    fun deleteAllDrafts() {
        recordStore.deleteAll(AndroidRecordKind.Draft)
        syncRecords()
    }

    fun deleteAllOutgoingHistory() {
        recordStore.deleteAll(AndroidRecordKind.Outgoing)
        syncRecords()
    }

    fun exportDiagnosticsText(): String = diagnosticLogStore.exportText()

    fun exportDiagnosticsFile(directory: File): File = diagnosticLogStore.exportFile(directory)

    fun close() {
        servicesJob.cancel()
        discoveryErrorJob.cancel()
        repository.close()
    }

    private fun failSend(message: String) {
        _uiState.update {
            it.copy(sendState = AndroidSendState.Failed(message), connectionFailureMessage = message).withDerivedValues(repository)
        }
        recordDiagnostic("send.failed", message)
    }

    private fun updateRecord(record: AndroidCarrierRecord) {
        recordStore.upsert(record)
        syncRecords()
    }

    private fun syncRecords() {
        _uiState.update {
            it.copy(
                records = recordStore.records,
                drafts = recordStore.drafts,
                outgoingHistory = recordStore.outgoingHistory,
                draftCount = recordStore.drafts.size,
                diagnostics = diagnosticLogStore.recent(),
                trustedMacs = repository.trustedMacs,
            ).withDerivedValues(repository)
        }
    }

    private fun recordDiagnostic(name: String, message: String) {
        diagnosticLogStore.append(name, message)
        _uiState.update { it.copy(diagnostics = diagnosticLogStore.recent()).withDerivedValues(repository) }
    }

    private fun recordServicesDiagnostic(services: List<MacService>) {
        val signature = services.joinToString("|") { "${it.name}@${it.host}:${it.port}:${it.macID.orEmpty()}" }
        if (signature == lastServicesDiagnosticSignature) {
            return
        }
        lastServicesDiagnosticSignature = signature
        val message = if (services.isEmpty()) {
            "No Mac services discovered."
        } else {
            services.joinToString { "${it.name}@${it.host}:${it.port}" }
        }
        recordDiagnostic("discovery.services", message)
    }

    private fun effectiveService(): MacService? =
        _uiState.value.selectedMac ?: manualService(_uiState.value.manualHost, _uiState.value.manualPort)

    private fun connectingStatusText(service: MacService): String {
        if (service.isManualMac()) {
            return "正在连接到手动输入的 Mac"
        }
        return "正在连接到 ${service.name}"
    }

    private fun connectionFailureMessage(service: MacService, rawMessage: String): String {
        if (!service.isManualMac()) {
            return rawMessage
        }
        return "无法连接到手动输入的 Mac。请确认连接管理里的 Mac 地址是当前这台 Mac 的局域网地址。"
    }

    private fun MacService.isManualMac(): Boolean = name == "手动 Mac"

    private fun statusForReceipt(receipt: CarrierDeliveryReceipt?): AndroidRecordStatus {
        return when (receipt?.pasteStatus) {
            CarrierDeliveryReceipt.PasteStatus.Posted -> AndroidRecordStatus.PastePosted
            CarrierDeliveryReceipt.PasteStatus.UnverifiedPosted -> AndroidRecordStatus.PasteUnverified
            CarrierDeliveryReceipt.PasteStatus.Failed -> AndroidRecordStatus.PasteFailed
            CarrierDeliveryReceipt.PasteStatus.Received, null -> AndroidRecordStatus.Received
        }
    }

    private fun AndroidComposerUiState.withDerivedValues(
        repository: AndroidCarrierRepository,
    ): AndroidComposerUiState {
        val service = selectedMac ?: manualService(manualHost, manualPort)
        val canConnect = service != null &&
            !isBusy &&
            connectionStatus != AndroidConnectionStatus.Connected &&
            (AndroidPairingCode.isValid(pairingCode) || repository.hasSavedTrustToken(service))
        val connected = connectionStatus == AndroidConnectionStatus.Connected
        return copy(
            canSend = CarrierPayloadPolicy.canSend(text) && connected && sendState != AndroidSendState.Sending && !isBusy,
            canSaveDraft = CarrierPayloadPolicy.canSend(text),
            canUndo = textHistory.canUndo,
            canRedo = textHistory.canRedo,
            canConnect = canConnect,
        )
    }

    private companion object {
        const val maximumDraftCount = 99
    }
}
