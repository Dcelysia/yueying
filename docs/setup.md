# 安装与源码搭建

适用对象：希望在自己家中使用，或从源码构建跃映的开发者。本项目不要求刷机或 root。鸿蒙手机仅浏览和遥控；Android 手机保留本地播放；电视负责独立取流和弹幕。

## 1. 准备设备与安装包

- 一台能安装 Android APK 的电视或电视盒子，以及一部 Android / HarmonyOS 手机。
- 手机与电视处于可互相访问的同一局域网；访客 Wi-Fi、AP 隔离或防火墙可能阻止发现。
- 使用同一来源、配套版本的手机客户端和电视接收端。构建产物不等于商店审核通过；可用版本以仓库 Releases 或实际邀请测试记录为准。

Android 使用 APK；HarmonyOS 5+ 的原生客户端使用 HAP 开发安装或经过审核的 AppTest 邀测。不能把 APK 改扩展名当作鸿蒙包。鸿蒙签名、开发设备与正式 APP 发布的区别见[发布说明](harmonyos-release.md)。

## 2. Android TV：用 ADB 安装

先在电视上按厂商说明开启开发者选项与 ADB / 无线调试，在电视确认“允许此电脑调试”。这些操作必须由设备使用者手动完成，不使用脚本绕过授权。开发电脑与电视应连接同一可信网络。

从 Android SDK 的 Platform Tools 使用 `adb`。以下地址是占位符，须替换为电视实际显示的 IP 与 ADB 端口；不是本项目遥控端口。

```sh
adb devices -l
TV_ADDRESS="电视IP:ADB端口"
adb connect "$TV_ADDRESS"
adb -s "$TV_ADDRESS" install -r dist/bili-remote-tv-release.apk
```

部分新系统使用“无线调试”配对：先按电视显示的配对地址执行 `adb pair`，输入设备上显示的配对码，再使用实际连接地址执行 `adb connect`；配对端口与连接端口可能不同。老设备是否提供 TCP ADB、需要怎样先连 USB，由厂商与系统版本决定，不预设所有电视都是 5555。

若 `adb devices` 显示 `unauthorized`，在电视确认信任；`offline` 或连接拒绝时先检查电视调试设置、IP、端口和网络。`install -r` 尽量保留现有数据；若签名不同，先确认安装包来源与原签名，不直接卸载清除原数据。

安装后在电视手动打开接收端。启动手机接收服务不需要再到网络设置打开“投屏”开关；电视首次安装后仍应实际启动一次。日常遥控只使用应用协议，**不依赖电脑常驻或 ADB 保持连接**。

ADB 是开发管理通道，`9838` 是本项目局域网控制端口。两者都不应映射到公网或对不可信网络开放。使用结束可按自己的需要关闭系统 ADB 调试。

Android 官方操作参考：[Android Debug Bridge](https://developer.android.com/tools/adb)。

## 3. 安装手机端并连接

Android 手机可手动安装对应 APK；通过开发电脑安装时，先在手机开启调试并确认电脑信任，再明确选择手机的 serial，避免误装到电视：

```sh
adb devices -l
PHONE_SERIAL="手机在adb列表中的serial"
adb -s "$PHONE_SERIAL" install -r dist/bili-remote-mobile.apk
```

鸿蒙开发安装请按后面的 DevEco 签名流程；AppTest 邀测须使用获邀华为账号与实际邀请码。

1. 手机打开“连接电视”，优先选择自动发现的接收端。
2. 未发现时，在手机填入电视实际局域网 IP 和 **9838**。这里不是填 ADB 端口。
3. 手机选择视频或分 P 后，电视独立播放；手机进入占位播放器。可打开全屏控制调节进度、音量、选集、倍速、画质、弹幕及赞助片段跳过。
4. 电视与手机按需分别登录 B站账号。手机登录凭据不通过遥控协议发给电视，手机登录也不自动赋予电视会员或付费内容权限。

自动发现受广播、多播、路由器隔离和厂商网络策略影响。手动 IP 成功只证明控制连接可达，不等于自动发现链路已验证。保存连接用于后续重连；不要把维护者家中的固定 IP 当作所有人的默认设备。

## 4. 验证多手机接力

- A 连接电视并选视频，等电视进入播放。
- B 连接同一接收端，打开已有播放的占位页或全屏控制页；电视不应重播、跳到开头或重新加载 A 的旧视频。
- A 切换视频、选集、进度或音量，检查 B 跟随电视回传状态；B 的操作也应让 A 更新。
- B 返回、锁屏、断开连接或退出账号，电视继续播放；只有主动“停止电视播放”才停止。

鸿蒙端全屏是电视控制界面，不是手机视频播放器。Android 的本地播放与遥控切换保留；请分别验证，不能用鸿蒙无本地播放的设计覆盖 Android 功能。

## 5. Android 源码环境

```sh
git clone https://github.com/Dcelysia/yueying.git
cd yueying
python3 scripts/setup-flutter.py
python3 scripts/build-apks.py --only mobile
python3 scripts/build-apks.py --only tv --tv-build-type release
```

需要 Python 3.11+、Android SDK、JDK 17。手机固定使用 Flutter 3.47.7 / Dart 3.13.5，包含 PiliPlus 配套补丁；不要先运行任意版本的 `flutter upgrade`。可通过 `ANDROID_HOME`、`JAVA_HOME` 指向自己的 SDK / JDK。工具链与构建产物位于 `toolchains/`、`dist/`，不加入源码仓库。

Apple Silicon Mac 还需要 Xcode 命令行工具，以及 Homebrew 的 `protobuf`、`abseil`。构建脚本会处理 NeoBV 配套的 macOS ARM gRPC 代码生成器；遇到网络或工具链失败时检查实际报错，不直接删掉现有 SDK 或用户目录。

电视发布签名使用本机 `apps/tv/signing.properties` 与所引用的密钥文件；本机已有签名应妥善保管，后续覆盖安装需保持一致。不要把密码、证书私钥、账号 Cookie 或访问令牌提交到 Git。Android 手机/电视的“release”构建也不自动等于应用商店发布。

常见输出：`dist/bili-remote-mobile.apk`、`dist/bili-remote-tv-release.apk`，以及脚本生成的构建清单。以本次脚本的实际输出和 SHA-256 为准。

## 6. HarmonyOS 源码环境

安装 DevEco Studio 及所需 HarmonyOS SDK，按本人决定阅读并接受相应协议。使用独立 Flutter-OH SDK，保留 Android 的 `toolchains/flutter`：

```sh
python3 scripts/setup-flutter-ohos.py
```

本项目当前基线 Flutter-OH 3.41.9+ohos-1.0.2 / Dart 3.11.5。脚本默认安装到 `~/development/flutter-ohos`；需要自定义位置时使用 `FLUTTER_OHOS_HOME`。不要让该目录覆盖已有其他 SDK。

首次检出且尚无本机签名配置时，将 `ohos-poc/ohos/build-profile.example.json5` 复制为 `ohos-poc/ohos/build-profile.json5`。在 DevEco Studio 打开鸿蒙工程，配置自己的设备、调试证书和 Profile；使用自己的签名材料，不能复用维护者未公开的文件。活动签名配置不入 Git。

macOS 的开发构建示例：

```sh
cd ohos-poc
HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
~/development/flutter-ohos/bin/flutter pub get

HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
~/development/flutter-ohos/bin/flutter build hap --debug --no-pub --target-platform ohos-arm64
```

安装调试 HAP 的实际设备必须在签名 Profile 支持范围内；使用 DevEco 运行/安装。模拟器跑通不代表家庭真机上的自动发现、后台重连或硬件性能已验证。

正式发布前，必须把开发包标识改成本人在华为开发者中心登记的实际 `bundleName`，配置发布签名，核对 `ohos-poc/release-metadata.json` 的公开信息。可先使用本项目发布预检：

```sh
python3 scripts/build-harmonyos.py \
  --config ohos-poc/release-metadata.json \
  --bundle-name 你登记的实际包名 \
  --check-only
```

他人 fork 应改为自己的运营者、联系邮箱、对应源码及政策地址；不要沿用维护者公开信息冒充同一运营者。预检通过后去掉 `--check-only` 才实际构建 release APP；开发包标识或签名未完成时，应先处理具体缺项。

## 7. 模拟器联调边界

Android 与鸿蒙模拟器可能不在同一广播网络。联调可以用开发工具转发控制端口，再手动连接；端口转发不用于证明真实 Wi-Fi 自动发现成功。具体例子见[鸿蒙端 README](../ohos-poc/README.md#模拟器联调)。

至少记录：双方实际版本、连接方式、是否真正播放、A/B 切换与同步结果、断线和返回行为。不要把 HTTP 响应正常、截图或构建成功写成所有功能都通过。

## 8. 可选开机恢复与性能说明

电视“网络”设置保留开机自启与保持 ADB 的相关选项，厂商系统可能限制。只有明确需要并了解系统授权用途时，才按实际包名授予 `WRITE_SECURE_SETTINGS`、悬浮窗或通知监听等可选能力；这不是基本遥控安装的必需步骤。不要为适配而替换系统桌面、禁用厂商组件、刷机或 root。

音量拖动在共享控制层合并发送，进度拖动主要在松手后跳转；状态通过电视回传。弹幕和高分辨率视频的性能取决于电视 CPU、解码器及实际内容，仓库不保证所有设备、4K 或密集弹幕场景零掉帧。

需要继续开发时，可将[AI 搭建指引](ai-setup.md)和实际设备信息一起交给协作工具。
