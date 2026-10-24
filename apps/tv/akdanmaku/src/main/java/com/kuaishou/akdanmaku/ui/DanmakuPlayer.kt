/*
 * The MIT License (MIT)
 *
 * Copyright 2021 Kwai, Inc. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

package com.kuaishou.akdanmaku.ui

import android.graphics.Canvas
import android.graphics.Point
import android.graphics.RectF
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Message
import android.util.Log
import androidx.core.math.MathUtils.clamp
import com.kuaishou.akdanmaku.DanmakuConfig
import com.kuaishou.akdanmaku.data.DanmakuItemData
import com.kuaishou.akdanmaku.data.DanmakuItem
import com.kuaishou.akdanmaku.data.DataSource
import com.kuaishou.akdanmaku.ecs.DanmakuEngine
import com.kuaishou.akdanmaku.ecs.system.DataSystem
import com.kuaishou.akdanmaku.ecs.system.RenderSystem
import com.kuaishou.akdanmaku.ext.endTrace
import com.kuaishou.akdanmaku.ext.startTrace
import com.kuaishou.akdanmaku.render.DanmakuRenderer
import com.kuaishou.akdanmaku.utils.Fraction
import com.kuaishou.akdanmaku.utils.ObjectPool
import java.lang.ref.WeakReference
import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/**
 *
 * 弹幕播放器，与 [DanmakuView] 形成类似于视频播放器的弹幕播放结构
 * 此类应当在共享同一个弹幕播放的场景间进行共享，它持有着
 * - 播放上下文（计时器，渲染器，缓存管理等）
 * - 渲染引擎
 * 使用 View 的动画刷新驱动绘制；当前帧绘制后立即在后台准备下一帧，避免两个刷新时钟相互等待。
 *
 * 内部具有一个用于执行计算的线程，几乎所有对外 API 均为同步返回，具体操作在此线程中进行
 *
 * @param renderer 业务端自定义的弹幕渲染器
 */
@Suppress("unused")
// Bili Remote: stop idle frame work, release asynchronously, and replace data without rebuilding the engine.
class DanmakuPlayer(renderer: DanmakuRenderer, dataSource: DataSource? = null) {

  companion object {
    internal const val MSG_FRAME_UPDATE = 2101
    internal const val NOTIFY_DISPLAYER_SIZE_CHANGE = 2201

    private const val PLAYER_WIDTH = 682
    const val MIN_DANMAKU_DURATION: Long = 4000
    const val MAX_DANMAKU_DURATION_HIGH_DENSITY: Long = 9000
    /**
     * 是否手动控制 Step 流程
     */
    var isManualStep = false
  }

  private var danmakuView: WeakReference<DanmakuView>? = null
  internal val engine = DanmakuEngine.get(renderer)
  private val actionThread by lazy  { HandlerThread("ActionThread").apply { start() } }
  private val actionHandler by lazy { ActionHandler(actionThread.looper) }
  private val frameUpdateQueued = AtomicBoolean(false)

  private var currentDisplayerWidth = 0
  private var currentDisplayerHeight = 0
  private var currentDisplayerSizeFactor = 1f
  private var config: DanmakuConfig? = null
  @Volatile private var pendingReplacement: List<DanmakuItemData>? = null
  private val replaceDataTask = Runnable {
    val replacement = pendingReplacement
    pendingReplacement = null
    if (!isReleased && replacement != null) {
      val items = ArrayList<DanmakuItem>(replacement.size)
      for (data in replacement) {
        if (isReleased || pendingReplacement != null) return@Runnable
        items.add(obtainItem(data))
      }
      dataSystem?.replaceItems(items)
      engine.context.config.updateRetainer()
      engine.context.config.updateLayout()
      engine.context.config.updateVisibility()
      requestPausedFrame()
    }
  }

  private val drawSemaphore = Semaphore(0)
  @Volatile private var pausedRefreshPending = false
  private val pausedRefreshTask = Runnable {
    if (!started && !isReleased && pausedRefreshPending) {
      val view = danmakuView?.get()
      if (view != null) {
        // Refresh paused settings only after the previous draw has finished.
        if (drawSemaphore.tryAcquire()) {
          pausedRefreshPending = false
          engine.preAct()
          engine.act()
        }
        view.postInvalidateOnAnimation()
      }
    }
  }

  private fun requestPausedFrame() {
    if (started || isReleased) return
    pausedRefreshPending = true
    actionHandler.removeCallbacks(pausedRefreshTask)
    actionHandler.post(pausedRefreshTask)
  }

  @Volatile
  private var started = false

  private val dataSystem: DataSystem?
    get() = engine.getSystem(DataSystem::class.java)

  /**
   * 弹幕埋点所需的接口
   */
  var listener: DanmakuListener? = null
    set(value) {
      if (field != value) {
        field = value
        engine.getSystem(RenderSystem::class.java)?.listener = value
      }
    }

  @Volatile
  var isReleased: Boolean = false
    private set

  val cacheHit: Fraction?
    get() = engine.getSystem(RenderSystem::class.java)?.cacheHit

  init {
    dataSource?.setListener(dataSystem)
    engine.context.onCacheReady = { requestPausedFrame() }
  }

  private fun scheduleNextFrame() {
    if (started && !isReleased && !isManualStep && frameUpdateQueued.compareAndSet(false, true)) {
      actionHandler.sendEmptyMessage(MSG_FRAME_UPDATE)
    }
  }

  private fun updateFrame(deltaTimeSeconds: Float? = null) {
    try {
      if (!started || isReleased) return
      if (isManualStep) {
        engine.step(deltaTimeSeconds)
      } else {
        engine.preAct()
      }
      if (!started || isReleased) return
      startTrace("updateFrame")
      engine.act()
      endTrace()
    } finally {
      // Clear before invalidation so even an immediate draw can schedule its successor.
      frameUpdateQueued.set(false)
      // A pause/resume during this update must still start its successor.
      if (started && !isReleased) danmakuView?.get()?.postInvalidateOnAnimation()
    }
  }

  internal fun draw(canvas: Canvas, opacity: Float) {
    if (isReleased) {
      return
    }
    if (!isManualStep) {
      // Time goes one step.
      engine.step()
    }
    drawSemaphore.tryAcquire()
    engine.draw(canvas, opacity) {
      releaseSemaphore()
      scheduleNextFrame()
    }
    if (pausedRefreshPending) requestPausedFrame()
  }

  private fun releaseSemaphore() {
    // Acquired or on the first draw(with init permit: 0).
    if (drawSemaphore.availablePermits() == 0) {
      drawSemaphore.release()
    }
  }

  /**
   * For debug use, step manually.
   */
  fun step(deltaTimeMs: Int) {
    if (isManualStep) {
      actionHandler.obtainMessage(MSG_FRAME_UPDATE, deltaTimeMs, 0).sendToTarget()
    }
  }

  /**
   * 将播放器与一个 DanmakuView 绑定，前一个被绑定的会自动解锁。
   * 绑定后弹幕的绘制将在此 View 上进行
   */
  fun bindView(danmakuView: DanmakuView) {
    this.danmakuView?.get()?.danmakuPlayer = null
    this.danmakuView = WeakReference(danmakuView)
    danmakuView.danmakuPlayer = this
    engine.context.displayer = danmakuView.displayer
    notifyDisplayerSizeChanged(danmakuView.displayer.width, danmakuView.displayer.height)
    requestPausedFrame()
    danmakuView.postInvalidate()
  }

  /**
   * 播放弹幕
   *
   * @param danmakuConfig 弹幕配置
   */
  fun start(danmakuConfig: DanmakuConfig? = null) {
    danmakuConfig?.let {
      updateConfig(it)
    }
    if (isReleased) return
    pausedRefreshPending = false
    engine.start()
    if (!started) {
      started = true
      scheduleNextFrame()
    }
  }

  fun pause() {
    if (isReleased) return
    started = false
    engine.pause()
    releaseSemaphore()
    // Let the queued update observe started=false and clear its own flag.
    // Resetting it here could race with a running update and a quick resume.
  }

  fun stop() {
    pause()
    seekTo(0)
  }

  /**
   * 释放弹幕播放器，释放后弹幕播放器将不再可用。
   */
  fun release() {
    if (isReleased) {
      return
    }
    isReleased = true
    started = false
    danmakuView = null
    pendingReplacement = null
    pausedRefreshPending = false
    engine.context.onCacheReady = null
    releaseSemaphore()
    actionHandler.removeCallbacksAndMessages(null)
    actionHandler.post {
      try {
        engine.release()
      } finally {
        actionThread.quitSafely()
      }
    }
  }

  /** Replaces the complete dataset on the action thread; pending requests are conflated. */
  fun replaceData(dataList: List<DanmakuItemData>) {
    if (isReleased) return
    pendingReplacement = dataList
    actionHandler.removeCallbacks(replaceDataTask)
    actionHandler.post(replaceDataTask)
  }

  fun seekTo(positionMs: Long) {
    Log.d(DanmakuEngine.TAG, "[Player] SeekTo($positionMs)")
    getConfig()?.updateFirstShown()
    engine.seekTo(max(positionMs, 0L))
    requestPausedFrame()
  }

  fun getCurrentTimeMs(): Long {
    return engine.getCurrentTimeMs()
  }

  fun updatePlaySpeed(speed: Float) {
    engine.updateTimerFactor(speed)
  }

  fun updateData(dataList: List<DanmakuItemData>): List<DanmakuItem> {
    val items = dataList.map { obtainItem(it) }
    dataSystem?.addItems(items)
    return items
  }

  /**
   * 弹幕目前统一的数据结构就是 DanmakuItem，他是 DanmakuItemData 的超集，也是被定义为
   * 可以进行扩展的
   */
  fun updateItems(items: List<DanmakuItem>) {
    dataSystem?.addItems(items)
  }

  fun send(danmaku: DanmakuItemData): DanmakuItem {
    val item = obtainItem(danmaku)
    dataSystem?.addItem(item)
    return item
  }

  fun send(item: DanmakuItem) {
    dataSystem?.addItem(item)
  }

  /**
   * 更新一个弹幕
   */
  fun updateItem(item: DanmakuItem) {
    dataSystem?.updateItem(item)
  }

  fun updateConfig(danmakuConfig: DanmakuConfig?) {
    config = danmakuConfig
    engine.updateConfig(danmakuConfig ?: return)
    requestPausedFrame()
  }

  fun getConfig(): DanmakuConfig? = engine.getConfig()

  fun getDanmakusAtPoint(point: Point): List<DanmakuItem>? {
    return engine.getSystem(RenderSystem::class.java)?.getDanmakus(point)
  }

  fun getDanmakusInRect(hitRect: RectF): List<DanmakuItem>? {
    return engine.getSystem(RenderSystem::class.java)?.getDanmakus(hitRect)
  }

  fun hold(item: DanmakuItem?) {
    dataSystem?.hold(item)
  }

  fun obtainItem(danmaku: DanmakuItemData): DanmakuItem =
    ObjectPool.obtainItem(danmaku, this)

  fun releaseItem(item: DanmakuItem) {
    ObjectPool.releaseItem(item)
  }

  /**
   * 设置滚动弹幕的速度系数
   * @param factor 速度系数。
   */
  fun setDanmakuRollingSpeed(factor: Float) {
    if (factor <= 0) return

    if (factor != config?.rollingSpeedFactor) {
        config?.rollingSpeedFactor = factor
    }

    // 使用当前保存的尺寸重新计算时长
    updateViewportState(currentDisplayerWidth, currentDisplayerHeight, currentDisplayerSizeFactor, true)
    requestPausedFrame()
  }

  internal fun notifyDisplayerSizeChanged(width: Int, height: Int) {
    val displayer = engine.context.displayer
    updateViewportState(width, height, displayer.getViewportSizeFactor())
    updateMaxDanmakuDuration()
    if (displayer.width != width || displayer.height != height) {
      Log.d(DanmakuEngine.TAG, "notifyDisplayerSizeChanged($width, $height)")
      displayer.width = width
      displayer.height = height
      actionHandler.obtainMessage(NOTIFY_DISPLAYER_SIZE_CHANGE).sendToTarget()
    }
  }

  private fun updateViewportState(width: Int, height: Int, viewportSizeFactor: Float, forceUpdate: Boolean = false) {
    val config = this.config ?: return
    if (currentDisplayerWidth != width ||
      currentDisplayerHeight != height ||
      currentDisplayerSizeFactor != viewportSizeFactor ||
      forceUpdate) {
      val duration =
        (DanmakuConfig.DEFAULT_DURATION * (viewportSizeFactor * width / PLAYER_WIDTH)).toLong()

      if (config.rollingDurationMs != duration) {
        config.rollingDurationMs = duration
        config.updateRetainer()
        config.updateLayout()
        config.updateVisibility()
      }
      Log.d("XanaDanmaku", "[Factor] update rolling duration to $duration")
      currentDisplayerWidth = width
      currentDisplayerHeight = height
      currentDisplayerSizeFactor = viewportSizeFactor
    }
  }

  private fun updateMaxDanmakuDuration() {
    // FIXME distinguish differ danmaku type duration
  }

  private inner class ActionHandler(looper: Looper) : Handler(looper) {
    override fun handleMessage(msg: Message) {
      when (msg.what) {
        MSG_FRAME_UPDATE -> {
          val deltaTimeSeconds = if (msg.arg1 > 0) {
            msg.arg1 / 1000.0f
          } else null
          updateFrame(deltaTimeSeconds)
        }
        NOTIFY_DISPLAYER_SIZE_CHANGE -> {
          val newConfig = engine.context.config
          newConfig.updateLayout()
          newConfig.updateMeasure()
          newConfig.updateCache()
          newConfig.updateRetainer()
          requestPausedFrame()
        }
      }
    }
  }

}
