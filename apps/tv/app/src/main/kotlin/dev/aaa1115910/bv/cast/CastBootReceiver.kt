package dev.aaa1115910.bv.cast

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.aaa1115910.bv.util.Prefs
import io.github.oshai.kotlinlogging.KotlinLogging

/** Start after unlock, when the existing pairing and Bilibili credentials are accessible. */
class CastBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        try {
            if (Prefs.openAppOnBoot) CastReceiverService.start(context.applicationContext)
        } catch (exception: IllegalStateException) {
            // A vendor may restrict autostart; opening the home activity retries the service.
            KotlinLogging.logger("CastBootReceiver").warn(exception) { "System denied cast receiver autostart" }
        }
        TvStartupService.ensureAdbEnabled(context)
        TvStartupService.requestRecoveryBinding(context)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            TvStartupService.openAppOncePerBoot(context, fromBootBroadcast = true)
        } else {
            // Updating the APK must not be mistaken for a new boot.
            TvStartupService.rememberCurrentBoot(context)
        }
    }
}
