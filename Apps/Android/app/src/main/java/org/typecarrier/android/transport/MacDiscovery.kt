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
) {
    val id: String = macID ?: "$name@$host:$port"
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

    fun start() {
        if (discoveryListener != null) {
            return
        }

        multicastLock = wifiManager?.createMulticastLock("typecarrier-mdns")?.apply {
            setReferenceCounted(false)
            acquire()
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceType == serviceType) {
                    resolutionQueue.enqueue(serviceInfo)?.let(::resolve)
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                resolutionQueue.removePending(serviceInfo.serviceName)
                val serviceID = serviceIDsByDiscoveryName.remove(serviceInfo.serviceName)
                if (serviceID != null) {
                    services.remove(serviceID)
                    publishServices()
                }
            }

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                onError("发现服务失败：$errorCode")
                stop()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                onError("停止发现失败：$errorCode")
            }
        }

        discoveryListener = listener
        nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stop() {
        val listener = discoveryListener ?: return
        runCatching { nsdManager.stopServiceDiscovery(listener) }
        discoveryListener = null
        resolutionQueue.clear()
        multicastLock?.release()
        multicastLock = null
        services.clear()
        serviceIDsByDiscoveryName.clear()
        publishServices()
    }

    private fun resolve(serviceInfo: NsdServiceInfo) {
        nsdManager.resolveService(
            serviceInfo,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    onError("解析服务失败：$errorCode")
                    resolveNextPendingService()
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    val host = serviceInfo.host?.hostAddress
                    if (host == null) {
                        resolveNextPendingService()
                        return
                    }
                    val androidPort = serviceInfo.attributes["androidPort"]
                        ?.toString(Charsets.UTF_8)
                        ?.toIntOrNull()
                        ?: run {
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
                    )
                    services[service.id] = service
                    serviceIDsByDiscoveryName[serviceInfo.serviceName] = service.id
                    publishServices()
                    resolveNextPendingService()
                }
            },
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
        const val serviceType = "_typecarrier._tcp."
    }
}
