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
) {
    val id: String = "$name@$host:$port"
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
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var resolving = false

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
                if (serviceInfo.serviceType == serviceType && !resolving) {
                    resolve(serviceInfo)
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                val keyPrefix = "${serviceInfo.serviceName}@"
                val key = services.keys.firstOrNull { it.startsWith(keyPrefix) }
                if (key != null) {
                    services.remove(key)
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
        resolving = false
        multicastLock?.release()
        multicastLock = null
        services.clear()
        publishServices()
    }

    private fun resolve(serviceInfo: NsdServiceInfo) {
        resolving = true
        nsdManager.resolveService(
            serviceInfo,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    resolving = false
                    onError("解析服务失败：$errorCode")
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    resolving = false
                    val host = serviceInfo.host?.hostAddress ?: return
                    val service = MacService(
                        name = serviceInfo.serviceName,
                        host = host,
                        port = serviceInfo.port,
                    )
                    services[service.id] = service
                    publishServices()
                }
            },
        )
    }

    private fun publishServices() {
        val snapshot = services.values.sortedBy { it.name }
        mainHandler.post {
            onServicesChanged(snapshot)
        }
    }

    private companion object {
        const val serviceType = "_typecarrier-json._tcp."
    }
}
