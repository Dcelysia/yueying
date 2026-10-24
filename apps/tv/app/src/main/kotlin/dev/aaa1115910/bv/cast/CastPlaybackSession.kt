package dev.aaa1115910.bv.cast

@kotlinx.serialization.Serializable
data class CastQueueItem(
    val aid: Long,
    val cid: Long,
    val title: String,
    val epid: Int? = null,
    val seasonId: Int? = null
)

/** Optional fields let a phone change one setting without overwriting the others. */
@kotlinx.serialization.Serializable
data class CastDanmakuSettings(
    val scale: Float? = null,
    val area: Float? = null,
    val opacity: Float? = null,
    val density: Float? = null,
    val types: Set<String>? = null
) {
    fun validate() {
        require(scale != null || area != null || opacity != null || density != null || types != null) { "缺少弹幕设置" }
        scale?.let { require(it.isFinite() && it in 0.5f..4f) { "弹幕字号超出范围" } }
        area?.let { require(it.isFinite() && it in 0.1f..1f) { "弹幕显示区域超出范围" } }
        opacity?.let { require(it.isFinite() && it in 0.1f..1f) { "弹幕不透明度超出范围" } }
        density?.let { require(it.isFinite() && it in 0.2f..1f) { "弹幕密度超出范围" } }
        types?.let { require(it.all { type -> type in setOf("rolling", "top", "bottom") }) { "弹幕类型无效" } }
    }
}

data class CastPlaybackIdentity(val remoteSessionId: String?, val aid: Long, val cid: Long, val epid: Int?)

@kotlinx.serialization.Serializable
data class CastSponsorSegment(
    val id: String,
    val category: String,
    val startMs: Long,
    val endMs: Long
)

data class CastPlaybackSnapshot(
    val remoteSessionId: String? = null,
    val state: CastTransportState = CastTransportState.STOPPED,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val speed: Float = 1f,
    val aid: Long = 0L,
    val cid: Long = 0L,
    val epid: Int? = null,
    val seasonId: Int = 0,
    val roomId: Long = 0L,
    val title: String = "",
    val qualityId: Int = 0,
    val availableQuality: Map<Int, String> = emptyMap(),
    val volume: Int = 100,
    val volumeMode: String = "unavailable",
    val queue: List<CastQueueItem> = emptyList(),
    val errorMessage: String? = null,
    val danmakuEnabled: Boolean = false,
    val danmakuSettings: CastDanmakuSettings? = null,
    val sponsorSkipMode: String? = null,
    val sponsorSegment: CastSponsorSegment? = null,
    val sponsorSkipNotice: String? = null
)

enum class CastTransportState(val dlnaName: String) {
    STOPPED("STOPPED"),
    PLAYING("PLAYING"),
    PAUSED("PAUSED_PLAYBACK"),
    TRANSITIONING("TRANSITIONING")
}

interface CastPlaybackSession {
    fun play()
    fun pause()
    fun stop()
    fun seekTo(positionMs: Long)
    fun setSpeed(speed: Float)
    fun setQuality(qualityId: Int)
    fun setDanmakuEnabled(enabled: Boolean)
    fun updateDanmakuSettings(settings: CastDanmakuSettings) {
        throw UnsupportedOperationException("此播放器不支持弹幕样式设置")
    }
    fun skipSponsorSegment(segmentId: String) { throw UnsupportedOperationException("此播放器不支持片段跳过") }
    fun dismissSponsorSegment(segmentId: String) { throw UnsupportedOperationException("此播放器不支持片段跳过") }
    suspend fun setSponsorSkipMode(mode: String) { throw UnsupportedOperationException("此播放器不支持片段跳过设置") }
    fun setVolume(volume: Int) { throw UnsupportedOperationException("此播放器不支持音量控制") }
    fun adjustVolume(direction: Int) { setVolume((snapshot().volume + direction * 5).coerceIn(0, 100)) }
    fun playItem(item: CastQueueItem) { throw UnsupportedOperationException("此播放器不支持选集") }
    fun identity(): CastPlaybackIdentity = snapshot().let { CastPlaybackIdentity(it.remoteSessionId, it.aid, it.cid, it.epid) }
    fun snapshot(): CastPlaybackSnapshot
}

object CastPlaybackSessionRegistry {
    @Volatile
    private var session: CastPlaybackSession? = null

    fun register(session: CastPlaybackSession) {
        this.session = session
    }

    fun unregister(session: CastPlaybackSession) {
        if (this.session === session) {
            this.session = null
        }
    }

    fun current(): CastPlaybackSession? = session

    fun pauseCurrent() {
        session?.pause()
    }
}
