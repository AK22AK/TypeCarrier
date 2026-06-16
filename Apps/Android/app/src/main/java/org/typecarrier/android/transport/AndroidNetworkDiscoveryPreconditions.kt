package org.typecarrier.android.transport

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

object AndroidNetworkDiscoveryPreconditions {
    fun current(context: Context): AndroidDiscoveryPrecondition {
        val connectivityManager = context.applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return AndroidDiscoveryPrecondition.NoNetwork
        val activeNetwork = connectivityManager.activeNetwork
            ?: return AndroidDiscoveryPrecondition.NoNetwork
        val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
            ?: return AndroidDiscoveryPrecondition.NoNetwork

        return if (
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        ) {
            AndroidDiscoveryPrecondition.Available
        } else {
            AndroidDiscoveryPrecondition.NotLocalNetwork
        }
    }
}
