package dev.aaa1115910.bv.player

import android.view.LayoutInflater
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import dev.aaa1115910.bv.player.impl.exo.ExoMediaPlayer

@OptIn(UnstableApi::class)
@Composable
fun BvVideoPlayer(
    modifier: Modifier = Modifier,
    videoPlayer: AbstractVideoPlayer?,
    resizeMode: Int = AspectRatioFrameLayout.RESIZE_MODE_FILL,
    keepScreenAwake: Boolean = false,
    useSurfaceView: Boolean = false,
) {
    if (videoPlayer is ExoMediaPlayer) {
        AndroidView(
            modifier = modifier.fillMaxSize(),
            factory = { ctx ->
                val layout = if (useSurfaceView) R.layout.bv_surface_player_view else R.layout.bv_texture_player_view
                val playerView = LayoutInflater.from(ctx).inflate(layout, null) as PlayerView
                playerView.apply {
                    player = videoPlayer.mPlayer
                    this.resizeMode = resizeMode
                    if (keepScreenAwake) {
                        keepScreenOn = true
                    }
                }
            },
            update = { playerView ->
                playerView.player = videoPlayer.mPlayer
                playerView.resizeMode = resizeMode
                if (keepScreenAwake) {
                    playerView.keepScreenOn = true
                }
            },
            onRelease = { playerView ->
                playerView.player = null
                playerView.keepScreenOn = false
            }
        )
    }
}
