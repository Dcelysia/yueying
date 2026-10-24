package dev.aaa1115910.bv.viewmodel.player

data class StreamCandidate(
    val quality: Int,
    val codecPrefix: String,
    val videoUrl: String,
    val audioUrl: String?,
    val decoderSupported: Boolean = true,
)

class PlaybackFallbackPlanner(
    private val candidates: List<StreamCandidate>
) {
    private val failedVideoUrls = mutableSetOf<String>()

    fun selectPreferred(quality: Int, codecPrefix: String): StreamCandidate? {
        var supportedQuality: Int? = null
        for (candidate in candidates) {
            if (candidate.decoderSupported && candidate.videoUrl !in failedVideoUrls &&
                candidate.quality <= quality &&
                (supportedQuality == null || candidate.quality > supportedQuality)
            ) {
                supportedQuality = candidate.quality
            }
        }
        val selectedQuality = supportedQuality ?: return null
        var firstSupported: StreamCandidate? = null
        var compatibleHevc: StreamCandidate? = null
        for (candidate in candidates) {
            if (!candidate.decoderSupported || candidate.quality != selectedQuality ||
                candidate.videoUrl in failedVideoUrls
            ) continue
            if (codecFamily(candidate.codecPrefix) == codecFamily(codecPrefix)) return candidate
            if (firstSupported == null) firstSupported = candidate
            if (compatibleHevc == null && codecFamily(candidate.codecPrefix) == "hevc") {
                compatibleHevc = candidate
            }
        }
        return compatibleHevc ?: firstSupported
    }

    fun nextAfterFailure(current: StreamCandidate): StreamCandidate? {
        failedVideoUrls.add(current.videoUrl)
        return selectPreferred(current.quality, current.codecPrefix)
    }

    private fun codecFamily(prefix: String): String = when {
        prefix.startsWith("hev") || prefix.startsWith("hvc") -> "hevc"
        else -> prefix
    }
}
