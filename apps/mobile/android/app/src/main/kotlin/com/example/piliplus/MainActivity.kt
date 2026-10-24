package com.example.piliplus

import android.content.Intent
import android.content.res.Configuration
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.SystemClock
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private var sharedVideoChannel: MethodChannel? = null
    private var pendingSharedVideo: Map<String, String>? = null
    private var localNetworkPermissionResult: MethodChannel.Result? = null
    private var remoteVolumeEnabled = false
    private var remoteVolumeChannel: MethodChannel? = null
    private var remoteMediaSession: MediaSession? = null
    private var remoteVolumeProvider: VolumeProvider? = null
    private var lastVolumeKeyAt = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedVideoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.biliremote/shared_video").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingShare" -> result.success(pendingSharedVideo)
                    "acknowledgeShare" -> {
                        if (pendingSharedVideo?.get("id") == call.arguments) pendingSharedVideo = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        remoteVolumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.biliremote/remote_volume").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "updateSession") {
                    updateRemoteVolumeSession(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    result.success(null)
                } else if (call.method == "requestLocalNetwork") {
                    val permission = "android.permission.ACCESS_LOCAL_NETWORK"
                    if (Build.VERSION.SDK_INT < 37 || checkSelfPermission(permission) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else if (localNetworkPermissionResult != null) {
                        result.error("PERMISSION_PENDING", "请先处理局域网权限提示", null)
                    } else {
                        localNetworkPermissionResult = result
                        requestPermissions(arrayOf(permission), 9837)
                    }
                } else result.notImplemented()
            }
        }
    }

    private fun receiveSharedVideo(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.take(16_384)
            ?.takeIf { it.isNotBlank() } ?: return
        val share = mapOf("id" to SystemClock.elapsedRealtimeNanos().toString(), "text" to text)
        pendingSharedVideo = share
        sharedVideoChannel?.invokeMethod("shareReceived", share)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveSharedVideo(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9837) {
            localNetworkPermissionResult?.success(grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
            localNetworkPermissionResult = null
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (remoteVolumeEnabled && (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                val now = SystemClock.uptimeMillis()
                // A held key adjusts at most once per 180 ms; individual taps remain responsive.
                if (event.repeatCount == 0 || now - lastVolumeKeyAt >= 180) {
                    lastVolumeKeyAt = now
                    sendRemoteControlCommand("adjustVolume", if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) 1 else -1)
                }
            }
            return true
        }
        if (remoteVolumeEnabled) {
            val action = when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_MUTE -> "toggleMute"
                KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
                KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_HEADSETHOOK -> "togglePlayback"
                else -> null
            }
            if (action != null) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    sendRemoteControlCommand(action)
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun sendRemoteControlCommand(method: String, value: Int? = null) {
        runOnUiThread {
            if (remoteVolumeEnabled) remoteVolumeChannel?.invokeMethod(method, value)
        }
    }

    private fun updateRemoteVolumeSession(data: Map<*, *>) {
        // Keep consuming foreground keys while reconnecting, so they cannot change phone audio.
        remoteVolumeEnabled = data["enabled"] == true
        if (!remoteVolumeEnabled || data["available"] != true) {
            releaseRemoteVolumeSession()
            return
        }
        val volume = (data["volume"] as? Number)?.toInt()?.coerceIn(0, 100) ?: 0
        if (remoteMediaSession == null) {
            val provider = object : VolumeProvider(VolumeProvider.VOLUME_CONTROL_ABSOLUTE, 100, volume) {
                override fun onAdjustVolume(direction: Int) {
                    if (direction == AudioManager.ADJUST_RAISE || direction == AudioManager.ADJUST_LOWER) {
                        runOnUiThread {
                            val now = SystemClock.uptimeMillis()
                            if (now - lastVolumeKeyAt >= 180) {
                                lastVolumeKeyAt = now
                                sendRemoteControlCommand("adjustVolume", direction)
                            }
                        }
                    }
                }

                override fun onSetVolumeTo(volume: Int) {
                    sendRemoteControlCommand("setVolume", volume.coerceIn(0, 100))
                }
            }
            remoteVolumeProvider = provider
            remoteMediaSession = MediaSession(this, "Bili Remote TV").apply {
                setCallback(object : MediaSession.Callback() {
                    override fun onPlay() {
                        sendRemoteControlCommand("play")
                    }

                    override fun onPause() {
                        sendRemoteControlCommand("pause")
                    }
                })
                setPlaybackToRemote(provider)
                isActive = true
            }
        }
        remoteVolumeProvider?.setCurrentVolume(volume)
        val playing = data["playing"] == true
        remoteMediaSession?.setPlaybackState(PlaybackState.Builder()
            .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE)
            .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (playing) 1f else 0f)
            .build())
        remoteMediaSession?.setMetadata(MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, data["title"] as? String ?: "电视播放")
            .putString(MediaMetadata.METADATA_KEY_ARTIST, data["deviceName"] as? String ?: "电视")
            .build())
    }

    private fun releaseRemoteVolumeSession() {
        remoteMediaSession?.release()
        remoteMediaSession = null
        remoteVolumeProvider = null
    }

    override fun onDestroy() {
        remoteVolumeEnabled = false
        releaseRemoteVolumeSession()
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) receiveSharedVideo(intent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }
}
