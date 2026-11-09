package org.typecarrier.android.viewmodel

import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierPostPasteAction
import org.typecarrier.android.storage.AndroidRecordStore
import org.typecarrier.android.transport.AndroidCarrierRepository
import org.typecarrier.android.transport.AndroidConnectResult
import org.typecarrier.android.transport.AndroidPairingPrompt
import org.typecarrier.android.transport.AndroidDiscoveryPrecondition
import org.typecarrier.android.transport.MacService
import org.typecarrier.android.transport.manualService

data class AndroidComposerUiState(
    val text: String = "",
    val sendState: AndroidSendState = AndroidSendState.Idle,
    val connectionStatus: AndroidConnectionStatus = AndroidConnectionStatus.Searching,
    val headerStatusText: String = "正在查找设备",
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
    val connectedMacs: List<MacService> = emptyList(),
    val trustedMacs: List<MacService> = emptyList(),
    val selectedMac: MacService? = null,
    val manualHost: String = "",
    val manualPort: String = "17642",
    /** While pairing: the code to compare with the one the Mac shows. */
    val pairingPrompt: AndroidPairingPrompt? = null,
    val senderDisplayName: String = "",
    val launchesIntoInputMode: Boolean = true,
    val enablesSendReturnGesture: Boolean = false,
    val sendsReturnAfterPaste: Boolean = false,
    val deviceName: String = "Android",
    val canConnect: Boolean = false,
    val isBusy: Boolean = false,
    val discoveryPrecondition: AndroidDiscoveryPrecondition = AndroidDiscoveryPrecondition.Available,
    val diagnostics: List<AndroidDiagnosticEvent> = emptyList(),
    /** True after discovery ran out without a connection and was stopped until the person retries. */
    val searchTimedOut: Boolean = false,
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
    private val searchTimeoutMillis: Long = SEARCH_TIMEOUT_MILLIS,
    private val resumeSearchTimeoutMillis: Long = RESUME_SEARCH_TIMEOUT_MILLIS,
) {
    companion object {
        private const val maximumDraftCount = 99
        const val SEARCH_TIMEOUT_MILLIS = 15_000L
        const val RESUME_SEARCH_TIMEOUT_MILLIS = 25_000L
        const val SEARCH_TIMED_OUT_TITLE = "未找到设备"
        const val SEARCH_TIMED_OUT_MESSAGE = "已停止搜索。确认设备上的 TypeCarrier 已打开、两台设备在同一网络，然后点刷新重试。"
    }

    private var searchTimeoutJob: Job? = null
    private var searchHolds = 0

    private val textHistory = TextEditHistory()
    private var connectedMac: MacService? = null
    private var autoConnectAttemptedServiceIDs: Set<String> = emptySet()
    private var autoSelectedServiceID: String? = null
    private var lastServicesDiagnosticSignature: String? = null
    private var lastDiscoveryError: String? = null

    private val _uiState = MutableStateFlow(
        AndroidComposerUiState(
            manualHost = repository.manualHost,
            manualPort = repository.manualPort,
            senderDisplayName = repository.senderDisplayName,
            launchesIntoInputMode = repository.launchesIntoInputMode,
            enablesSendReturnGesture = repository.enablesSendReturnGesture,
            deviceName = repository.deviceName,
            records = recordStore.records,
            drafts = recordStore.drafts,
            outgoingHistory = recordStore.outgoingHistory,
            draftCount = recordStore.drafts.size,
            discoveryPrecondition = repository.discoveryPrecondition.value,
            diagnostics = diagnosticLogStore.recent(),
            trustedMacs = repository.trustedMacs,
        ),
    )
    val uiState: StateFlow<AndroidComposerUiState> = _uiState

    private val servicesJob: Job = scope.launch {
        repository.services.collect { services ->
            recordServicesDiagnostic(services)
            val trustedMacs = repository.trustedMacs
            autoConnectAttemptedServiceIDs = autoConnectAttemptedServiceIDs.intersect(services.map { it.id }.toSet())
            var autoConnectTarget: MacService? = null
            var autoSelectedTarget: MacService? = null
            _uiState.update { current ->
                val currentSelected = current.selectedMac?.let { selected ->
                    services.firstOrNull { it.id == selected.id } ?: selected
                }
                autoConnectTarget = autoConnectTarget(services = services, current = current, selected = currentSelected)
                val selected = currentSelected ?: autoSelectTarget(services = services, current = current)
                if (currentSelected == null) {
                    autoSelectedTarget = selected
                    autoSelectedServiceID = selected?.id
                }
                current.copy(
                    services = services,
                    trustedMacs = trustedMacs,
                    selectedMac = selected,
                    connectionStatus = if (connectedMac != null || current.searchTimedOut) current.connectionStatus else if (selected == null) AndroidConnectionStatus.Searching else AndroidConnectionStatus.Idle,
                    headerStatusText = when {
                        connectedMac != null || current.searchTimedOut -> current.headerStatusText
                        selected != null -> selected.name
                        services.isEmpty() -> "未发现设备"
                        else -> "发现 ${services.size} 台设备"
                    },
                ).withDerivedValues(repository)
            }
            autoSelectedTarget?.let { service ->
                recordDiagnostic("discovery.autoSelected", "Selected sole discovered Mac ${service.name}.")
            }
            autoConnectTarget?.let { service ->
                autoConnectAttemptedServiceIDs = autoConnectAttemptedServiceIDs + service.id
                connectToService(service)
            }
        }
    }

    private val connectionsJob: Job = scope.launch {
        repository.connectedServices.collect { connected ->
            _uiState.update { current ->
                connectedMac = connected.firstOrNull { it.id == current.selectedMac?.id }
                val selected = connectedMac ?: current.selectedMac
                current.copy(
                    connectedMacs = connected,
                    selectedMac = selected,
                    trustedMacs = repository.trustedMacs,
                    connectionStatus = if (current.isBusy) current.connectionStatus else if (connectedMac != null) {
                        AndroidConnectionStatus.Connected
                    } else if (selected != null) AndroidConnectionStatus.Idle else current.connectionStatus,
                    headerStatusText = selected?.name ?: current.headerStatusText,
                ).withDerivedValues(repository)
            }
        }
    }

    private val pairingPromptJob: Job = scope.launch {
        repository.pairingPrompt.collect { prompt ->
            _uiState.update { it.copy(pairingPrompt = prompt) }
            prompt?.let { recordDiagnostic("pairing.codeShown", "Comparing a pairing code with ${it.macName}.") }
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

    private val discoveryPreconditionJob: Job = scope.launch {
        repository.discoveryPrecondition.collect { precondition ->
            _uiState.update { it.copy(discoveryPrecondition = precondition) }
            if (precondition != AndroidDiscoveryPrecondition.Available) {
                recordDiagnostic("network.precondition", precondition.diagnosticMessage)
            }
        }
    }

    fun start() {
        repository.startDiscovery()
        scheduleSearchTimeout(searchTimeoutMillis)
        recordDiagnostic("app.start", "Android sender started.")
    }

    fun refreshDiscovery() {
        repository.refreshDiscovery()
        scheduleSearchTimeout(searchTimeoutMillis)
        _uiState.update {
            it.copy(
                connectionStatus = if (connectedMac != null) AndroidConnectionStatus.Connected else AndroidConnectionStatus.Searching,
                headerStatusText = connectedMac?.name ?: "正在查找设备",
                connectionFailureMessage = null,
                searchTimedOut = false,
            ).withDerivedValues(repository)
        }
        recordDiagnostic("discovery.refresh", "Restarted Mac discovery.")
    }

    /** Stops discovery (and its Wi-Fi multicast lock) while the app is not visible. */
    fun handleAppEnteredBackground() {
        cancelSearchTimeout()
        repository.stopDiscovery()
        recordDiagnostic("app.backgroundDiscoveryStopped", "Stopped Mac discovery in background.")
    }

    /** Keeps discovering until the matching [endSearchHold]; restarts a search that timed out. */
    fun beginSearchHold() {
        searchHolds += 1
        cancelSearchTimeout()
        if (_uiState.value.searchTimedOut) {
            refreshDiscovery()
            cancelSearchTimeout()
        }
    }

    fun endSearchHold() {
        searchHolds = (searchHolds - 1).coerceAtLeast(0)
        if (searchHolds == 0 && !_uiState.value.searchTimedOut) {
            scheduleSearchTimeout(searchTimeoutMillis)
        }
    }

    private fun scheduleSearchTimeout(timeoutMillis: Long) {
        searchTimeoutJob?.cancel()
        if (searchHolds > 0) {
            searchTimeoutJob = null
            return
        }
        searchTimeoutJob = scope.launch {
            delay(timeoutMillis)
            searchTimeoutJob = null
            handleSearchTimeout(timeoutMillis)
        }
    }

    private fun cancelSearchTimeout() {
        searchTimeoutJob?.cancel()
        searchTimeoutJob = null
    }

    private fun handleSearchTimeout(timeoutMillis: Long) {
        val state = _uiState.value
        if (connectedMac != null || state.isBusy || state.pairingPrompt != null || searchHolds > 0 || state.services.isNotEmpty()) {
            // Connected, connecting, pairing, or computers are listed for the person to pick:
            // "not found" would be wrong, so look again later instead.
            scheduleSearchTimeout(searchTimeoutMillis)
            return
        }
        repository.stopDiscovery()
        _uiState.update {
            it.copy(
                connectionStatus = AndroidConnectionStatus.Idle,
                headerStatusText = SEARCH_TIMED_OUT_TITLE,
                connectionFailureMessage = SEARCH_TIMED_OUT_MESSAGE,
                searchTimedOut = true,
            ).withDerivedValues(repository)
        }
        recordDiagnostic("discovery.timeout", "Nothing connected within ${timeoutMillis} ms; stopped discovery.")
    }

    fun handleAppBecameActive() {
        val state = _uiState.value
        repository.startDiscovery()
        scheduleSearchTimeout(resumeSearchTimeoutMillis)
        if (state.isBusy || state.connectionStatus == AndroidConnectionStatus.Connected) {
            return
        }
        _uiState.update { it.copy(searchTimedOut = false, connectionFailureMessage = null).withDerivedValues(repository) }

        val trustedSelectedMac = state.selectedMac?.takeIf(repository::isPaired)
        if (trustedSelectedMac != null) {
            recordDiagnostic(
                "app.foregroundTrustedReconnect",
                "Reconnecting to ${trustedSelectedMac.name} after app became active.",
            )
            scope.launch {
                connectToService(trustedSelectedMac)
            }
            return
        }

        repository.refreshDiscovery()
        _uiState.update {
            it.copy(
                connectionStatus = AndroidConnectionStatus.Searching,
                headerStatusText = "正在查找设备",
                connectionFailureMessage = null,
            ).withDerivedValues(repository)
        }
        recordDiagnostic("app.foregroundDiscoveryRefresh", "Restarted Mac discovery after app became active.")
    }

    fun selectMac(service: MacService) {
        if (_uiState.value.isBusy) return
        connectedMac = repository.connectedServices.value.firstOrNull { it.id == service.id }
        autoSelectedServiceID = null
        _uiState.update {
            it.copy(
                selectedMac = service,
                connectionStatus = if (connectedMac != null) AndroidConnectionStatus.Connected else AndroidConnectionStatus.Idle,
                headerStatusText = service.name,
                connectionFailureMessage = null,
            ).withDerivedValues(repository)
        }
    }

    fun disconnectSelectedMac() {
        if (_uiState.value.isBusy) return
        _uiState.value.selectedMac?.let(repository::closeConnection)
        connectedMac = null
        _uiState.update {
            it.copy(connectionStatus = AndroidConnectionStatus.Idle).withDerivedValues(repository)
        }
    }

    fun updateManualHost(value: String) {
        if (_uiState.value.isBusy) return
        repository.manualHost = value
        connectedMac = null
        autoSelectedServiceID = null
        _uiState.update {
            it.copy(
                selectedMac = null,
                manualHost = repository.manualHost,
                connectionStatus = AndroidConnectionStatus.Idle,
                headerStatusText = "手动输入的设备",
            ).withDerivedValues(repository)
        }
    }

    fun updateManualPort(value: String) {
        if (_uiState.value.isBusy) return
        repository.manualPort = value
        connectedMac = null
        autoSelectedServiceID = null
        _uiState.update {
            it.copy(
                selectedMac = null,
                manualPort = repository.manualPort,
                connectionStatus = AndroidConnectionStatus.Idle,
                headerStatusText = "手动输入的设备",
            ).withDerivedValues(repository)
        }
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

    fun updateEnablesSendReturnGesture(value: Boolean) {
        repository.enablesSendReturnGesture = value
        _uiState.update {
            it.copy(
                enablesSendReturnGesture = value,
                sendsReturnAfterPaste = if (value) it.sendsReturnAfterPaste else false,
            ).withDerivedValues(repository)
        }
        recordDiagnostic("settings.sendReturnGesture.updated", "enablesSendReturnGesture=$value")
    }

    fun updateSendsReturnAfterPaste(value: Boolean) {
        _uiState.update { current ->
            current.copy(
                sendsReturnAfterPaste = if (current.enablesSendReturnGesture) value else false,
            ).withDerivedValues(repository)
        }
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

    /**
     * The header's retry button. It reconnects to a paired computer, and otherwise searches again:
     * pairing only starts when the person picks a computer and taps pair in the connection dialog.
     */
    fun retryFromHeader() {
        val service = _uiState.value.selectedMac
        if (_uiState.value.canConnect && service != null && repository.isPaired(service)) {
            connect()
        } else {
            refreshDiscovery()
        }
    }

    fun connect(): Job = scope.launch {
        val service = effectiveService() ?: return@launch
        if (!_uiState.value.canConnect) {
            return@launch
        }
        connectToService(service)
    }

    private suspend fun connectToService(service: MacService) {
        _uiState.update {
            it.copy(
                isBusy = true,
                connectionStatus = AndroidConnectionStatus.Connecting,
                headerStatusText = connectingStatusText(service),
                connectionFailureMessage = null,
                selectedMac = service,
            ).withDerivedValues(repository)
        }

        val paired = repository.isPaired(service)
        recordDiagnostic(
            "connection.attempt",
            "target=${service.name} host=${service.host} port=${service.port} macID=${service.macID ?: "unknown"} auth=${if (paired) "pairedKey" else "pairing"} discovered=${_uiState.value.services.size}",
        )

        runCatching {
            repository.connect(service = service)
        }.onSuccess { result ->
            if (result is AndroidConnectResult.Connected) {
                val trustedMacs = repository.trustedMacs
                val connectedService = repository.connectedServices.value.firstOrNull {
                    it.host == service.host && it.port == service.port &&
                        it.appBundleID == service.appBundleID && it.appVariant == service.appVariant
                } ?: service
                connectedMac = connectedService
                autoSelectedServiceID = null
                _uiState.update {
                    it.copy(
                        isBusy = false,
                        connectionStatus = AndroidConnectionStatus.Connected,
                        headerStatusText = connectedService.name,
                        connectionFailureMessage = null,
                        selectedMac = connectedService,
                        trustedMacs = trustedMacs,
                    ).withDerivedValues(repository)
                }
                recordDiagnostic("connection.accepted", "Connected to ${connectedService.name}.")
            } else {
                val rejected = result as AndroidConnectResult.Rejected
                val trustedMacs = repository.trustedMacs
                val message = if (rejected.pairingRemoved) {
                    "配对已失效，请重新配对。"
                } else {
                    rejected.message
                }
                repository.closeConnection(service)
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
            repository.closeConnection(service)
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
            repository.sendText(
                service = state.selectedMac ?: connectedMac ?: error("请选择发送目标"),
                text = textToSend,
                senderDisplayName = state.senderDisplayName.ifBlank { state.deviceName },
                postPasteAction = if (state.enablesSendReturnGesture && state.sendsReturnAfterPaste) {
                    CarrierPostPasteAction.PressReturn
                } else {
                    null
                },
            )
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
            state.selectedMac?.let(repository::closeConnection)
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
        if (!repository.isPaired(service)) {
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
            "target=${service.name} host=${service.host} port=${service.port} macID=${service.macID ?: "unknown"} auth=pairedKey",
        )

        val result = repository.connect(service = service)
        if (result is AndroidConnectResult.Rejected) {
            val message = result.message
            repository.closeConnection(service)
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
        val connectedService = repository.connectedServices.value.firstOrNull {
            it.host == service.host && it.port == service.port &&
                it.appBundleID == service.appBundleID && it.appVariant == service.appVariant
        } ?: service
        connectedMac = connectedService
        autoSelectedServiceID = null
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
        cancelSearchTimeout()
        servicesJob.cancel()
        connectionsJob.cancel()
        discoveryErrorJob.cancel()
        discoveryPreconditionJob.cancel()
        pairingPromptJob.cancel()
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
        val signature = services.joinToString("|") {
            "${it.name}@${it.host}:${it.port}:${it.macID.orEmpty()}:${it.appBundleID.orEmpty()}:${it.appVariant.orEmpty()}"
        }
        if (signature == lastServicesDiagnosticSignature) {
            return
        }
        lastServicesDiagnosticSignature = signature
        val message = if (services.isEmpty()) {
            "No Mac services discovered."
        } else {
            services.joinToString { service ->
                buildString {
                    append("${service.name}@${service.host}:${service.port}")
                    service.macID?.takeIf { it.isNotBlank() }?.let { append(" macID=$it") }
                    service.appVariant?.takeIf { it.isNotBlank() }?.let { append(" appVariant=$it") }
                    service.appBundleID?.takeIf { it.isNotBlank() }?.let { append(" appBundleID=$it") }
                }
            }
        }
        recordDiagnostic("discovery.services", message)
    }

    private fun effectiveService(): MacService? =
        _uiState.value.selectedMac ?: manualService(_uiState.value.manualHost, _uiState.value.manualPort)

    private fun autoConnectTarget(
        services: List<MacService>,
        current: AndroidComposerUiState,
        selected: MacService?,
    ): MacService? {
        if (connectedMac != null ||
            current.isBusy ||
            current.connectionStatus == AndroidConnectionStatus.Connecting ||
            current.connectionStatus == AndroidConnectionStatus.Connected ||
            (selected != null && selected.id != autoSelectedServiceID)
        ) {
            return null
        }

        val trustedServices = services.filter { service ->
            service.id !in autoConnectAttemptedServiceIDs && repository.isPaired(service)
        }
        return trustedServices.singleOrNull()
    }

    private fun autoSelectTarget(
        services: List<MacService>,
        current: AndroidComposerUiState,
    ): MacService? {
        if (connectedMac != null ||
            current.isBusy ||
            current.connectionStatus == AndroidConnectionStatus.Connecting ||
            current.connectionStatus == AndroidConnectionStatus.Connected
        ) {
            return null
        }

        return services.singleOrNull()
    }

    private fun connectingStatusText(service: MacService): String {
        if (service.isManualMac()) {
            return "正在连接到手动输入的设备"
        }
        return "正在连接到 ${service.name}"
    }

    private fun connectionFailureMessage(service: MacService, rawMessage: String): String {
        if (!service.isManualMac()) {
            return rawMessage
        }
        return "无法连接到手动输入的设备。请确认连接管理里的设备地址是当前这台设备的局域网地址。"
    }

    private val AndroidDiscoveryPrecondition.diagnosticMessage: String
        get() = when (this) {
            AndroidDiscoveryPrecondition.Available -> "Network can support local discovery."
            AndroidDiscoveryPrecondition.NoNetwork -> "No active network; Mac discovery cannot run."
            AndroidDiscoveryPrecondition.NotLocalNetwork -> "Active network is not Wi-Fi or Ethernet; Mac discovery may not reach the LAN."
        }

    private fun MacService.isManualMac(): Boolean = name == "手动输入的设备"

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
            connectionStatus != AndroidConnectionStatus.Connected
        val connected = connectionStatus == AndroidConnectionStatus.Connected
        return copy(
            canSend = CarrierPayloadPolicy.canSend(text) && connected && sendState != AndroidSendState.Sending && !isBusy,
            canSaveDraft = CarrierPayloadPolicy.canSend(text),
            canUndo = textHistory.canUndo,
            canRedo = textHistory.canRedo,
            canConnect = canConnect,
        )
    }

}
