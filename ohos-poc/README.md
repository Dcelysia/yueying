# 跃映（Yueying）鸿蒙手机端

鸿蒙手机端以独立名称“跃映 / Yueying”发布；Android 手机端和电视接收端名称不变。图标来源及生成记录见 `assets/branding/README.md`。

第一版只负责 B站浏览与电视控制，不包含手机本地视频播放器。Android 手机端继续保留原有本地播放能力。

## 功能

- Android 风格的双列首页（推荐/热门）、独立搜索/视频结果页、详情与分 P、我的、收藏夹及观看历史。
- 可选 B站官方网页扫码登录，账号凭据只保存在手机应用私有目录；退出登录会删除本地登录凭据。
- 自动发现电视、固定地址兜底、手动 IP 连接与保存后的自动重连。
- 全屏电视占位播放器：进度、暂停、选集、音量、画质、倍速、弹幕和赞助片段跳过。
- 进入电视控制页面只读取当前状态；多手机连接时跟随同一电视播放，不重新加载旧视频。

手机发送视频编号、分 P 和起播位置，电视使用自己的登录态取流。遥控协议不传手机的 B站凭据或视频流；手机退出不停止电视。

## 代码共享

`../packages/bili_remote_core` 是 Android 与鸿蒙共同依赖的 Flutter 包，包含自动发现、WebSocket 协议、重连、播放状态以及进度/音量控制。Android 通过现有路径的薄适配注入本地播放器释放和原生按键；鸿蒙不引入本地播放器。

浏览页面在 `lib/browse/`，按 PiliPlus 现有接口和 WBI 算法适配，不依赖 Android 全量播放器和原生插件。它与 Android 的完整浏览页面尚未合并，不能称为全量 UI 共用。

## 开发

使用仓库脚本 `python3 scripts/setup-flutter-ohos.py` 安装独立 Flutter-OH SDK。不要替换 Android 的 `toolchains/flutter`。本机基线为 Flutter-OH 3.41.9+ohos-1.0.2 / Dart 3.11.5。

首次检出后，将 `ohos/build-profile.example.json5` 复制为 `ohos/build-profile.json5`，然后用 DevEco Studio 配置本机签名。模板不含证书、密码或设备标识。现有开发 bundleName 是 `com.example.ohos_hello`；正式邀测前需要登记最终应用身份并重签。

```sh
cd ohos-poc
HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
~/development/flutter-ohos/bin/flutter pub get

HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
~/development/flutter-ohos/bin/flutter build hap --debug --no-pub --target-platform ohos-arm64
```

`EntryAbility` 通过小型原生通道提供应用私有存储目录；Dart 先初始化 Hive，再恢复遥控和账号数据。仅申请 INTERNET 与 GET_NETWORK_INFO，没有相机、麦克风或公共文件读写权限。扫码登录是显示二维码供 B站 App 扫描，不使用本机相机。

## 模拟器联调

虚拟机通常不在同一广播网络，跨虚拟机自动发现不可由端口转发验证。可先将 Android 电视的 9838 转发到宿主 19838，再用鸿蒙 hdc rport 将虚拟机 9838 转到宿主 19838，在鸿蒙手动连接 127.0.0.1:9838。真实家庭 Wi-Fi 的 UDP 自动发现仍需真机验证。

许可证沿用 GPL-3.0，见 LICENSE。发布准备见 `../docs/harmonyos-release.md`。
