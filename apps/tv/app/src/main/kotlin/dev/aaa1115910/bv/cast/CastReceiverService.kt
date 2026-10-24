package dev.aaa1115910.bv.cast

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.Build
import android.content.pm.ServiceInfo
import dev.aaa1115910.bv.activities.MainActivity
import dev.aaa1115910.bv.cast.server.CastHttpServer
import dev.aaa1115910.bv.cast.server.CastNetworkUtil
import dev.aaa1115910.bv.cast.server.CastRequestLogger
import dev.aaa1115910.bv.cast.server.CastSsdpServer
import dev.aaa1115910.bv.util.Prefs
import io.github.oshai.kotlinlogging.KotlinLogging
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.util.UUID

class CastReceiverService : Service() {
    private val logger = KotlinLogging.logger("CastReceiverService")
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var multicastLock: WifiManager.MulticastLock? = null
    private var httpServer: CastHttpServer? = null
    private var ssdpServer: CastSsdpServer? = null
    private var connectivityManager: ConnectivityManager? = null
    private var discoveryAddresses = emptySet<String>()
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = refreshDiscoveryNetwork()
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = refreshDiscoveryNetwork()
        override fun onLost(network: Network) = refreshDiscoveryNetwork()
    }

    override fun onCreate() {
        super.onCreate()
        // Android stops an idle background service even while a paired phone still needs it.
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(NotificationChannel(
                RECEIVER_CHANNEL, "电视遥控", NotificationManager.IMPORTANCE_LOW
            ))
            Notification.Builder(this, RECEIVER_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Bili Remote TV 已准备好")
            .setContentText("手机连接已自动开启，同一局域网免配对连接")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setContentIntent(PendingIntent.getActivity(this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(RECEIVER_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(RECEIVER_NOTIFICATION_ID, notification)
        }
        val requestLogger = CastRequestLogger(applicationContext)
        val uuid = Prefs.castReceiverUuid.ifBlank {
            UUID.randomUUID().toString().also { Prefs.castReceiverUuid = it }
        }
        acquireMulticastLock()
        val playbackLauncher = CastPlaybackLauncher(applicationContext)
        httpServer = CastHttpServer(
            remotePlayback = dev.aaa1115910.bv.cast.remote.RemotePlaybackServer(
                uuid, dev.aaa1115910.bv.cast.remote.RemotePairingStore(applicationContext), playbackLauncher
            ),
            uuid = uuid,
            requestLogger = requestLogger,
            playbackLauncher = playbackLauncher,
            scope = scope
        )
        ssdpServer = CastSsdpServer(
            uuid = uuid,
            requestLogger = requestLogger,
            scope = scope
        )
        runCatching {
            httpServer?.start()
            ssdpServer?.start()
            watchDiscoveryNetwork()
            requestLogger.log("Cast receiver active addresses=${CastNetworkUtil.localIpv4Addresses()}")
        }.onFailure {
            logger.warn(it) { "Start cast receiver failed" }
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        connectivityManager?.let { manager ->
            runCatching { manager.unregisterNetworkCallback(networkCallback) }
        }
        connectivityManager = null
        ssdpServer?.stop()
        httpServer?.stop()
        ssdpServer = null
        httpServer = null
        multicastLock?.release()
        multicastLock = null
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun watchDiscoveryNetwork() {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET)
            .build()
        manager.registerNetworkCallback(request, networkCallback)
        connectivityManager = manager
    }

    private fun refreshDiscoveryNetwork() {
        val addresses = runCatching { CastNetworkUtil.localIpv4Addresses().toSet() }
            .getOrDefault(emptySet())
        if (addresses == discoveryAddresses) return
        discoveryAddresses = addresses
        // Rejoin multicast on the new interface without closing phone WebSocket connections.
        ssdpServer?.refreshNetwork()
    }

    private fun acquireMulticastLock() {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        multicastLock = wifiManager.createMulticastLock("NeoBV-CastReceiver").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    companion object {
        private const val RECEIVER_CHANNEL = "bili_remote_receiver"
        private const val RECEIVER_NOTIFICATION_ID = 9838

        fun start(context: Context) {
            val intent = Intent(context, CastReceiverService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CastReceiverService::class.java))
        }
    }
}

