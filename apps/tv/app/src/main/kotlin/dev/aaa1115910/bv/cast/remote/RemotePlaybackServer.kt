package dev.aaa1115910.bv.cast.remote

import dev.aaa1115910.bv.cast.CastPlaybackIdentity
import dev.aaa1115910.bv.cast.CastQueueItem
import dev.aaa1115910.bv.cast.CastDanmakuSettings
import dev.aaa1115910.bv.cast.CastPlaybackLauncher
import dev.aaa1115910.bv.cast.CastPlaybackSessionRegistry
import dev.aaa1115910.bv.cast.CastPlaybackSnapshot
import io.ktor.server.routing.Routing
import io.ktor.server.routing.get
import io.ktor.server.response.respondText
import io.ktor.http.ContentType
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.CloseReason
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.util.UUID

/** Owns a TV playback session. Closing a phone socket never stops the TV player. */
class RemotePlaybackServer(
    private val deviceId: String,
    private val pairing: RemotePairingStore,
    private val launcher: CastPlaybackLauncher
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val commands = Mutex()
    private var playbackId = UUID.randomUUID().toString()
    private var lastMediaIdentity = ""
    private var pendingMedia: RemoteMedia? = null
    private var pendingSinceMs = 0L
    private var revision = 0L
    private val completedRequests = LinkedHashMap<String, JsonObject>()
    // Accessed under commands, retained only for the current playback queue.
    private var encodedQueueSource: List<CastQueueItem>? = null
    private var encodedQueue: JsonElement = JsonArray(emptyList())

    fun register(routing: Routing) = with(routing) {
        get("/remote/v1/info") {
            call.respondText(buildJsonObject {
                put("protocol", 1); put("deviceId", deviceId); put("name", "Bili Remote TV")
            }.toString(), ContentType.Application.Json)
        }
        webSocket("/remote/v1") {
            try {
                val helloFrame = withTimeout(10_000) { incoming.receive() } as? Frame.Text
                    ?: error("请先发送连接信息")
                val hello = json.parseToJsonElement(helloFrame.readText()).jsonObject
                require(hello.string("type") == "hello" && hello["protocol"]?.jsonPrimitive?.int == 1) { "遥控协议版本不匹配" }
                val clientId = hello.string("clientId") ?: error("缺少设备编号")
                val token = pairing.registerClient(clientId)
                send(Frame.Text(buildJsonObject {
                    put("type", "welcome"); put("protocol", 1); put("deviceId", deviceId)
                    put("name", "Bili Remote TV"); put("token", token)
                }.toString()))
                coroutineScope {
                    // A single worker coalesces state refreshes; command intake never waits for a full snapshot send.
                    val stateRefreshes = Channel<Unit>(Channel.CONFLATED)
                    stateRefreshes.trySend(Unit)
                    val updates = launch {
                        for (ignored in stateRefreshes) {
                            val state = commands.withLock { stateMessage() }
                            send(Frame.Text(state.toString()))
                            // Downstream snapshots are capped at 2/s; ACK and command execution never wait here.
                            delay(500)
                        }
                    }
                    val ticker = launch {
                        while (true) {
                            delay(1_000)
                            stateRefreshes.trySend(Unit)
                        }
                    }
                    try {
                        for (frame in incoming) {
                            if (frame !is Frame.Text) continue
                            var requestId: String? = null
                            val result = try {
                                val request = json.parseToJsonElement(frame.readText()).jsonObject
                                requestId = request.string("requestId")
                                require(!requestId.isNullOrBlank() && requestId!!.length <= 100) { "缺少请求编号" }
                                commands.withLock {
                                    val key = "$clientId:$requestId"
                                    completedRequests[key] ?: execute(request).also {
                                        completedRequests[key] = it
                                        if (completedRequests.size > 128) completedRequests.remove(completedRequests.keys.first())
                                    }
                                }
                            } catch (cancelled: CancellationException) {
                                throw cancelled
                            } catch (error: Exception) {
                                buildJsonObject {
                                    put("type", "error"); put("requestId", requestId)
                                    put("message", error.message ?: "电视执行失败")
                                }
                            }
                            send(Frame.Text(result.toString()))
                            // ACK is immediate. A fresh state is requested separately and may be coalesced.
                            stateRefreshes.trySend(Unit)
                        }
                    } finally {
                        ticker.cancel()
                        stateRefreshes.close()
                        updates.cancel()
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                close(CloseReason(CloseReason.Codes.CANNOT_ACCEPT, "Invalid remote session"))
            }
        }
    }

    private suspend fun execute(request: JsonObject): JsonObject {
        require(request.string("type") == "command") { "命令格式错误" }
        val action = request.string("action") ?: error("缺少操作")
        // Refresh first so a TV-remote episode change invalidates commands from an older phone screen.
        val currentIdentity = withContext(Dispatchers.Main.immediate) {
            CastPlaybackSessionRegistry.current()?.identity() ?: CastPlaybackIdentity(null, 0L, 0L, null)
        }
        refreshPlaybackIdentity(currentIdentity)
        val payload = request["payload"]?.jsonObject ?: buildJsonObject {}
        if (action == "load") {
            val media = json.decodeFromJsonElement<RemoteMedia>(payload)
            media.validate()
            val requestedPlaybackId = UUID.randomUUID().toString()
            require(launcher.launch(media.toCastContent().let { it.copy(rawFields = it.rawFields + ("remote_playback_id" to requestedPlaybackId)) })) { "电视无法打开此视频" }
            pendingMedia = media
            pendingSinceMs = System.currentTimeMillis()
            playbackId = requestedPlaybackId
        } else if (action != "state") {
            require(request.string("playbackId") == playbackId) { "电视已切换视频，请等待状态更新后重试" }
            require(pendingMedia == null) { "电视正在切换视频，请稍候" }
            withContext(Dispatchers.Main.immediate) {
                val session = CastPlaybackSessionRegistry.current() ?: error("电视当前没有播放视频")
                when (action) {
                    "play" -> session.play()
                    "pause" -> session.pause()
                    "stop", "back" -> session.stop()
                    "seek" -> session.seekTo(payload.getValue("positionMs").jsonPrimitive.long.coerceAtLeast(0))
                    "volume" -> session.setVolume(payload.getValue("value").jsonPrimitive.int.coerceIn(0, 100))
                    "adjustVolume" -> {
                        val direction = payload.getValue("direction").jsonPrimitive.int
                        require(direction == -1 || direction == 1) { "音量方向无效" }
                        session.adjustVolume(direction)
                    }
                    "speed" -> session.setSpeed(payload.getValue("value").jsonPrimitive.float.also {
                        require(it.isFinite() && it in 0.25f..4f) { "倍速超出范围" }
                    })
                    "quality" -> {
                        val quality = payload.getValue("value").jsonPrimitive.int
                        require(session.snapshot().availableQuality.containsKey(quality)) { "此清晰度不可用" }
                        session.setQuality(quality)
                    }
                    "skipSponsor" -> session.skipSponsorSegment(payload.string("segmentId") ?: error("缺少片段编号"))
                    "dismissSponsor" -> session.dismissSponsorSegment(payload.string("segmentId") ?: error("缺少片段编号"))
                    "sponsorSkipMode" -> session.setSponsorSkipMode(payload.string("mode") ?: error("缺少跳过模式"))
                    "danmaku" -> session.setDanmakuEnabled(payload.getValue("enabled").jsonPrimitive.boolean)
                    "danmakuSettings" -> {
                        val settings = json.decodeFromJsonElement<CastDanmakuSettings>(payload)
                        settings.validate()
                        session.updateDanmakuSettings(settings)
                    }
                    "next", "previous", "episode" -> {
                        val snapshot = session.snapshot()
                        val currentIndex = snapshot.queue.indexOfFirst { it.aid == snapshot.aid && it.cid == snapshot.cid }
                        val index = when (action) {
                            "next" -> currentIndex + 1
                            "previous" -> currentIndex - 1
                            else -> snapshot.queue.indexOfFirst {
                                it.aid == payload.getValue("aid").jsonPrimitive.long &&
                                    it.cid == payload.getValue("cid").jsonPrimitive.long
                            }
                        }
                        require(index in snapshot.queue.indices && (action == "episode" || currentIndex >= 0)) { "没有可切换的剧集" }
                        session.playItem(snapshot.queue[index])
                    }
                    else -> error("不支持的操作：$action")
                }
            }
        }
        return buildJsonObject {
            put("type", "ack"); put("requestId", request.string("requestId"))
            put("status", if (action == "load") "accepted" else "applied")
        }
    }

    private fun refreshPlaybackIdentity(current: CastPlaybackIdentity): Boolean {
        val waiting = pendingMedia
        if (waiting != null && current.remoteSessionId == playbackId && current.aid > 0 && current.cid > 0) {
            pendingMedia = null
            lastMediaIdentity = "${current.aid}:${current.cid}:${current.epid}"
        }
        val timedOut = pendingMedia != null && System.currentTimeMillis() - pendingSinceMs > 15_000
        if (timedOut) pendingMedia = null
        val identity = "${current.aid}:${current.cid}:${current.epid}"
        if (pendingMedia == null && identity != lastMediaIdentity) {
            lastMediaIdentity = identity
            playbackId = UUID.randomUUID().toString()
        }
        return timedOut
    }

    private suspend fun stateMessage(): JsonObject {
        val snapshot = withContext(Dispatchers.Main.immediate) {
            CastPlaybackSessionRegistry.current()?.snapshot() ?: CastPlaybackSnapshot()
        }
        val timedOut = refreshPlaybackIdentity(CastPlaybackIdentity(snapshot.remoteSessionId, snapshot.aid, snapshot.cid, snapshot.epid))
        val waiting = pendingMedia
        return withContext(Dispatchers.Default) {
            if (encodedQueueSource !== snapshot.queue) {
                encodedQueueSource = snapshot.queue
                encodedQueue = json.encodeToJsonElement(snapshot.queue)
            }
            buildJsonObject {
                put("type", "state"); put("playbackId", playbackId); put("revision", ++revision)
                put("state", when {
                    timedOut -> "ERROR"
                    waiting != null -> "TRANSITIONING"
                    snapshot.errorMessage != null -> "ERROR"
                    else -> snapshot.state.name
                })
                put("error", if (timedOut) "电视未能打开视频，请重试" else snapshot.errorMessage)
                put("aid", waiting?.aid ?: snapshot.aid); put("cid", waiting?.cid ?: snapshot.cid)
                put("title", waiting?.title ?: snapshot.title)
                put("positionMs", if (waiting != null) waiting.positionMs else snapshot.positionMs)
                put("durationMs", if (waiting != null) 0 else snapshot.durationMs)
                put("sponsorSkipMode", snapshot.sponsorSkipMode)
                put("sponsorSegment", if (waiting == null) json.encodeToJsonElement(snapshot.sponsorSegment) else JsonNull)
                put("sponsorSkipNotice", if (waiting == null) snapshot.sponsorSkipNotice else null)
                put("speed", snapshot.speed); put("volume", snapshot.volume)
                put("volumeMode", snapshot.volumeMode); put("danmakuEnabled", snapshot.danmakuEnabled)
                put("danmakuSettings", json.encodeToJsonElement(snapshot.danmakuSettings))
                put("qualityId", snapshot.qualityId)
                put("qualities", buildJsonObject { snapshot.availableQuality.forEach { (id, label) -> put(id.toString(), label) } })
                put("queue", if (waiting == null) encodedQueue else JsonArray(emptyList()))
            }
        }
    }

    private fun JsonObject.string(key: String): String? = (get(key) as? JsonPrimitive)?.contentOrNull
}
