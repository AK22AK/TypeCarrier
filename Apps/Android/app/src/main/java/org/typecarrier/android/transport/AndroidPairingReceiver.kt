package org.typecarrier.android.transport

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import java.io.Closeable
import java.io.EOFException
import java.net.ServerSocket
import java.net.Socket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.typecarrier.android.protocol.AndroidBridgeResponseStatus
import org.typecarrier.android.protocol.AndroidPairingAssociationResponse
import org.typecarrier.android.protocol.AndroidTrustToken
import org.typecarrier.android.protocol.CarrierJson
import org.typecarrier.android.protocol.CarrierWireFrame

class AndroidPairingReceiver(
    context: Context,
    private val deviceID: () -> String,
    private val deviceName: () -> String,
    private val localPairingCode: () -> String,
    private val onAssociated: (AssociatedMac) -> Unit,
    private val onError: (String) -> Unit,
) : Closeable {
    private val appContext = context.applicationContext
    private val nsdManager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val registrationRecovery = NsdServiceRecovery()
    private var serverSocket: ServerSocket? = null
    private var acceptJob: Job? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var scheduledRegistrationRetry: Runnable? = null

    fun start() {
        if (serverSocket != null) {
            return
        }
        cancelScheduledRegistrationRetry()

        runCatching {
            val nextSocket = ServerSocket(0)
            serverSocket = nextSocket
            registerService(nextSocket.localPort)
            acceptJob = scope.launch {
                acceptLoop(nextSocket)
            }
        }.onFailure { error ->
            onError(error.localizedMessage ?: "启动 Android 匹配服务失败")
            close()
        }
    }

    override fun close() {
        close(clearsScheduledRetry = true)
    }

    private fun close(clearsScheduledRetry: Boolean) {
        if (clearsScheduledRetry) {
            cancelScheduledRegistrationRetry()
        }
        acceptJob?.cancel()
        acceptJob = null
        runCatching { serverSocket?.close() }
        serverSocket = null
        registrationListener?.let { listener ->
            runCatching { nsdManager.unregisterService(listener) }
        }
        registrationListener = null
    }

    fun dispose() {
        close()
        scope.cancel()
    }

    private suspend fun acceptLoop(socket: ServerSocket) {
        while (scope.isActive && !socket.isClosed) {
            val connection = runCatching { socket.accept() }.getOrNull() ?: break
            scope.launch {
                handle(connection)
            }
        }
    }

    private suspend fun handle(socket: Socket) {
        withContext(Dispatchers.IO) {
            socket.use { activeSocket ->
                val payload = activeSocket.getInputStream().readFrame()
                val request = CarrierJson.decodePairingAssociationRequest(payload.decodeToString())
                val response = if (request.pairingCode == localPairingCode()) {
                    val trustToken = AndroidTrustToken.generate()
                    onAssociated(
                        AssociatedMac(
                            macID = request.macID,
                            macName = request.macName,
                            host = activeSocket.inetAddress.hostAddress ?: "",
                            trustToken = trustToken.rawValue,
                        ),
                    )
                    AndroidPairingAssociationResponse(
                        status = AndroidBridgeResponseStatus.Accepted,
                        message = "Associated.",
                        deviceID = deviceID(),
                        deviceName = deviceName(),
                        trustToken = trustToken.rawValue,
                    )
                } else {
                    AndroidPairingAssociationResponse(
                        status = AndroidBridgeResponseStatus.InvalidPairing,
                        message = "Invalid pairing code.",
                    )
                }
                activeSocket.getOutputStream().write(
                    CarrierWireFrame.encode(CarrierJson.encode(response).encodeToByteArray()),
                )
                activeSocket.getOutputStream().flush()
            }
        }
    }

    private fun registerService(port: Int) {
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = deviceName()
            serviceType = serviceTypeName
            this.port = port
            setAttribute("deviceID", deviceID())
            setAttribute("deviceName", deviceName())
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                registrationRecovery.started()
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                onError("Android 匹配服务发布失败：$errorCode")
                close(clearsScheduledRetry = false)
                scheduleRegistrationRestartAfterFailure()
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                onError("Android 匹配服务停止失败：$errorCode")
            }
        }
        registrationListener = listener
        nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun scheduleRegistrationRestartAfterFailure() {
        val delayMillis = registrationRecovery.failed()
        val retry = Runnable {
            scheduledRegistrationRetry = null
            if (registrationRecovery.shouldRunScheduledRetry()) {
                start()
            }
        }
        scheduledRegistrationRetry = retry
        mainHandler.postDelayed(retry, delayMillis)
    }

    private fun cancelScheduledRegistrationRetry() {
        scheduledRegistrationRetry?.let(mainHandler::removeCallbacks)
        scheduledRegistrationRetry = null
        registrationRecovery.userRestarted()
    }

    private fun java.io.InputStream.readFrame(): ByteArray {
        val header = readFully(4)
        val length = ((header[0].toInt() and 0xff) shl 24) or
            ((header[1].toInt() and 0xff) shl 16) or
            ((header[2].toInt() and 0xff) shl 8) or
            (header[3].toInt() and 0xff)
        if (length > CarrierWireFrame.maxPayloadSize) {
            error("请求过大：$length bytes")
        }
        return readFully(length)
    }

    private fun java.io.InputStream.readFully(size: Int): ByteArray {
        val bytes = ByteArray(size)
        var offset = 0
        while (offset < size) {
            val read = read(bytes, offset, size - offset)
            if (read < 0) {
                throw EOFException("连接已断开")
            }
            offset += read
        }
        return bytes
    }

    companion object {
        const val serviceTypeName = "_tcpair._tcp."
    }
}

data class AssociatedMac(
    val macID: String,
    val macName: String,
    val host: String,
    val trustToken: String,
)
