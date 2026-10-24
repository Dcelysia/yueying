package dev.aaa1115910.bv.activities

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.tv.material3.OutlinedButton
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import dev.aaa1115910.bv.cast.TvStartupService
import dev.aaa1115910.bv.cast.server.CastNetworkUtil
import dev.aaa1115910.bv.cast.server.CastReceiverConfig
import dev.aaa1115910.bv.repository.UserRepository
import dev.aaa1115910.bv.screen.MainScreen
import dev.aaa1115910.bv.screen.user.lock.UnlockUserScreen
import dev.aaa1115910.bv.ui.theme.BVTheme
import kotlinx.coroutines.delay
import io.github.oshai.kotlinlogging.KotlinLogging
import org.koin.android.ext.android.inject

class MainActivity : PreviewAwareComponentActivity() {

    private val userRepository: UserRepository by inject()
    private val logger = KotlinLogging.logger {}

    override fun onCreate(savedInstanceState: Bundle?) {
        var keepSplashScreen = true
        installSplashScreen().apply {
            setKeepOnScreenCondition { keepSplashScreen }
        }
        super.onCreate(savedInstanceState)
        TvStartupService.rememberCurrentBoot(this)
        TvStartupService.ensureAdbEnabled(this)
        TvStartupService.requestRecoveryBinding(this)

        setContent {
            var isCheckingUserLock by remember { mutableStateOf(true) }
//            var isMainlandChina by remember { mutableStateOf(false) }
            var userLockLocked by remember { mutableStateOf(false) }

            LaunchedEffect(Unit) {
                val user = userRepository.findUserByUid(userRepository.uid)
                userLockLocked = user?.lock?.isNotBlank() ?: false
                logger.info { "default user: ${user?.username}" }
                isCheckingUserLock = false
                keepSplashScreen = false
            }


            BVTheme {
                if (isCheckingUserLock) {
                    //避免在检查网络的期间加载屏幕内容，导致检查完毕后显示屏幕内容时出现初始焦点未成功设置的问题
                } else {
                    if (!userLockLocked) {
                        Column(modifier = Modifier.fillMaxSize()) {
                            PhoneConnectionBanner()
                            MainScreen(modifier = Modifier.weight(1f))
                        }
                    } else {
                        UnlockUserScreen(
                            onUnlockSuccess = { user ->
                                logger.info { "unlock user lock for user ${user.uid}" }
                                userLockLocked = false
                            }
                        )
                    }
                }
            }
        }
    }

}

@Composable
private fun PhoneConnectionBanner() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var address by remember { mutableStateOf(CastNetworkUtil.localIpv4Address()) }

    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                address = CastNetworkUtil.localIpv4Address()
                delay(1_000)
            }
        }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text("手机遥控", style = MaterialTheme.typography.titleMedium)
            Text(
                text = if (address == "127.0.0.1") {
                    "连接家庭网络后，在手机端选择 Bili Remote TV"
                } else {
                    "在手机端选择 Bili Remote TV · 手动地址 $address:${CastReceiverConfig.HTTP_PORT}"
                },
                style = MaterialTheme.typography.bodySmall
            )
        }
        OutlinedButton(onClick = {
            for (action in listOf(Settings.ACTION_SETTINGS, "com.xiaomi.mitv.settings.SETTINGS")) {
                try {
                    context.startActivity(Intent(action))
                    return@OutlinedButton
                } catch (_: ActivityNotFoundException) {
                    // Some Xiaomi TVs expose only their vendor settings action.
                }
            }
            Toast.makeText(context, "请使用遥控器的设置键打开系统设置", Toast.LENGTH_LONG).show()
        }) {
            Text("系统设置")
        }
        Text("同一局域网 · 免配对连接", style = MaterialTheme.typography.bodySmall)
    }
}
