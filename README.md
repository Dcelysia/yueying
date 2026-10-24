# 跃映 · HarmonyOS 原生版

跃映的独立 ArkTS / ArkUI / UI Design Kit 迁移分支，版本 **1.0.2**。手机用于浏览和电视控制，视频由局域网电视接收端播放。

## 功能

- 推荐、热门、搜索、视频详情和选集；可选 B站二维码登录。
- 收藏夹、观看记录、关注、UP主空间和动态；动态支持收起与展开。
- 自动发现、保存电视、前台立即重连、手动 IP / 端口连接和固定地址兜底。
- 占位播放器、横屏全屏、进度、选集、倍速、画质、弹幕样式、赞助片段提示和自动跳过策略。
- 多手机同步同一电视；进入控制页不重新加载视频。实体音量键仅在前台且电视可控时接管。
- 系统分享接收 B站链接；待播内容在恢复电视连接后继续处理。
- 离线隐私政策、用户协议、开源许可与撤回同意。

## 构建和设备

需要 DevEco Studio 26、HarmonyOS API 26 SDK。目前最低系统为 **HarmonyOS 7 / API 26**。模拟器工程默认包名为 `com.dcelysia.yueying.nativepreview`，使用原生系统组件。

在 DevEco 中打开本目录，构建 entry 的 debug 或 release。默认不携带签名；真实手机需使用对应包名、已包含设备 UDID 的开发签名。AppTest 使用正式包名 `com.dcelysia.yueying` 及匹配的市场分发签名。

发布打包时在独立临时目录覆盖包名和签名配置，并用真实发布资料替换 `resources/rawfile` 中协议模板的占位符。证书、密钥、密码、实名发布资料和设备标识均不纳入源码。

## 演示与验证

模拟器预览包的登录页提供“使用演示账号（假数据）”，可查看本地收藏、历史、关注、空间与动态。演示入口仅对预览包名开放，演示视频不会向电视下发播放命令。真实登录流程保留。

已在 HarmonyOS 模拟器与 Android 模拟电视之间验证电视控制、倍速及策略切换、横屏设置、硬件音量键前后台行为、音量弹窗与面板一致、播放状态同步。已生成真实登录二维码；私人账号内容仍需用自己的账号联调。模拟数据不作为真实账号接口通过的证明。

## 来源与许可

本改版由 **dcelysia** 维护。项目在 [跃映](https://github.com/Dcelysia/yueying) 及 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 派生实现基础上二次开发，业务接口与请求签名代码沿用 GPL-3.0，保留上游作者版权与许可。详见 [LICENSE](LICENSE)。

电视接收端基于 [NeoBV](https://github.com/b1ackmarket/NeoBV)，保留其 MIT 许可与署名；本分支不改变原有电视及 Flutter 工作区。原生 HdsTabs 和系统材质用法参考华为文档及 [chai 的鸿蒙 BiliMusic](https://github.com/chai2shi-spec/BiliMusic)。本地演示 SVG 插画为本迁移分支制作。

本项目与哔哩哔哩官方无关。第三方内容、接口及商标权利归相应权利人。
