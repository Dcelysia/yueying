package dev.aaa1115910.bv.cast

import dev.aaa1115910.bv.cast.remote.RemoteMedia
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RemoteMediaTest {
    @Test
    fun `UGC preserves exact video and part identity without direct media URL`() {
        val content = RemoteMedia(aid = 42, cid = 123, positionMs = 35_000).toCastContent()
        assertEquals(42L, content.aid)
        assertEquals(123L, content.cid)
        assertEquals(35, content.seekSeconds)
        assertTrue(content.remotePlayback)
        assertNull(content.directMediaUrl)
    }

    @Test
    fun `PGC preserves episode and season identity`() {
        val content = RemoteMedia(aid = 42, cid = 123, epid = 55, seasonId = 8).toCastContent()
        assertEquals(55, content.epid)
        assertEquals(8, content.seasonId)
    }

    @Test
    fun `shared video without cid is resolved on television and preserves page`() {
        val content = RemoteMedia(aid = 170001, page = 2).toCastContent()
        assertEquals(170001L, content.aid)
        assertNull(content.cid)
        assertEquals("2", content.rawFields["remote_page"])
        assertNull(content.title)
    }

    @Test
    fun `shared episode without aid or cid can reach television resolver`() {
        val content = RemoteMedia(epid = 55).toCastContent()
        assertNull(content.aid)
        assertNull(content.cid)
        assertEquals(55, content.epid)
        assertFailsWith<IllegalArgumentException> { RemoteMedia(aid = 42, page = 0).validate() }
        assertFailsWith<IllegalArgumentException> { RemoteMedia().validate() }
    }

    @Test
    fun `rejects identities and positions that cannot reach the player correctly`() {
        assertFailsWith<IllegalArgumentException> { RemoteMedia(0, 123).validate() }
        assertFailsWith<IllegalArgumentException> { RemoteMedia(42, -1).validate() }
        assertFailsWith<IllegalArgumentException> { RemoteMedia(42, 123, epid = 0).validate() }
        assertFailsWith<IllegalArgumentException> { RemoteMedia(42, 123, positionMs = -1).validate() }
        assertFailsWith<IllegalArgumentException> { RemoteMedia(42, 123, positionMs = Long.MAX_VALUE).validate() }
    }
}
