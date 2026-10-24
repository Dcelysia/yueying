# 跃映（Yueying）品牌图标

鸿蒙手机端采用独立的“跃映 / Yueying”名称。Android 手机端、电视接收端与协议名称不受影响。正式图标采用白色背景和红色图形。

`yueying-icon.png` 为 2026-10-24 按用户授权通过 Codex 内置 `image_gen` 工具生成的品牌图标，原图按原样保存，实际尺寸为 1254 × 1254。生成结果标识为 `exec-72ce1be2-211f-4141-9118-208bbdebd6b2`，没有使用 CLI 图片生成器。生成时名称尚未选定，随后用户选择“跃映”，图形中不含文字。该图标不含 B站品牌图形；本记录不代表商标注册或第三方授权。

原生 `AppScope/resources/base/media/app_icon.png` 和 `entry/src/main/resources/base/media/app_icon.png` 均由原图使用 macOS `sips -z 512 512` 缩放为 512 × 512。启动图标与应用图标直接引用这两个 PNG；未使用分层图标资源。原图保留在源码中，不额外打包为 Flutter 页面素材。

## 生成提示词

> Use case: logo-brand. Asset type: final launcher icon for an independent modern phone-to-TV video browsing/controller app, name undecided. Critical colors: pure WHITE edge-to-edge BACKGROUND, vivid coral RED SYMBOL ONLY. One elegant compact playful geometric red mark combining a rounded television screen, small play triangle, and a simple connected phone/calling signal. Modern friendly mobile app identity, bold clean curves, balanced negative space, readable tiny at 48px, flat vector-like execution. Make the symbol feel like a single unified logo rather than two clipart devices. Center inside 22 percent safety margin. No text, letters, numbers, Bilibili logo/mascot/antennae, existing brand symbols, gradient, texture, shadow, outer rounded-square mask or mockup. Square production icon, opaque white background. White background is essential; do NOT invert colors.
