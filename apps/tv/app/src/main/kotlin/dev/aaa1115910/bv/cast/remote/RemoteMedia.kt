package dev.aaa1115910.bv.cast.remote

import dev.aaa1115910.bv.cast.protocol.CastContent
import kotlinx.serialization.Serializable

/** Video identity travels over the LAN; signed media URLs and Bilibili credentials do not. */
@Serializable
data class RemoteMedia(
    val aid: Long = 0,
    val cid: Long = 0,
    val epid: Int? = null,
    val seasonId: Int? = null,
    val title: String = "",
    val positionMs: Long = 0,
    val page: Int = 1
) {
    fun validate() {
        require(aid >= 0 && cid >= 0 && (aid > 0 || epid != null || seasonId != null)) { "视频编号或分 P 编号无效" }
        require(cid == 0L || aid > 0) { "分 P 编号缺少视频编号" }
        require(page in 1..10_000) { "分 P 序号无效" }
        require(epid == null || epid > 0) { "剧集编号无效" }
        require(seasonId == null || seasonId > 0) { "季度编号无效" }
        require(positionMs >= 0 && positionMs <= Int.MAX_VALUE.toLong()) { "播放位置无效" }
        require(title.length <= 1000) { "标题过长" }
    }

    fun toCastContent(): CastContent {
        validate()
        return CastContent(
            aid = aid.takeIf { it > 0 }, cid = cid.takeIf { it > 0 }, epid = epid, seasonId = seasonId,
            title = title.takeIf { it.isNotBlank() }, seekSeconds = (positionMs / 1000).toInt(),
            remotePlayback = true,
            rawFields = mapOf("remote_page" to page.toString())
        )
    }
}
