# HarmonyOS 原生版构建与 AppTest

## 当前实现

鸿蒙入口是 [`apps/harmony`](../apps/harmony)，使用 ArkTS / ArkUI / UIDesignKit，最低 HarmonyOS 7 / API 26。版本 1.0.2（9），默认包名 `com.dcelysia.yueying`。Android 手机继续使用 Flutter；两种手机端使用同一电视遥控协议，但原生鸿蒙不再加载 Dart/Flutter-OH。

手机提供浏览、可选 B站扫码登录、收藏、历史、动态、分享链接接收与电视控制。手机不在本地播放、下载或中转媒体流；独立电视端使用自己的账号获取并播放视频。来源标注、外部打开入口与开源许可均不代表获得第三方平台、内容或商标授权，审核通过也不代替相关授权。

## 开发安装与覆盖升级

1. 安装 DevEco Studio 26 和 API 26 SDK，自行阅读接受所需协议。
2. 复制 `apps/harmony/build-profile.example.json5` 为 `apps/harmony/build-profile.json5`，在 IDE 打开 `apps/harmony`。
3. 配置自己的开发证书、设备授权 Profile，并确认 product 的 `signingConfig` 对应已存在的签名配置。
4. 真机安装签名 HAP；`unsigned.hap` 不能代替签名包。

同一应用覆盖安装要求包名、签名证书、Profile 授权身份及版本递增符合系统要求。开发签名 HAP 与市场发布签名 APP 的用途不同；不要为解决签名不匹配而直接卸载用户版本或清除数据。

## 权限、政策与资料

当前原生模块申请 `ohos.permission.INTERNET` 和 `ohos.permission.GET_NETWORK_INFO`，用于 B站请求、图片请求和局域网连接/网络状态能力。没有申请相机、麦克风、定位、通讯录等权限；二维码由 B站客户端扫码，不是本应用调用相机。

内置隐私政策与用户协议模板位于 `apps/harmony/entry/src/main/resources/rawfile/`。同意前不启动浏览、发现或自动重连。选择华为隐私托管时，应用通过 AppGalleryKit 查询系统返回的政策 URL，并逐条校验当前 ID、版本及 FULL_MODE_AGREED；系统变更或拒绝同意时停止服务。托管模式不重复显示本地首次同意页，内置用户协议仅供阅读，不伪造系统同意记录。明确不支持托管的开发环境才保留本地离线同意；已知托管服务失败时不降级。应用返回前台会做一次轻量授权复核，撤回失败会阻断服务并支持重试。真实运营者、联系邮箱和公开政策地址必须由实际发布者填写；不能借用他人身份。政策可使用华为的隐私声明托管服务，最终链接应与审核资料和实际应用一致。

本机私有元数据 JSON 示例（不要把真实资料提交到仓库）：

```json
{
  "BILI_REMOTE_OPERATOR": "实际运营者",
  "BILI_REMOTE_CONTACT_EMAIL": "实际公开联系邮箱",
  "BILI_REMOTE_SOURCE_URL": "https://github.com/你的账号/你的仓库/tree/与包一致的提交或tag",
  "BILI_REMOTE_PRIVACY_URL": "https://你的正式隐私政策地址",
  "BILI_REMOTE_TERMS_URL": "https://你的正式用户协议地址"
}
```

源代码、版本及许可应与分发二进制对应。签名文件、密钥、密码、设备标识、实名和联系资料不进入 GitHub 源码或历史；使用本机私有目录保存。原生源码中的模板是开发材料，不可把占位符当成正式隐私政策上传。

## 市场 release APP

先在华为后台登记实际应用身份，并在本机 `build-profile.json5` 配置市场发布签名及对应 product。配置密码使用 DevEco 所支持的格式，不将原始密码写入公开源码。

在仓库根目录执行：

```sh
python3 scripts/build-harmonyos.py \
  --config /absolute/private/release-metadata.json \
  --bundle-name com.dcelysia.yueying \
  --product default --check-only

python3 scripts/build-harmonyos.py \
  --config /absolute/private/release-metadata.json \
  --bundle-name com.dcelysia.yueying \
  --product default
```

脚本使用 DevEco 自带 Node、Hvigor 和 JSON5 解析器；默认 macOS 路径可通过 `--deveco-home` / `DEVECO_HOME` 改写。它在私有临时副本注入政策资料，原源码模板不变；release APP 校验包名、版本与 `debug=false` 后输出到 `dist/harmonyos/`。它不会替用户提交审核，也不能单凭签名名称判断 Profile 一定为市场发布用途，发布者仍须核对证书和 Profile 类型。

## AppTest 更新

在华为 AppGallery Connect 使用已登记应用，上传本次市场签名 `.app`，等待软件包合法性校验，再在 AppTest 创建或更新邀测版本，选择允许测试的设备/系统、群组和立即生效时间，补充真实测试方法与发布说明后提交。使用 API 26 的当前原生包不能宣称兼容旧 API 24 设备。

审核、测试开始时间、邀请码与可安装范围均以后台实际状态为准。上传成功、预检通过、旧版本已测试或应用管理的“准备发布”不能代替新版本审核结果。不要把家庭邀请码、设备资料或审核账号凭据放公开仓库；本仓库不发送邀请通知。

正式应用市场上架是另一流程，可能要求 APP 备案、主体及其他材料；AppTest 不意味着公开上架已经完成。请以平台当时表单和适用规则为准。

## 最小验收

记录本次源码 SHA、构建版本、包 SHA256、签名用途和真实设备；至少检查扫码确认后登录成功、首页头像、分享具体分 P/历史续播、多手机进入不重播及切换同步、播放/暂停图标、倍速/广告策略即时反馈、实体音量键和弹窗/面板音量一致、横竖屏及退出行为。模拟器或假账号数据只证明对应页面与操作，不是所有真实账号接口、电视性能或内容授权的证明。
