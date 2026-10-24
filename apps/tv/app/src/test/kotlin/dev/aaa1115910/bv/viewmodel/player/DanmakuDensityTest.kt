package dev.aaa1115910.bv.viewmodel.player

import com.kuaishou.akdanmaku.data.DanmakuItemData
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

class DanmakuDensityTest {
    private fun item(id: Long, position: Long = 0L) = DanmakuItemData(
        danmakuId = id, position = position, content = "字", mode = DanmakuItemData.DANMAKU_MODE_ROLLING,
        textSize = 100, textColor = -1
    )

    @Test
    fun `full density reuses the original list without copying`() = runBlocking {
        val source = listOf(item(1), item(2))
        assertSame(source, filterDanmakuByScreenArea(source, 1f, 1f, 0.1f))
    }

    @Test
    fun `dense burst preserves the area budget and recovers after seven seconds`() = runBlocking {
        val source = (1L..6L).map { item(it) } + item(7, 7001L)
        // Budget: 1920*1080*0.1*0.2*0.5 = 20736; each item takes 10000 pixels.
        assertEquals(listOf(1L, 2L, 4L, 7L),
            filterDanmakuByScreenArea(source, 0.2f, 1f, 0.1f).map { it.danmakuId })
    }

    @Test
    fun `sparse comments are not randomly discarded at low density`() = runBlocking {
        val source = listOf(item(1), item(2, 8000L), item(3, 16000L))
        assertEquals(source, filterDanmakuByScreenArea(source, 0.2f, 1f, 0.1f))
    }
}
