package org.typecarrier.android.viewmodel

import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.typecarrier.android.diagnostics.AndroidDiagnosticLogStore
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierPostPasteAction
import org.typecarrier.android.storage.AndroidRecordStore
import org.typecarrier.android.transport.AndroidCarrierRepository
import org.typecarrier.android.transport.AndroidConnectResult
import org.typecarrier.android.transport.AndroidPairingPrompt
import org.typecarrier.android.transport.AndroidDiscoveryPrecondition
import org.typecarrier.android.transport.MacService
import org.typecarrier.android.ui.connectionDisplayText

class AndroidComposerViewModelTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun saveDraftPersistsDraftClearsTextAndUpdatesBadge() = runBlocking {
        val viewModel = makeViewModel()

        viewModel.updateText("draft text")
        viewModel.saveDraft().join()

        assertEquals("", viewModel.uiState.value.text)
        assertEquals(1, viewModel.uiState.value.draftCount)
        assertFalse(viewModel.uiState.value.canSaveDraft)
    }

    @Test
    fun successfulSendRecordsHistoryAndClearsText() = runBlocking {
        val repository = FakeAndroidCarrierRepository()
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)
        viewModel.connect().join()

        viewModel.updateText("hello")
        viewModel.send().join()

        assertEquals("", viewModel.uiState.value.text)
        assertEquals(1, viewModel.uiState.value.outgoingHistory.size)
        assertEquals(repository.mac.name, viewModel.uiState.value.headerStatusText)
    }

    @Test
    fun sendWithReturnModePassesPostPasteActionToRepository() = runBlocking {
        val repository = FakeAndroidCarrierRepository()
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)
        viewModel.connect().join()

        viewModel.updateEnablesSendReturnGesture(true)
        viewModel.updateSendsReturnAfterPaste(true)
        viewModel.updateText("hello")
        viewModel.send().join()

        assertEquals(CarrierPostPasteAction.PressReturn, repository.lastPostPasteAction)
    }

    @Test
    fun disablingSendReturnModeResetsSelectedSendBehavior() {
        val viewModel = makeViewModel()

        viewModel.updateEnablesSendReturnGesture(true)
        viewModel.updateSendsReturnAfterPaste(true)
        viewModel.updateEnablesSendReturnGesture(false)

        assertFalse(viewModel.uiState.value.enablesSendReturnGesture)
        assertFalse(viewModel.uiState.value.sendsReturnAfterPaste)
    }

    @Test
    fun sendRefreshesTrustedConnectionBeforeWritingText() = runBlocking {
        val repository = FakeAndroidCarrierRepository().apply {
            requiresReconnectBeforeSend = true
        }
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)
        viewModel.connect().join()

        viewModel.updateText("hello")
        viewModel.send().join()

        assertEquals(2, repository.connectAttempts)
        assertEquals(1, repository.sendAttempts)
        assertEquals("", viewModel.uiState.value.text)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
    }

    @Test
    fun failedSendKeepsTextAndMarksFailure() = runBlocking {
        val repository = FakeAndroidCarrierRepository().apply {
            sendFailure = IllegalStateException("offline")
        }
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)
        viewModel.connect().join()

        viewModel.updateText("keep me")
        viewModel.send().join()

        assertEquals("keep me", viewModel.uiState.value.text)
        assertTrue(viewModel.uiState.value.sendState is AndroidSendState.Failed)
        assertEquals("offline", viewModel.uiState.value.connectionFailureMessage)
    }

    @Test
    fun selectingAnAlreadyConnectedTrustedMacKeepsConnection() {
        val repository = FakeAndroidCarrierRepository().apply {
            hasTrustToken = true
        }
        val viewModel = makeViewModel(repository = repository)

        viewModel.selectMac(repository.mac)

        assertFalse(viewModel.uiState.value.canConnect)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
    }

    @Test
    fun connectingStateNamesSelectedMacBeforeConnectionCompletes() = runBlocking {
        val connectGate = CompletableDeferred<Unit>()
        val repository = FakeAndroidCarrierRepository().apply {
            connectGateBeforeResponse = connectGate
        }
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)

        val connectJob = viewModel.connect()

        assertEquals(AndroidConnectionStatus.Connecting, viewModel.uiState.value.connectionStatus)
        assertEquals("正在连接到 Test Mac", viewModel.uiState.value.headerStatusText)

        connectGate.complete(Unit)
        connectJob.join()
    }

    @Test
    fun connectingStateNamesManualHostBeforeConnectionCompletes() = runBlocking {
        val connectGate = CompletableDeferred<Unit>()
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
            manualHost = "10.116.251.181"
            connectGateBeforeResponse = connectGate
        }
        val viewModel = makeViewModel(repository = repository)

        val connectJob = viewModel.connect()

        assertEquals(AndroidConnectionStatus.Connecting, viewModel.uiState.value.connectionStatus)
        assertEquals("正在连接到手动输入的设备", viewModel.uiState.value.headerStatusText)

        connectGate.complete(Unit)
        connectJob.join()
    }

    @Test
    fun manualConnectionFailureShowsUserFacingMessageAndKeepsRawDiagnostic() = runBlocking {
        val rawFailure = "failed to connect to /10.116.251.181 (port 17641) after 5000ms"
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
            manualHost = "10.116.251.181"
            connectFailure = IllegalStateException(rawFailure)
        }
        val viewModel = makeViewModel(repository = repository)

        viewModel.connect().join()

        assertEquals("连接失败", viewModel.uiState.value.headerStatusText)
        assertEquals(
            "无法连接到手动输入的设备。请确认连接管理里的设备地址是当前这台设备的局域网地址。",
            viewModel.uiState.value.connectionFailureMessage,
        )
        assertTrue(viewModel.exportDiagnosticsText().contains(rawFailure))
    }

    @Test
    fun acceptedPairingMarksMacTrusted() = runBlocking {
        val repository = FakeAndroidCarrierRepository()
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)

        viewModel.connect().join()

        assertTrue(repository.hasTrustToken)
        assertFalse(viewModel.uiState.value.canConnect)
    }

    @Test
    fun invalidSavedTrustTokenClearsTrustedMacAndAllowsRepairing() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
            nextConnectResult = AndroidConnectResult.Rejected("Invalid pairing code or trust token.", pairingRemoved = true)
        }
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)

        viewModel.connect().join()

        val rejectedState = viewModel.uiState.value
        assertFalse(repository.hasTrustToken)
        assertFalse(rejectedState.trustedMacs.any { it.id == repository.mac.id })
        assertTrue(rejectedState.canConnect)
        assertEquals("配对已失效，请重新配对。", rejectedState.connectionFailureMessage)

        repository.nextConnectResult = AndroidConnectResult.Connected
        viewModel.connect().join()

        assertEquals(true, repository.lastConnectWasPairing)
        assertTrue(repository.hasTrustToken)
    }

    @Test
    fun serviceDiscoveryChangesAreRecordedInDiagnostics() {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)

        repository.publishServices(listOf(repository.mac))

        assertTrue(viewModel.exportDiagnosticsText().contains("discovery.services"))
        assertTrue(viewModel.exportDiagnosticsText().contains("Test Mac@127.0.0.1:17641"))
    }

    @Test
    fun discoveryErrorsAreRecordedInDiagnostics() {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)

        repository.publishDiscoveryError("解析服务失败：3")

        assertTrue(viewModel.exportDiagnosticsText().contains("discovery.error"))
        assertTrue(viewModel.exportDiagnosticsText().contains("解析服务失败：3"))
    }

    @Test
    fun singleDiscoveredTrustedMacConnectsAutomatically() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
        }
        val viewModel = makeViewModel(repository = repository)

        repository.publishServices(listOf(repository.mac))

        assertEquals(1, repository.connectAttempts)
        assertEquals(false, repository.lastConnectWasPairing)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
        assertEquals(repository.mac, viewModel.uiState.value.selectedMac)
    }

    @Test
    fun singleDiscoveredUntrustedMacBecomesCurrentPairingTarget() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)

        repository.publishServices(listOf(repository.mac))

        assertEquals(repository.mac, viewModel.uiState.value.selectedMac)
        assertEquals(0, repository.connectAttempts)
        assertEquals(AndroidConnectionStatus.Idle, viewModel.uiState.value.connectionStatus)
        assertEquals(repository.mac.name, viewModel.uiState.value.headerStatusText)
        // Pairing happens on connect, so an unpaired Mac can be connected right away.
        assertTrue(viewModel.uiState.value.canConnect)

        viewModel.connect().join()

        assertEquals(1, repository.connectAttempts)
        assertEquals(true, repository.lastConnectWasPairing)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
        assertTrue(viewModel.exportDiagnosticsText().contains("discovery.autoSelected"))
    }

    @Test
    fun multipleDiscoveredTrustedMacsDoNotConnectAutomatically() {
        val secondMac = MacService(name = "Other Mac", host = "127.0.0.2", port = 17641, macID = "mac-2")
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
        }
        val viewModel = makeViewModel(repository = repository)

        repository.publishServices(listOf(repository.mac, secondMac))

        assertEquals(0, repository.connectAttempts)
        assertEquals(null, viewModel.uiState.value.selectedMac)
        assertEquals(AndroidConnectionStatus.Searching, viewModel.uiState.value.connectionStatus)
    }

    @Test
    fun trustedMacCanAutoConnectAfterUntrustedMacWasAutoSelected() {
        val trustedMac = MacService(name = "Trusted Mac", host = "127.0.0.2", port = 17641, macID = "mac-2")
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            trustedServices = listOf(trustedMac)
        }
        val viewModel = makeViewModel(repository = repository)

        repository.publishServices(listOf(repository.mac))

        assertEquals(repository.mac, viewModel.uiState.value.selectedMac)
        assertEquals(0, repository.connectAttempts)

        repository.publishServices(listOf(repository.mac, trustedMac))

        assertEquals(1, repository.connectAttempts)
        assertEquals(trustedMac, repository.lastConnectedService)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
        assertEquals(trustedMac, viewModel.uiState.value.selectedMac)
    }

    @Test
    fun startDoesNotExposeRememberedMacAsCurrentTargetWhenItIsNotDiscovered() {
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
        }
        val viewModel = makeViewModel(repository = repository)

        viewModel.start()

        assertEquals(0, repository.connectAttempts)
        assertEquals(null, repository.lastConnectWasPairing)
        assertEquals(listOf(repository.mac), viewModel.uiState.value.trustedMacs)
        assertEquals(emptyList<MacService>(), viewModel.uiState.value.services)
        assertEquals(null, viewModel.uiState.value.selectedMac)
        assertEquals(AndroidConnectionStatus.Searching, viewModel.uiState.value.connectionStatus)
        assertEquals("未发现设备", viewModel.uiState.value.headerStatusText)
        assertFalse(viewModel.uiState.value.canConnect)
    }

    @Test
    fun becomingActiveRefreshesDiscoveryWhenDisconnected() {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)

        viewModel.handleAppBecameActive()

        assertEquals(1, repository.refreshDiscoveryAttempts)
        assertEquals(AndroidConnectionStatus.Searching, viewModel.uiState.value.connectionStatus)
        assertEquals("正在查找设备", viewModel.uiState.value.headerStatusText)
        assertTrue(viewModel.exportDiagnosticsText().contains("app.foregroundDiscoveryRefresh"))
    }

    @Test
    fun becomingActiveReconnectsSelectedTrustedMac() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
        }
        val viewModel = makeViewModel(repository = repository)

        viewModel.selectMac(repository.mac)
        viewModel.handleAppBecameActive()

        assertEquals(1, repository.connectAttempts)
        assertEquals(false, repository.lastConnectWasPairing)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
        assertEquals(repository.mac.name, viewModel.uiState.value.headerStatusText)
        assertTrue(viewModel.exportDiagnosticsText().contains("app.foregroundTrustedReconnect"))
    }

    @Test
    fun becomingActiveKeepsConnectedMacWithoutRefreshingDiscovery() = runBlocking {
        val repository = FakeAndroidCarrierRepository().apply {
            hasTrustToken = true
        }
        val viewModel = makeViewModel(repository = repository)

        viewModel.selectMac(repository.mac)
        viewModel.connect().join()
        viewModel.handleAppBecameActive()

        assertEquals(0, repository.refreshDiscoveryAttempts)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
        assertEquals(repository.mac.name, viewModel.uiState.value.headerStatusText)
    }

    @Test
    fun automaticInvalidSavedTrustTokenShowsRepairingState() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList()).apply {
            hasTrustToken = true
            nextConnectResult = AndroidConnectResult.Rejected("Invalid pairing code or trust token.", pairingRemoved = true)
        }
        val viewModel = makeViewModel(repository = repository)

        viewModel.start()
        repository.publishServices(listOf(repository.mac))

        assertFalse(repository.hasTrustToken)
        assertEquals(AndroidConnectionStatus.Idle, viewModel.uiState.value.connectionStatus)
        assertEquals("连接失败", viewModel.uiState.value.headerStatusText)
        assertEquals("配对已失效，请重新配对。", viewModel.uiState.value.connectionFailureMessage)
    }

    @Test
    fun selectedTargetStaysSelectedWithoutSendingWhenDiscoveryDisappears() {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)

        viewModel.start()
        repository.publishServices(listOf(repository.mac))
        viewModel.selectMac(repository.mac)

        assertEquals(repository.mac, viewModel.uiState.value.selectedMac)
        assertTrue(viewModel.uiState.value.canConnect)

        repository.publishServices(emptyList())

        assertEquals(repository.mac, viewModel.uiState.value.selectedMac)
        assertFalse(viewModel.uiState.value.canSend)
        assertEquals(repository.mac.name, viewModel.uiState.value.headerStatusText)
    }

    @Test
    fun discoveryPreconditionUpdatesUiSelfCheck() {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)

        repository.publishDiscoveryPrecondition(AndroidDiscoveryPrecondition.NotLocalNetwork)

        assertEquals(AndroidDiscoveryPrecondition.NotLocalNetwork, viewModel.uiState.value.discoveryPrecondition)
        assertEquals(
            "当前网络无法发现局域网设备",
            AndroidConnectionSelfCheck.findings(viewModel.uiState.value).first().title,
        )
    }

    @Test
    fun connectedTargetStaysVisibleWhenDiscoveryListClears() = runBlocking {
        val repository = FakeAndroidCarrierRepository().apply {
            hasTrustToken = true
        }
        val viewModel = makeViewModel(repository = repository)

        viewModel.selectMac(repository.mac)
        viewModel.connect().join()
        repository.publishServices(emptyList())

        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
        assertEquals(repository.mac, viewModel.uiState.value.selectedMac)
        assertEquals(repository.mac.name, viewModel.uiState.value.headerStatusText)
        assertFalse(viewModel.uiState.value.canConnect)
    }

    @Test
    fun multipleConnectedMacsCanBeSelectedAndOneDisconnectDoesNotSwitchTarget() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)
        val second = MacService("Test Mac", "127.0.0.2", 17641, macID = "second")
        viewModel.selectMac(repository.mac)
        viewModel.connect().join()
        viewModel.selectMac(second)
        viewModel.connect().join()
        assertEquals(2, viewModel.uiState.value.connectedMacs.size)
        viewModel.updateText("to second")
        viewModel.send().join()
        assertEquals(second.id, repository.lastSendTarget?.id)
        viewModel.disconnectSelectedMac()
        viewModel.updateText("offline")
        assertEquals(second.id, viewModel.uiState.value.selectedMac?.id)
        assertFalse(viewModel.uiState.value.canSend)
        assertEquals(listOf(repository.mac), viewModel.uiState.value.connectedMacs)
        viewModel.selectMac(repository.mac)
        assertTrue(viewModel.uiState.value.canSend)
    }

    @Test
    fun secondReceiverAuthenticationFailureLeavesFirstConnectionUsable() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository)
        viewModel.selectMac(repository.mac)
        viewModel.connect().join()
        viewModel.updateText("hello")
        viewModel.refreshDiscovery()
        assertTrue(viewModel.uiState.value.canSend)
        val second = MacService("Other Mac", "127.0.0.2", 17641, macID = "second")
        viewModel.selectMac(second)
        repository.nextConnectResult = AndroidConnectResult.Rejected("invalid")
        viewModel.connect().join()
        assertEquals(listOf(repository.mac), viewModel.uiState.value.connectedMacs)
        assertEquals(second, viewModel.uiState.value.selectedMac)
        assertFalse(viewModel.uiState.value.canSend)
        viewModel.selectMac(repository.mac)
        assertTrue(viewModel.uiState.value.canSend)
    }

    @Test
    fun connectedReceiverRenameUpdatesHeaderWithoutSwitchingTarget() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val old = MacService("Old Mac", "host", 17641, macID = "stable")
        val viewModel = makeViewModel(repository)
        viewModel.selectMac(old)
        viewModel.connect().join()
        repository.publishConnectedServices(listOf(old.copy(name = "书房设备")))
        assertEquals(old.id, viewModel.uiState.value.selectedMac?.id)
        assertEquals("书房设备", viewModel.uiState.value.headerStatusText)
        assertEquals(AndroidConnectionStatus.Connected, viewModel.uiState.value.connectionStatus)
    }

    @Test
    fun searchStopsAfterTimeoutWhenNothingConnects() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository, searchTimeoutMillis = 50)

        viewModel.start()
        delay(200)

        val state = viewModel.uiState.value
        assertTrue(state.searchTimedOut)
        assertEquals(1, repository.stopDiscoveryAttempts)
        assertEquals(AndroidComposerViewModel.SEARCH_TIMED_OUT_TITLE, connectionDisplayText(state))
        assertEquals(AndroidComposerViewModel.SEARCH_TIMED_OUT_MESSAGE, state.connectionFailureMessage)
        assertTrue(viewModel.exportDiagnosticsText().contains("discovery.timeout"))
    }

    @Test
    fun searchKeepsRunningWhileConnected() = runBlocking {
        val repository = FakeAndroidCarrierRepository()
        val viewModel = makeViewModel(repository = repository, searchTimeoutMillis = 50)
        viewModel.selectMac(repository.mac)
        viewModel.connect().join()

        viewModel.start()
        delay(200)

        assertFalse(viewModel.uiState.value.searchTimedOut)
        assertEquals(0, repository.stopDiscoveryAttempts)
        viewModel.close()
    }

    @Test
    fun searchDoesNotReportNotFoundWhileComputersAreListed() = runBlocking {
        val repository = FakeAndroidCarrierRepository()
        val viewModel = makeViewModel(repository = repository, searchTimeoutMillis = 50)

        viewModel.start()
        delay(200)

        assertFalse(viewModel.uiState.value.searchTimedOut)
        assertEquals(0, repository.stopDiscoveryAttempts)
        viewModel.close()
    }

    @Test
    fun refreshAfterTimeoutSearchesAgain() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository, searchTimeoutMillis = 50)
        viewModel.start()
        delay(200)

        viewModel.refreshDiscovery()

        assertFalse(viewModel.uiState.value.searchTimedOut)
        assertEquals(AndroidConnectionStatus.Searching, viewModel.uiState.value.connectionStatus)
        assertEquals(1, repository.refreshDiscoveryAttempts)
    }

    @Test
    fun macPickerHoldsTheSearchOpenAndRestartsATimedOutSearch() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository, searchTimeoutMillis = 50)
        viewModel.start()
        delay(200)
        assertTrue(viewModel.uiState.value.searchTimedOut)

        viewModel.beginSearchHold()
        assertFalse(viewModel.uiState.value.searchTimedOut)
        delay(200)
        assertFalse(viewModel.uiState.value.searchTimedOut)

        viewModel.endSearchHold()
        delay(200)
        assertTrue(viewModel.uiState.value.searchTimedOut)
        viewModel.close()
    }

    @Test
    fun backgroundStopsDiscoveryAndForegroundStartsItAgain() = runBlocking {
        val repository = FakeAndroidCarrierRepository(emptyList())
        val viewModel = makeViewModel(repository = repository, searchTimeoutMillis = 50)
        viewModel.start()

        viewModel.handleAppEnteredBackground()
        delay(200)
        assertEquals(1, repository.stopDiscoveryAttempts)
        assertFalse("No timeout fires in background", viewModel.uiState.value.searchTimedOut)

        viewModel.handleAppBecameActive()
        assertEquals(2, repository.startDiscoveryAttempts)
        assertEquals(AndroidConnectionStatus.Searching, viewModel.uiState.value.connectionStatus)
        viewModel.close()
    }

    private fun makeViewModel(
        repository: FakeAndroidCarrierRepository = FakeAndroidCarrierRepository(),
        searchTimeoutMillis: Long = AndroidComposerViewModel.SEARCH_TIMEOUT_MILLIS,
    ): AndroidComposerViewModel {
        val recordsFile = temporaryFolder.newFile("records.json").also(File::delete)
        val diagnosticsFile = temporaryFolder.newFile("diagnostics.jsonl").also(File::delete)
        return AndroidComposerViewModel(
            repository = repository,
            recordStore = AndroidRecordStore(file = recordsFile),
            diagnosticLogStore = AndroidDiagnosticLogStore(file = diagnosticsFile),
            scope = CoroutineScope(Dispatchers.Unconfined),
            searchTimeoutMillis = searchTimeoutMillis,
            resumeSearchTimeoutMillis = searchTimeoutMillis,
        )
    }
}

private class FakeAndroidCarrierRepository(
    initialServices: List<MacService>? = null,
) : AndroidCarrierRepository {
    val mac = MacService(name = "Test Mac", host = "127.0.0.1", port = 17641)
    private val mutableServices = MutableStateFlow(initialServices ?: listOf(mac))
    private val mutableDiscoveryErrors = MutableStateFlow<String?>(null)
    private val mutableDiscoveryPrecondition = MutableStateFlow(AndroidDiscoveryPrecondition.Available)
    private val mutableConnectedServices = MutableStateFlow<List<MacService>>(emptyList())
    override val connectedServices: StateFlow<List<MacService>> = mutableConnectedServices
    override val services: StateFlow<List<MacService>> = mutableServices
    override val discoveryError: StateFlow<String?> = mutableDiscoveryErrors
    override val discoveryPrecondition: StateFlow<AndroidDiscoveryPrecondition> = mutableDiscoveryPrecondition
    override val deviceName: String = "Android Test"
    override val trustedMacs: List<MacService>
        get() = if (hasTrustToken) listOf(mac) else emptyList()
    override var manualHost: String = ""
    override var manualPort: String = "17641"
    override var senderDisplayName: String = ""
    override var launchesIntoInputMode: Boolean = true
    override var enablesSendReturnGesture: Boolean = false
    var hasTrustToken = false
    var trustedServices: List<MacService>? = null
    var sendFailure: Throwable? = null
    var connectFailure: Throwable? = null
    var requiresReconnectBeforeSend = false
    var lastPostPasteAction: CarrierPostPasteAction? = null
    var lastSendTarget: MacService? = null
    var lastConnectedService: MacService? = null
    var lastConnectWasPairing: Boolean? = null
    val mutablePairingPrompt = MutableStateFlow<AndroidPairingPrompt?>(null)
    override val pairingPrompt: StateFlow<AndroidPairingPrompt?> = mutablePairingPrompt
    var connectAttempts = 0
    var sendAttempts = 0
    var refreshDiscoveryAttempts = 0
    var connectGateBeforeResponse: CompletableDeferred<Unit>? = null
    var nextConnectResult: AndroidConnectResult = AndroidConnectResult.Connected

    fun publishServices(services: List<MacService>) {
        mutableServices.value = services
    }

    fun publishConnectedServices(services: List<MacService>) { mutableConnectedServices.value = services }

    fun publishDiscoveryError(message: String) {
        mutableDiscoveryErrors.value = message
    }

    fun publishDiscoveryPrecondition(precondition: AndroidDiscoveryPrecondition) {
        mutableDiscoveryPrecondition.value = precondition
    }

    var startDiscoveryAttempts = 0
    var stopDiscoveryAttempts = 0
    override fun startDiscovery() {
        startDiscoveryAttempts += 1
    }
    override fun stopDiscovery() {
        stopDiscoveryAttempts += 1
    }
    override fun refreshDiscovery() {
        refreshDiscoveryAttempts += 1
    }
    override fun isPaired(service: MacService): Boolean =
        trustedServices?.any { it.id == service.id } ?: hasTrustToken
    override fun forgetTrustedMac(service: MacService) {
        hasTrustToken = false
    }

    override suspend fun connect(service: MacService): AndroidConnectResult {
        connectFailure?.let { throw it }
        connectAttempts += 1
        lastConnectedService = service
        lastConnectWasPairing = !isPaired(service)
        connectGateBeforeResponse?.await()
        when (val result = nextConnectResult) {
            AndroidConnectResult.Connected -> {
                hasTrustToken = true
                mutableConnectedServices.value = (mutableConnectedServices.value + service).distinctBy { it.id }
            }
            is AndroidConnectResult.Rejected -> if (result.pairingRemoved) hasTrustToken = false
        }
        return nextConnectResult
    }

    override suspend fun sendText(
        service: MacService,
        text: String,
        senderDisplayName: String,
        postPasteAction: CarrierPostPasteAction?,
    ): CarrierDeliveryReceipt {
        sendAttempts += 1
        lastSendTarget = service
        lastPostPasteAction = postPasteAction
        if (requiresReconnectBeforeSend && connectAttempts < 2) {
            throw IllegalStateException("stale socket")
        }
        sendFailure?.let { throw it }
        return CarrierDeliveryReceipt(
            payloadID = "payload",
            receivedAt = "2026-06-01T00:00:00Z",
            pasteStatus = CarrierDeliveryReceipt.PasteStatus.Posted,
            detail = "设备已插入",
        )
    }

    override fun closeConnection(service: MacService?) {
        mutableConnectedServices.value = if (service == null) emptyList() else mutableConnectedServices.value.filter { it.id != service.id }
    }
    override fun close() = Unit
}
