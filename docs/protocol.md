# Bili Remote 协议 v1

默认端口 9838。`GET /remote/v1/info` 返回协议版本、设备编号和名称，用于验证 SSDP 发现的设备；不返回账号信息。

`ws://<电视IP>:9838/remote/v1` 建立持续连接。手机只接受私有、链路本地或回环 IP；遥控连接与 B 站账号登录互相独立。

## 免配对连接

首条消息必须在十秒内发送：

```json
{"type":"hello","protocol":1,"clientId":"phone-unique-id"}
```

电视直接接受有效的 clientId，无需 PIN、token 校验或电视端确认。电视返回 `welcome`，包含协议版本、deviceId、name、token；token 保留用于协议兼容，不作为访问限制。同一局域网内能访问服务的设备均可遥控。手机保存成功连接的电视身份和地址，下次启动自动重连；用户主动断开时停止自动连接。

## 从官方 App 分享

Android 手机端接收 `ACTION_SEND` 的 `text/plain` 内容，识别 B 站视频、番剧和 `b23.tv` 分享链接。短链匿名展开，不携带手机 B 站账号。手机提取 BV/AV、ep/ss 编号、`p` 和 `t` 参数，自动连接上次的电视，通过 `load` 发送编号；未连接过时先选择电视。

分享的 `load` 可只提供 `aid`、`epid` 或 `seasonId`，`cid` 默认为 0，电视自行获取视频详情和播放地址。`page` 从 1 开始，默认 1；分 P 不存在时拒绝播放。现有 `aid` + `cid` 精确播放保持兼容。播放身份以电视启动会话编号关联，解析出实际 CID 后退出切换状态。

## 命令

```json
{"type":"command","requestId":"unique-123","action":"load","payload":{"aid":42,"cid":123,"positionMs":0}}
```

`load` 使用明确的视频身份。普通视频为 aid/cid，番剧额外提供 epid/seasonId；可携带 title、positionMs。不发送 Cookie、账号密码或 CDN 媒体 URL。电视自行取流、加载弹幕及后续选集。

其他命令附带最近状态中的 `playbackId`，防止旧手机界面的指令影响新视频：

| action | payload |
| --- | --- |
| state | 空，立即读取状态 |
| play / pause | 空 |
| back / stop | 空，关闭电视当前播放器 |
| seek | positionMs |
| volume | value，0–100 |
| adjustVolume | direction，1 或 -1；按电视系统音量档位调整 |
| speed | value，0.25–4 |
| quality | value，电视返回的可用清晰度编号 |
| danmaku | enabled，布尔值 |
| danmakuSettings | 按需携带 scale（0.5–4）、area（0.1–1）、opacity（0.1–1）、density（0.2–1）、types（rolling/top/bottom 数组）；只修改提交的字段 |
| next / previous | 空 |
| episode | aid/cid，必须存在于电视当前队列 |

命令返回 `ack` 或带 requestId 的 `error`。`load` 的 ack 状态为 accepted，表示已接收启动请求，不代表视频已经起播。其他成功命令返回 applied；实际播放器情况以随后推送的 state 为准。电视对近期同一手机的 requestId 去重。

## 状态

电视约每 750 毫秒推送一次 state，命令后也立即推送。字段包括：playbackId、revision、state、error、aid、cid、title、positionMs、durationMs、speed、volume、volumeMode、danmakuEnabled、qualityId、qualities、queue。

state 可为 PLAYING、PAUSED、STOPPED、TRANSITIONING、ERROR。queue 展开合集内部的分 P，并保留番剧身份。手机忽略低 revision 的旧状态；重连后 revision 重新从收到的快照开始比较。

支持弹幕样式的播放器额外返回 `danmakuSettings`，包含 scale、area、opacity、density、types；不支持时为 null。手机据此显示样式控件。area 沿用电视播放器的显示区域比例，types 控制滚动、顶部固定和底部固定弹幕，不提供任意坐标拖动。设置使用电视端已有持久化逻辑，重连后以电视状态为准；旧电视没有该字段时，手机仍可使用原有弹幕开关。

手机关闭连接只释放网络连接，电视的播放会话和自动下一集继续运行。重新连接读取快照，不重放断线前的操作。新视频使用独立的播放会话编号；连续切换时旧播放器不会回到前台。
