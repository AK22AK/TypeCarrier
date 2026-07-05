package org.typecarrier.android.transport

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper

data class MacService(
    val name: String,
    val host: String,
    val port: Int,
    val macID: String? = null,
    val appBundleID: String? = null,
    val appVariant: String? = null,
) {
    val id: String = discoveryIdentity()

    private fun discoveryIdentity(): String {
        val normalizedMacID = macID?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedMacID == null) {
            return "$name@$host:$port"
        }

        return buildList {
            add("macID=$normalizedMacID")
            appBundleID?.trim()?.takeIf { it.isNotEmpty() }?.let { add("appBundleID=$it") }
            appVariant?.trim()?.takeIf { it.isNotEmpty() }?.let { add("appVariant=$it") }
        }.joinToString("|")
    }
}

class MacDiscovery(
    context: Context,
    private val onServicesChanged: (List<MacService>) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val services = linkedMapOf<String, MacService>()
    private val serviceIDsByDiscoveryName = linkedMapOf<String, String>()
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val resolutionQueue = MacDiscoveryResolutionQueue<NsdServiceInfo> { it.serviceName }
    private val recovery = NsdServiceRecovery()
    private val resolveRetryPolicy = NsdResolveRetryPolicy()
    private var scheduledRetry: Runnable? = null

    fun start() {
        if (discoveryListener != null) {
            return
        }
        cancelScheduledRetry()

        multicastLock = wifiManager?.createMulticastLock("typecarrier-mdns")?.apply {
            setReferenceCounted(false)
            acquire()
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                recovery.started()
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (MacDiscoveryServiceType.matches(serviceInfo.serviceType)) {
                    resolutionQueue.enqueue(serviceInfo)?.let(::resolve)
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                resolutionQueue.removePending(serviceInfo.serviceName)
                resolveRetryPolicy.clear(serviceInfo.serviceName)
                val serviceID = serviceIDsByDiscoveryName.remove(serviceInfo.serviceName)
                if (serviceID != null) {
                    services.remove(serviceID)
                    publishServices()
                }
            }

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                onError("发现服务失败：$errorCode")
                stop(clearsScheduledRetry = false)
                scheduleRestartAfterStartFailure()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                onError("停止发现失败：$errorCode")
            }
        }

        discoveryListener = listener
        nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stop() {
        stop(clearsScheduledRetry = true)
    }

    private fun stop(clearsScheduledRetry: Boolean) {
        if (clearsScheduledRetry) {
            cancelScheduledRetry()
        }
        val listener = discoveryListener ?: return
        runCatching { nsdManager.stopServiceDiscovery(listener) }
        discoveryListener = null
        resolutionQueue.clear()
        resolveRetryPolicy.clearAll()
        multicastLock?.release()
        multicastLock = null
        services.clear()
        serviceIDsByDiscoveryName.clear()
        publishServices()
    }

    private fun scheduleRestartAfterStartFailure() {
        val delayMillis = recovery.failed()
        val retry = Runnable {
            scheduledRetry = null
            if (recovery.shouldRunScheduledRetry()) {
                start()
            }
        }
        scheduledRetry = retry
        mainHandler.postDelayed(retry, delayMillis)
    }

    private fun cancelScheduledRetry() {
        scheduledRetry?.let(mainHandler::removeCallbacks)
        scheduledRetry = null
        recovery.userRestarted()
    }

    private fun resolve(serviceInfo: NsdServiceInfo) {
        nsdManager.resolveService(
            serviceInfo,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    onError("解析服务失败：$errorCode")
                    scheduleResolveRetryIfNeeded(serviceInfo)
                    resolveNextPendingService()
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    val host = serviceInfo.host?.hostAddress
                    if (host == null) {
                        onError("解析服务缺少地址：${serviceInfo.serviceName}")
                        resolveNextPendingService()
                        return
                    }
                    val androidPort = serviceInfo.attributes["androidPort"]
                        ?.toString(Charsets.UTF_8)
                        ?.toIntOrNull()
                        ?: run {
                            val keys = serviceInfo.attributes.keys.sorted().joinToString()
                            onError("解析服务缺少 Android 端口：${serviceInfo.serviceName} txtKeys=[$keys]")
                            resolveNextPendingService()
                            return
                        }
                    val macName = serviceInfo.attributes["macName"]
                        ?.toString(Charsets.UTF_8)
                        ?.takeIf { it.isNotBlank() }
                    val service = MacService(
                        name = macName ?: serviceInfo.serviceName,
                        host = host,
                        port = androidPort,
                        macID = serviceInfo.attributes["macID"]?.toString(Charsets.UTF_8)?.takeIf { it.isNotBlank() },
                        appBundleID = serviceInfo.attributes["appBundleID"]?.toString(Charsets.UTF_8)?.takeIf { it.isNotBlank() },
                        appVariant = serviceInfo.attributes["appVariant"]?.toString(Charsets.UTF_8)?.takeIf { it.isNotBlank() },
                    )
                    services[service.id] = service
                    serviceIDsByDiscoveryName[serviceInfo.serviceName] = service.id
                    resolveRetryPolicy.clear(serviceInfo.serviceName)
                    publishServices()
                    resolveNextPendingService()
                }
            },
        )
    }

    private fun scheduleResolveRetryIfNeeded(serviceInfo: NsdServiceInfo) {
        val delayMillis = resolveRetryPolicy.failed(serviceInfo.serviceName) ?: return
        mainHandler.postDelayed(
            {
                if (discoveryListener != null) {
                    resolutionQueue.enqueue(serviceInfo)?.let(::resolve)
                }
            },
            delayMillis,
        )
    }

    private fun resolveNextPendingService() {
        resolutionQueue.finishCurrent()?.let(::resolve)
    }

    private fun publishServices() {
        val snapshot = services.values.sortedBy { it.name }
        mainHandler.post {
            onServicesChanged(snapshot)
        }
    }

    private companion object {
        const val serviceType = MacDiscoveryServiceType.value
    }
}
