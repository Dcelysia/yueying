# 跃映 · HarmonyOS 原生版

版本 **1.0.2（9）**，包名 `com.dcelysia.yueying`。这是跃映的 ArkTS / ArkUI / UIDesignKit 实现，替代旧 `ohos-poc` Flutter 鸿蒙实现；原项目历史保留。Android 的 Flutter 和电视接收端不随本次迁移改变。

## 功能与边界

推荐、热门、搜索、详情与选集；可选 B站扫码登录、收藏、历史、关注与动态；局域网发现、连接、前台重连；占位播放器、横屏、音量、进度、倍速、画质、弹幕与赞助片段设置；多手机状态同步和系统分享链接接收。手机不在本地播放、下载或中转视频流，电视使用独立接收端与自己的账号获取视频。

页面保留内容来源提示和在哔哩哔哩打开入口。项目非哔哩哔哩官方产品，来源标注不等于接口、商标或内容授权；开源许可只覆盖各自授权范围内的代码。

## 在 DevEco Studio 打开

需要 DevEco Studio 26、HarmonyOS 7 / API 26 SDK。鸿蒙构建不依赖 Flutter-OH。先在本目录执行：

```sh
cp build-profile.example.json5 build-profile.json5
```

然后在 DevEco Studio 打开本目录。`build-profile.json5` 是被 Git 忽略的本机配置；通过 Signing Configs 配置自己的开发证书与设备 Profile，确认当前 product 的 `signingConfig` 指向已有签名。真机安装必须使用签名后的 HAP。`debug` 构建不等于自动签名。

覆盖已有安装时，包名、签名证书、Profile 授权身份必须匹配，版本号不能倒退；不要为了安装而卸载旧版或清除数据。AppTest 必须使用对应的市场发布签名，不能上传设备开发签名包。

## 构建与公开资料

常规开发可由 IDE 构建 entry；正式发布使用仓库根目录的 `scripts/build-harmonyos.py`，详见[发布说明](../../docs/harmonyos-release.md)。签名、真实运营者、联系邮箱与政策 URL 只放本机私有配置，禁止提交。原生内置政策模板位于 `entry/src/main/resources/rawfile/`，发布时替换占位符。市场隐私托管包通过 AppGalleryKit 核对系统当前政策 ID、版本和明确同意结果后初始化；不再重复弹本地首次同意页。应用内隐私入口查询系统托管链接，用户协议仍可在应用内阅读。只有明确不支持托管的开发环境才使用离线同意流程，托管读取失败不能降级绕过。撤回会先停止处理并清除本机数据，再撤回系统同意；未完成时保持阻断并允许重试。

默认正式包名不显示模拟器假账号入口；专用预览包才允许本地演示数据。演示数据与截图不能作为真实账号或网络功能通过的证明。构建通过也不等于商店审核通过或所有设备均无卡顿。

## 模拟器联调

电视协议默认端口 9838，HTTP 与 WebSocket 均直接连接局域网电视；ADB/HDC 只用于开发安装和可选端口转发。模拟器端口转发不能证明真实 Wi-Fi 自动发现成功。使用自己的 IP/端口，不把遥控端口暴露到公网。

至少验证：A 开始播放，B 连接后进入现有控制页不重播；A 切视频、暂停或调节参数时 B 同步；分享分 P 与历史续播、前台重连、实体音量键、全屏返回和停止播放。记录真机与模拟器边界，不把 HTTP 正常等同于完整播放验证。

## 来源与许可

本改版由 dcelysia 维护，在跃映、[PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 派生实现基础上二次开发，业务请求与控制代码遵循 GPL-3.0，保留原作者版权与许可证。电视端基于 [NeoBV](https://github.com/b1ackmarket/NeoBV)，保留其 MIT 许可。原生系统组件用法参考华为文档和 [chai 的 BiliMusic](https://github.com/chai2shi-spec/BiliMusic)。见 [LICENSE](LICENSE)、[开源说明](entry/src/main/resources/rawfile/NOTICE.md)及根目录来源记录。
