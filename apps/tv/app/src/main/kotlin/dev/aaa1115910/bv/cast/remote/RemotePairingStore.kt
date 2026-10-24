package dev.aaa1115910.bv.cast.remote

import android.content.Context
import java.security.SecureRandom

/** Remembers client tokens for compatibility; home-network connections need no pairing. */
class RemotePairingStore(context: Context) {
    private val preferences = context.getSharedPreferences("remote_pairing", Context.MODE_PRIVATE)
    private val random = SecureRandom()
    @Synchronized
    fun registerClient(clientId: String): String {
        require(clientId.matches(Regex("[A-Za-z0-9_-]{8,80}"))) { "设备编号无效" }
        preferences.getString("device.$clientId", null)?.let { return it }
        val newToken = ByteArray(32).also(random::nextBytes).joinToString("") { "%02x".format(it) }
        preferences.edit().putString("device.$clientId", newToken).apply()
        return newToken
    }

}
