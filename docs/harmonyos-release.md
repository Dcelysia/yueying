# 鸿蒙家庭测试与发布说明

核对日期：2026-10-24。使用个人华为开发者账号，本次只走 AppTest 邀请测试，不另外发起公开上架。

当前实际状态：已创建跃映 APP ID，上传并关联正式签名的“仅测试”APP，已通过本人手机号验证并关联家庭群组，已提交 AppTest 邀请测试。后台版本列表及状态页显示“正在等待审核”；提交时进入自动预审，通过后自动交由审核团队处理。软件包合法性已达标，上架自检仍显示“检测中”。未审核通过或发布测试版本，未发送测试通知。

## 当前工程与第一版边界

鸿蒙入口位于 `ohos-poc/`，使用 Flutter-OH。第一版支持推荐、搜索、视频详情和分 P、收藏夹、观看历史、可选扫码登录，以及电视发现、连接和全屏遥控；不引入手机本地播放器及其原生依赖。Android 手机仍位于 `apps/mobile/`，保留本地播放。两端实际共同依赖 `packages/bili_remote_core/` 的发现、协议和同步状态；浏览 UI 尚未全量共享。

源码已经纳入 Git，依赖目录、构建产物、本机签名及活动 `ohos/build-profile.json5` 排除。提供无签名的 `build-profile.example.json5`，首次检出后复制并在 DevEco 配置自己的签名。当前正式包名为 `com.dcelysia.yueying`、版本 `1.0.0+1`，已完成独立发布签名；`com.example.ohos_hello` 仅是此前模拟器开发包的标识。本轮正式包已上传并提交邀请测试审核。

## 家庭使用的分发路径

**可以先做邀请测试，不必先公开上架正式版。** 华为[分发入门](https://developer.huawei.com/consumer/cn/appgallery/devstart/)明确支持在正式发布之前选择特定用户群组测试 HarmonyOS 应用。本项目已完成 APP ID 登记、正式仅测试包上传及首轮家庭 AppTest 邀请测试提交，当前正在等待审核。后台已生成本版本分享链接和二维码；这不表示版本已审核通过或可以安装。其他应用的邀测链接不能复用于本项目。

| 路径 | 本项目用途与限制 |
| --- | --- |
| DevEco 调试安装 | 个人账号实名认证后，将家人的实际设备加入调试 Profile，安装签名 HAP。适合先验证少量设备；受设备列表与 Profile 有效期限制。 |
| AppTest 邀请测试 | 家人自行安装和接收测试更新的目标路径。选择定向群组、提交邀请测试版本并审核；不等于公开正式上架。 |
| HarmonyOS 应用内部测试 / 指定设备发布 | 与 AppTest 的“内部测试群组”不是同一个概念；不得从名称推定个人账号具备企业分发或免审资格。 |

公开文档提供内部、外部测试群组入口，但本次未找到能证明“个人账号内部群组一律免审”的现行官方说明。**以个人账号实际控制台的入口、资格和提示为准**；若不具备内部群组条件，使用面向家人的外部定向邀请测试。旧 AGC Android 开放式测试的配额或免审规则不作为本项目 HarmonyOS AppTest 的依据。

### 提交流程与家人安装入口

1. 从[华为开发者联盟](https://developer.huawei.com/consumer/cn/)登录 HarmonyOS 开发者中心并完成个人实名认证，创建 HarmonyOS 应用。记录平台生成的 APP ID，并登记最终应用名称及包名。
2. 按下节准备发布包并上传，等待基础包检测通过。在版本管理创建版本，上架类型选择“邀请测试”，填写测试说明、测试时间、审核及隐私信息。实际必填项、资质和备案校验以该应用表单为准。
3. 在 **应用管理 → 分发 → 应用测试 → 测试用户** 创建群组，添加家人的华为账号，关联本次测试版本。上述入口和“邀请测试需提交审核”来自[华为应用市场官方流程](https://developer.huawei.com/consumer/cn/appgallery/)。控制台改版时按同名功能查找。
4. 检查最终提交页后提交审核；保留版本号、提交状态和任务标识。只有平台显示审核通过、版本已发布且到达测试开始时间，才通知家人安装；不承诺固定审核时长。
5. 复制控制台实际生成的邀请入口或邀请码。家人使用获邀华为账号，在 AppTest 右上角头像 → 兑换邀请输入邀请码；如收到链接则按页面加入。华为[现行 AppTest 说明](https://consumer.huawei.com/cn/support/content/zh-cn16046464/)提示正在逐步改为仅发送邀请码，不能保证每次都有 BiliMusic 那种网址。
6. AppTest 若尚未安装，按[官方获取说明](https://consumer.huawei.com/cn/support/content/zh-cn16046461/)由邀请页面引导安装；不要把 Android APK 的 Wi-Fi 下载地址发给鸿蒙用户作为安装入口。测试版使用最长 90 天，后续更新与停止规则见[AppTest 介绍](https://consumer.huawei.com/cn/support/content/zh-cn16046463/)。

### 提交前材料与尚待确认项

以下是本项目的准备清单，不把尚未打开的控制台字段冒充已确认的必填项。

| 材料 | 准备要求 / 需要本人确认的信息 |
| --- | --- |
| 应用身份 | 最终名称、独立图标、简介、真实分类、截图；最终 `bundleName`、平台 APP ID 与发布签名身份相对应。开发用 `com.example.ohos_hello` 不能直接当作已经登记的正式身份。 |
| 发布软件包 | 构建 release APP 并完成发布签名及包检测；检查版本号、最低系统版本、包名和调试标识。开发 HAP 只用于开发安装，不因改扩展名而成为发布 APP。 |
| 签名材料 | 配套密钥库、发布证书与发布 Profile；`build-profile.json5` 的签名方案指向这些真实文件。签名密码、私钥、Profile 不入 Git。若当前 DevEco 提供发布自动签名，先核对生成材料的类型，不能把调试自动签名当成发布签名。 |
| 隐私声明 | 独立政策文本，真实运营者/个人信息处理者名称、可联系邮箱、处理目的/方式/范围、第三方服务和删除方式。提供审核人员可访问的 HTTPS 页面；也可优先使用控制台提供的标准化隐私声明托管服务。应用内文本、托管文本和实际网络行为保持一致。 |
| 测试信息 | 测试目的、时间、家人华为账号、接收端安装及同网连接步骤；根据表单填写审核联系人。没有这些真实信息时不能用占位姓名、邮箱或随机账号代填。 |
| 开源交付 | 手机 GPL-3.0、电视 MIT 及实际第三方组件声明；对应发布版本的可访问源码地址和获取方式。不能把上游仓库地址写成本项目修改版本的对应源码。 |
| 备案和类别资质 | 华为分发入门要求按实际业务履行备案和适用资质要求。本次没有查到本项目“家庭邀请测试”免除备案或内容授权核验的官方依据，也不声称该测试表单一定强制所有资质。以账号、应用类别及表单审核结果确认，缺少资料时不虚填备案号。 |
| 第三方内容来源 | 如实写明 B站接口、账号及图片服务的实际用途、手机不播放及电视端的职责；开源许可证与 B站内容/品牌授权分开核对，按审核要求提供真实材料。其他项目存在邀请测试不等于本项目已获授权或审核保证。 |

发布包格式依据[华为提交 HarmonyOS 应用指引](https://developer.huawei.com/consumer/cn/app/submit)；签名配置字段依据[工程级 build-profile.json5 文档](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-hvigor-build-profile-app)（页面更新时间 2026-10-08）。本项目身份登记、发布签名与测试包上传现已实际完成；该指引不代替后台的最终校验与审核。

## 权限声明与用途

当前 `ohos-poc/ohos/entry/src/main/module.json5` 保留/补齐以下两个权限：

| 权限 | 用途 |
| --- | --- |
| `ohos.permission.INTERNET` | 在局域网发现电视、读取接收端信息并通过 HTTP/WebSocket 发送用户操作。若版本包含互联网功能，也必须披露相应用途。 |
| `ohos.permission.GET_NETWORK_INFO` | 获取网络连接状态，用于连接变化后的提示和重连；适配后的 connectivity 插件调用相应网络 API 时需要。 |

这两项按系统授权权限使用，不为它们制作相机/定位式运行时授权弹窗，也不申请 ACL 高等级权限。应用内仍应提供与实际行为一致的隐私说明。

目前不因遥控需求新增定位、相机、麦克风、通讯录、图片读写、Wi-Fi 配网或分布式数据同步权限。后续若使用扫码、SSID/BSSID 或专门的分布式 API，先核对对应功能和 SDK 版本再申请，不能提前堆权限。

## 审核说明文案

下段适用于本次“浏览＋电视控制”版本，正式提交前补齐接收端部署与演示材料：

> 本应用是一款开源的家庭视频浏览与电视控制工具，与哔哩哔哩官方无关。用户可浏览、搜索视频，按需通过 B站官方网页扫码流程登录，查看收藏夹与观看历史，并将所选视频编号发送给同一局域网内由用户自行安装的电视接收端。电视使用自身登录状态获取和播放视频；手机不进行本地视频播放，不中转视频流，不向电视发送 B站登录凭据。手机可同步查看电视状态并调节播放、进度、选集、音量、画质和弹幕。本次测试仅邀请指定家庭成员。

审核人员无法直接访问家中的 `192.168.*` 电视。为让本项目可复核，准备以下真实材料；这是针对本项目局域网依赖的提交建议，不宣称华为对所有同类应用固定要求同一份演示材料：

- 一段真实录像：Android 手机 A 已让电视播放 → 鸿蒙 B 连接同一电视 → B 打开现有占位播放器及全屏控制页 → 调节进度、音量、选集 → A 切视频，B 的标题与进度同步。进入控制页不得触发重播或重置进度。
- 接收端版本、安装包/对应源码获取方式、Android 电视或模拟器安装步骤、同网发现和手动 IP 连接说明。测试设备按审核人员可搭建的环境描述，不能只给家中的固定 IP。
- 未连接时仍能真实检查推荐、搜索、详情和可选登录，遥控入口明确提示连接条件；不能伪造在线设备或播放成功状态。实际录像可以说明已验证能力，不能替代控制台要求的可运行测试环境。

若审核反馈需要可访问测试环境或补充测试账号，按其反馈补充，不擅自把家庭电视控制端暴露到公网。

## 浏览与电视控制版本隐私说明底稿

正式提交前补齐实际运营者名称、联系邮箱、对应版本公开源码地址与生效日期。隐私政策推荐使用审核人员可访问的 HTTPS 地址，也可使用控制台的标准化托管服务；是否接受具体地址以提交校验为准。下面不是已经发布的正式隐私政策。

- 为发现和连接电视，处理局域网设备地址、设备标识/名称、连接标识以及用户选择的电视信息；为展示和操作播放，处理电视返回的视频标题、视频编号、进度、音量等状态。
- 连接记录保存在设备本地，用于下次连接。说明哪些记录可通过应用内入口清除；若暂时只能通过系统清除应用数据删除，必须如实说明，不能宣传尚不存在的删除按钮。
- 连接信息及控制命令发送给用户选定的局域网电视接收端。当前遥控协议使用局域网 HTTP/WebSocket；不应宣传为端到端加密。仅在可信网络使用。
- 浏览、搜索、视频详情等请求发送至 B站接口；可选登录使用 B站官方网页扫码流程，不收集 B站密码。会话 Cookie 保存在应用私有目录，用于本人账号的收藏夹、历史与续播查询；退出登录删除本地凭据。账号退出不停止电视播放。
- 视频封面从 B站图片服务获取；遥控连接标识与 B站登录凭据分开，登录 Cookie 不通过遥控协议发送到电视或项目自建服务器。账号、观看记录、请求行为仍需按实际第三方服务说明披露，不能写成“完全不联网”。
- 本地遥控不必接入广告、统计或崩溃上报 SDK。若正式构建实际包含此类 SDK，必须按实测行为披露，不能仅因“开源”而写成不收集数据。
- Flutter、GetX、Hive 和适配后的网络插件等依赖应列入第三方组件和许可证清单。开源依赖与会收集数据的 SDK 应按各自实际行为说明。

## 开源与品牌

手机代码上游 `apps/mobile/LICENSE` 为 GPL-3.0；电视代码 `apps/tv/LICENSE` 为 MIT。复用/分发时保留对应的许可和版权声明；从手机端复制的 GPL 派生代码，不能仅因换成鸿蒙壳就改称全部 MIT。分发 GPL 派生二进制时提供相应版本的许可证和对应源码。

“源码开源”不等于获得哔哩哔哩接口、商标或视频内容授权。应用名称、图标和介绍应准确说明独立项目身份，不使用使人误认为官方出品或官方合作的表述。缺少必要授权时，不通过改名或隐藏入口来规避审核。

## 官方参考

- [华为应用市场分发入门与备案、资质、隐私要求](https://developer.huawei.com/consumer/cn/appgallery/devstart/)
- [华为应用市场：邀请测试群组、发布与停止测试](https://developer.huawei.com/consumer/cn/appgallery/)
- [提交 HarmonyOS 应用：发布 APP 软件包](https://developer.huawei.com/consumer/cn/app/submit)
- [工程级 build-profile.json5：签名证书、Profile 与产品包名](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-hvigor-build-profile-app)
- [AppTest 邀请参与、兑换邀请码与停止测试](https://consumer.huawei.com/cn/support/content/zh-cn16046464/)
- [AppTest 安装方式](https://consumer.huawei.com/cn/support/content/zh-cn16046461/)
- [AppTest 测试类型、支持系统与有效期](https://consumer.huawei.com/cn/support/content/zh-cn16046463/)
- [测试群组 API：AppTest 内部群组能力及支持入口](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/agc-help-test-api-query-test-user-0000002664997773)
- [DevEco Studio 自动签名](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-auto)
- [HarmonyOS 应用内部测试（独立于邀请测试的分发入口）](https://developer.huawei.com/consumer/cn/doc/app/agc-help-harmonyos-internaltest-0000001937800101)
- [网络连接 API 与 GET_NETWORK_INFO 权限](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V3/js-apis-net-connection-0000001333720849-V3)；同时对照了本机当前 SDK 的 `@ohos.net.connection.d.ts` 权限声明。
- [华为开发者服务协议](https://developer.huawei.com/consumer/cn/devservice/ServiceAgreement/)
- [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.html)

## 当前代码的协议入口与发布命令

首启同意前只初始化本机存储和读取内置文件；同意后才创建浏览客户端及恢复电视连接。“我的 → 关于与隐私”可离线阅读隐私政策、用户协议、第三方 NOTICE 及许可证，也可退出登录、清搜索/电视连接或撤回同意。清理连接不会停止电视播放。

正式发布的公开信息模板为 `ohos-poc/release-metadata.example.json`。复制到已忽略的 `.private/harmonyos-signing/release-metadata.json`，填写本人确认的运营者、邮箱、对应源码、隐私政策及用户协议 HTTPS 地址；身份联系配置留在本机，签名密码不得写入该文件。公开政策正文与应用内 `assets/legal/` 内容保持一致，可使用华为提供的隐私声明托管服务，或发布到自己的 HTTPS 网站。

先在华为后台登记应用身份，将 `ohos-poc/ohos/AppScope/app.json5` 的 bundleName/vendor 设置为自己的真实值，并在 DevEco 配置匹配的发布证书和发布 Profile。然后执行：

```sh
export HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
python3 scripts/build-harmonyos.py --config /absolute/path/release-metadata.json --bundle-name <登记的包名> --check-only
python3 scripts/build-harmonyos.py --config /absolute/path/release-metadata.json --bundle-name <登记的包名>
```

脚本只检查公开信息及本机包名一致性，不替代华为的签名、备案、内容授权或审核校验。上传 Flutter 构建日志所列出的 release `.app`，不要上传本文验证用的 debug HAP。当前示例配置会被构建前检查拒绝；运行时 release 也会拒绝未填写公开资料的版本。

本次已完成华为后台登录、真实应用登记、独立发布签名、正式仅测试包上传和 AppTest 邀请测试提交。实际状态为“正在等待审核”，不是准备提交草稿，也不是审核通过。后台已生成版本分享入口，未向家人发送。实际登记与审核状态见下节。


## 2026-10-24 已登记的跃映与已提交邀请测试

后台实际确认：名称“跃映”，HarmonyOS 应用，默认语言简体中文，登记支持设备仅手机。应用商店分类为“影视与直播”，主标签“视频”、附加标签“投屏”，不以工具分类隐藏视频浏览用途。

| 项目 | 实际值 |
| --- | --- |
| 已登记正式包名 | `com.dcelysia.yueying` |
| 邀测版本 | 首轮家庭联调，正在等待审核 |

具体应用、项目、测试版本及签名记录保存在本机私有发布记录中。本人可登录[HarmonyOS 开发者中心](https://developer.huawei.com/consumer/cn/)，进入“应用管理 → 分发 → 应用测试”查看对应版本；不在公开文档重复展示账户后台的定向入口。

已保存非敏感草稿内容：最终白底红图（`dist/harmonyos/appgallery-icon-1024.png`，由原图正常缩放）、真实应用介绍、测试说明、电视依赖与可选登录审核备注、本人在后台确认的真实负责人联系资料。本文不重复展示审核负责人实名。介绍明确基于 PiliPlus、NeoBV 等开源项目二次开发并保留原作者版权和许可证，未声称原作者许可等于获得 B站内容、商标或接口授权。后台应用信息与邀测资料的图标已分别上传并保存。

正式 `.app` 已上传并关联本草稿；测试时间已保存为 2026-10-25 00:00:00 至 2026-11-08 00:00:00，设备为手机、地区为中国大陆，软件包选择不额外加密。公开隐私政策已填写，用户协议与对应源码已放入审核备注。本人现已完成手机号验证，第一步校验通过；已关联外部“家庭邀测”群组，发送测试通知选择“否”。后台要求设备型应用提供自测文件，可上传不超过15 MB的docx或mp4，总文件数最多5个、总大小不超过500 MB；如需补充自测文件，使用实际联调录像，不能把未验证的能力写成已通过。此前用于模拟器的开发 HAP 采用 `com.example.ohos_hello` 和开发 Profile，不等于正式发布身份，不应上传作为审核包。

负责人手机号、验证码和测试成员账号不写入本仓库，也不由代理猜填或发送给他人。手机号及短信验证由本人完成。随后已提交 AppTest 邀请测试，未发起公开上架、未发布测试版本。

后台已创建外部测试群组“家庭邀测”，当前0人，未添加任何成员。添加方式支持单个华为账号邮箱/手机号、批量导入和邀请码。邀请码添加界面显示有效期30天，可指定人数（上限10000）；实际家庭使用应按家人人数设定，不向无关人公开。当前尚未生成邀请码。本次测试版本已经关联该群组；后续由本人决定实际家人账号或小人数邀请码，不自动联系成员。

### 正式发布签名与构建切换

本次已新建独立发布密钥、发布证书和普通发布 Profile，保留原 `auto_debug` 调试证书。后台证书与 Profile 均名为 `yueying-release-20261024`、生效至 2029-10-24；Profile 类型为“发布”，绑定 `com.dcelysia.yueying` 与实际 APP ID。已验证：本机密钥库公钥、下载 CER 叶证书及 Profile 内嵌证书一致；Profile 的 CMS 签名可解码验证，类型 `release`、APP ID 和包名均匹配。

1. 在 DevEco Studio 创建一套独立的发布密钥库和 CSR，保留现有开发密钥与配置。私钥、密码留在本机安全位置，不提交仓库。
2. 打开[开发者管理 → 证书](https://developer.huawei.com/consumer/cn/hdc-console/#/home/9249519184596237889)，新增证书，填写发布证书名称，选择“发布证书”，上传步骤1产生的 CSR，创建后下载 CER。后台只需要公开 CSR，不上传私钥或密钥库。
3. 打开[开发者管理 → Profile](https://developer.huawei.com/consumer/cn/hdc-console/#/home/172249065903274468)，添加，选择自己登记的“跃映”应用，确认包名，填写 Profile 名称，选择普通“发布”类型并绑定上一步发布证书，添加后下载。该普通发布 Profile 不使用开发设备列表；不把“调试”或“指定设备发布”冒充普通应用市场发布。
4. 在本机单独的 release 签名配置中引用匹配的发布密钥库、证书和 Profile，并使用登记的正式包名。配置及产物不得覆盖现有开发配置，不提交包含密钥/密码的文件。
5. 公开政策和源码配置完整后，使用构建脚本生成 release `.app`，验证包名/版本/签名类型后上传软件包管理，再将该包关联到“首轮家庭联调”草稿。

本机正式构建配置已准备：

- 根 `.gitignore` 显式忽略 `/.private/`，并已用 `git check-ignore` 验证。所有密钥、密码、CSR、CER、Profile 和密码加密材料只放在 `.private/harmonyos-signing/`，不纳入 Git。目录权限 700，秘密文件权限 600。
- `yueying-release.p12` 是独立 EC secp256r1 发布密钥库，别名 `yueying-release`；密码只存本机 `signing.properties` / `.keystore-password`，命令通过 passwordfile 读取，不打印密码。
- `yueying-release.cer`、`yueying-release.p7b` 分别是后台下载的发布证书与普通发布 Profile。
- 原 `ohos/build-profile.json5` 已原样备份为私有 `build-profile.debug.json5`；新的 `build-profile.release.json5` 和当前被忽略的 `ohos/build-profile.json5` 均为严格 JSON，产品 default 绑定 `yueyingRelease`。modules、compatibleSdkVersion、targetSdkVersion 与公共模板一致。
- 当前 AppScope 正式包名为 `com.dcelysia.yueying`、版本 `1.0.0+1`，签名身份与实际后台登记匹配。恢复 debug 配置时还必须让应用身份与原 debug Profile 对应；不要只换签名文件，也不要覆盖任一备份。
- Hvigor 要求密码使用其配套 `material/` 的加密格式，不能将原始密码直接粘入 signingConfigs。本次生成独立密码加密材料，已用本机官方 `DecipherUtil.decryptPwd` 回环验证，发布配置不依赖旧 debug 加密材料。

正式 release `.app` 已构建、校验包名/版本/发布签名及不可调试标志，提取的 release HAP 已在鸿蒙模拟器安装启动；正式 APP 已上传用于 AppTest 邀测，原开发 HAP 未作为审核包。


### 当前上传包与审核状态

- 上传文件：`dist/harmonyos/yueying-harmony-1.0.0-release.app`，11,491,116 字节。
- SHA256：`8953f87518f4b44408f265468fb2f112ee9cccd8830220feffc810cc153094f4`。
- 后台识别：`com.dcelysia.yueying` / `1.0.0（1）` / 手机 / 仅测试；软件包合法性“已达标”。上架自检任务已启动，最后查看仍为“检测中”，不能写成自检通过。该自检不等于提交公开上架。
- 对应源码：[harmony-v1.0.0-preview.1](https://github.com/Dcelysia/yueying/tree/harmony-v1.0.0-preview.1)。公开源码保留完整业务实现、构建方式及原许可证；发布者身份资料使用本机构建配置，实际提交包与签名记录另存本机。
- 已上线页面：[主页](https://dcelysia.github.io/yueying/site/)、[隐私政策](https://dcelysia.github.io/yueying/site/privacy.html)、[用户协议](https://dcelysia.github.io/yueying/site/terms.html)。自定义隐私政策方式下表单没有独立用户协议输入框；协议地址已放入审核备注并可在应用内阅读，未把协议地址冒填到“隐私权利”字段。
- 本人已完成负责人手机号短信验证；已关联“家庭邀测”群组并关闭测试通知，邀请测试已提交。手机号与验证码不记录在本仓库。
- 群组仍是0人，未生成群组邀请码、未发送邀请。平台“生成二维码”正常下载6张二维码，实际解码均是本版本的 taskId 分享链接，不含 invitationCode；只保存在后台及被忽略的本机产物目录，不把可加入家庭的链接、二维码或口令写入公开仓库。自测文件未上传，若审核要求补充，则按真实录像处理。

所有必填信息已通过平台校验并保存，AppTest 邀请测试已提交。最后查看版本列表与详情页均为“正在等待审核”，软件包上架自检仍在运行；没有撤销审核，也未向家人发送通知。平台提交时说明自动预审通常约30–40分钟，预审通过会自动提交审核团队，失败会返回检测报告；该时间仅是平台提示，不是审核通过承诺。
