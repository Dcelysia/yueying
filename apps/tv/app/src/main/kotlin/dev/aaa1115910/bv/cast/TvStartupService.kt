package dev.aaa1115910.bv.cast

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import dev.aaa1115910.bv.activities.MainActivity
import dev.aaa1115910.bv.util.Prefs

/** System binding can recover the process after vendor standby cleanup. No notifications are read. */
class TvStartupService : NotificationListenerService() {
    private val handler = Handler(Looper.getMainLooper())
    private var observingAdb = false
    private val adbObserver = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) = ensureAdbEnabled(this@TvStartupService)
    }
    private val openAfterBoot = Runnable { openAppOncePerBoot(this) }

    override fun onListenerConnected() {
        super.onListenerConnected()
        if (!observingAdb) {
            contentResolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ADB_ENABLED), false, adbObserver)
            observingAdb = true
        }
        ensureAdbEnabled(this)
        if (Prefs.openAppOnBoot) {
            runCatching { CastReceiverService.start(applicationContext) }
                .onFailure { Log.w(TAG, "System denied receiver recovery", it) }
        }
        handler.removeCallbacks(openAfterBoot)
        handler.postDelayed(openAfterBoot, 1_500)
        Log.i(TAG, "Startup recovery connected; autoOpen=${Prefs.openAppOnBoot}, keepAdb=${Prefs.keepAdbEnabled}")
    }

    override fun onListenerDisconnected() {
        stopObservingAdb()
        super.onListenerDisconnected()
        requestRecoveryBinding(this)
    }

    override fun onDestroy() {
        stopObservingAdb()
        super.onDestroy()
    }

    private fun stopObservingAdb() {
        handler.removeCallbacks(openAfterBoot)
        if (observingAdb) {
            contentResolver.unregisterContentObserver(adbObserver)
            observingAdb = false
        }
    }

    companion object {
        private const val TAG = "TvStartup"
        private const val BOOT_LAUNCH_WINDOW_MS = 180_000L

        fun ensureAdbEnabled(context: Context) {
            if (!Prefs.keepAdbEnabled) return
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) return
            runCatching {
                if (Settings.Global.getInt(context.contentResolver, Settings.Global.ADB_ENABLED, 0) == 0) {
                    if (Settings.Global.putInt(context.contentResolver, Settings.Global.ADB_ENABLED, 1)) {
                        Log.i(TAG, "Restored ADB setting; network port remains controlled by the firmware")
                    } else {
                        Log.w(TAG, "System refused ADB setting update")
                    }
                }
            }.onFailure { Log.w(TAG, "Could not restore ADB setting", it) }
        }

        fun requestRecoveryBinding(context: Context) {
            if (!Prefs.openAppOnBoot && !Prefs.keepAdbEnabled) return
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            if (!NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)) return
            runCatching { NotificationListenerService.requestRebind(ComponentName(context, TvStartupService::class.java)) }
                .onFailure { Log.w(TAG, "Could not request startup recovery binding", it) }
        }

        fun rememberCurrentBoot(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            val bootCount = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
            if (bootCount >= 0 && Prefs.startupHandledBootCount != bootCount) {
                Prefs.startupHandledBootCount = bootCount
            }
        }

        fun openAppOncePerBoot(context: Context, fromBootBroadcast: Boolean = false) {
            if (!Prefs.openAppOnBoot) return
            val bootCount = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1) else -1
            if (bootCount >= 0 && Prefs.startupHandledBootCount == bootCount) return
            // A late permission grant or a standby rebind must not take over Xiaomi Home.
            if (!fromBootBroadcast && (bootCount < 0 || SystemClock.elapsedRealtime() > BOOT_LAUNCH_WINDOW_MS)) {
                rememberCurrentBoot(context)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
                Log.w(TAG, "Boot launch needs background activity permission")
                return
            }
            runCatching {
                context.startActivity(Intent(context, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                ))
                rememberCurrentBoot(context)
                Log.i(TAG, "Requested app launch after boot; stock Home remains unchanged")
            }.onFailure { Log.w(TAG, "System denied boot activity launch", it) }
        }
    }
}
