package dev.aaa1115910.bv.viewmodel.player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PlaybackFallbackPlannerTest {
    @Test
    fun `planner retries same quality with another codec before dropping resolution`() {
        val planner = PlaybackFallbackPlanner(
            candidates = listOf(
                StreamCandidate(127, "av01", "video://8k-av1", "audio://main"),
                StreamCandidate(127, "hev1", "video://8k-hevc", "audio://main"),
                StreamCandidate(120, "hev1", "video://4k-hevc", "audio://main")
            )
        )

        val next = planner.nextAfterFailure(
            StreamCandidate(127, "av01", "video://8k-av1", "audio://main")
        )

        assertEquals(
            StreamCandidate(127, "hev1", "video://8k-hevc", "audio://main"),
            next
        )
    }
    @Test
    fun `unsupported 4k avc keeps 4k by selecting supported hevc`() {
        val hevc = StreamCandidate(120, "hev1", "4k-hevc", null)
        val planner = PlaybackFallbackPlanner(listOf(
            StreamCandidate(120, "avc1", "4k-avc", null, decoderSupported = false),
            hevc,
            StreamCandidate(80, "avc1", "1080p", null)
        ))
        assertEquals(hevc, planner.selectPreferred(120, "avc1"))
    }

    @Test
    fun `hevc sample entry variants match before unrelated codec`() {
        val hevc = StreamCandidate(120, "hvc", "4k-hvc1", null)
        val planner = PlaybackFallbackPlanner(listOf(
            StreamCandidate(120, "avc1", "4k-avc", null), hevc
        ))
        assertEquals(hevc, planner.selectPreferred(120, "hev1"))
    }

    @Test
    fun `failed streams are not retried and fallback terminates`() {
        val avc = StreamCandidate(120, "avc1", "4k-avc", null)
        val hevc = StreamCandidate(120, "hev1", "4k-hevc", null)
        val lower = StreamCandidate(80, "avc1", "1080p", null)
        val planner = PlaybackFallbackPlanner(listOf(avc, hevc, lower))
        assertEquals(avc, planner.nextAfterFailure(hevc))
        assertEquals(lower, planner.nextAfterFailure(avc))
        assertNull(planner.nextAfterFailure(lower))
        assertNull(planner.selectPreferred(120, "hev1"))
    }

    @Test
    fun `unsupported 4k falls back below request without selecting 8k`() {
        val lower = StreamCandidate(80, "hev1", "1080p", null)
        val planner = PlaybackFallbackPlanner(listOf(
            StreamCandidate(127, "hev1", "8k", null),
            StreamCandidate(120, "avc1", "4k", null, decoderSupported = false), lower
        ))
        assertEquals(lower, planner.selectPreferred(120, "avc1"))
    }

    @Test
    fun `no compatible decoder does not select an unsupported stream`() {
        val planner = PlaybackFallbackPlanner(listOf(
            StreamCandidate(120, "avc1", "4k", null, decoderSupported = false)
        ))
        assertNull(planner.selectPreferred(120, "avc1"))
    }
}
