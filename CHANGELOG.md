# 更新记录

## 0.2.2 — 2026-11-01

发版流程版。**应用功能与 0.2.1 完全一致**，没有任何代码改动，这一版存在的意义是验证「推 tag 即出包」。

### 新增

- **GitHub Actions 自动发版**（`.github/workflows/release.yml`）：推一个 `v*` 的 tag，云端 `macos-14` 机器自动编译通用二进制（arm64 + x86_64）、验签、打 dmg、挂载自检、上传产物，再从本文件抽出对应版本的说明，用 `gh release create` 发布 Release。不再需要本地跑脚本、手动传附件。
- 也支持在 Actions 页面点「Run workflow」手动触发：不带 tag，只编译并留下产物（14 天），不发布 Release。

### 改动

- 版本号由 tag 决定，内部号用 Actions 的 run number；本地直接跑脚本时退回默认值 `0.2.2 (13)`。
- 合并了几处只影响 CI 的小改动（回调与菜单项补 `@MainActor`，云端 Swift 版本较新、actor 隔离检查更严）。本地编译行为不变。

### 升级建议

装 0.2.1 的可以不动。除非你想确认自动构建出来的包和手工包一致，那可以下这个覆盖安装——安装后「关于」里显示的版本应是 `0.2.2`，括号里的内部号由流水线编号决定（云端构建是 3，本地脚本默认 13）。

## 0.2.1 — 2026-11-01

隔空投送 + 长按预览。基于 0.2.0。

### 新增

- **右键菜单「隔空投送」。** `Line.swift` 新增 `airdrop(_:)`，走系统 `NSSharingService(.sendViaAirDrop)`：弹出 AirDrop 窗口列出附近设备，选中即发送，绳子上的图不消失。文件已不存在时该项置灰，不弹窗。
  - 发送在菜单关闭之后执行（`DispatchQueue.main.async`），避免菜单的事件循环里再开窗口。
  - 发送前 `NSApp.activate`，因为绳子本身是不抢焦点的悬浮条，AirDrop 窗口需要应用在前台才看得见。
- **长按图片 = 快速查看。** 按住 0.45 秒直接进系统预览，之后左右方向键翻整条绳子，空格或 Esc 关闭。三种输入设备（内建触控板、妙控鼠标、普通鼠标）行为一致。

### 改动

- **「标记」的手势位置变了。** 长按原先给标记，现在给预览。标记改为：力触控（触控板）+ 中键（带滚轮的鼠标）+ 右键菜单，三个入口都没有丢。
- 版本号 `0.2.0 (11)` → `0.2.1 (12)`。

### 未改动

- 单击仍是复制，双击仍是打开，右键菜单原有项全部保留（含「快速查看」）。
- 老张的收图与第三方剪贴板逻辑不动。

### 说明

- 「左键选中 + 空格预览」这条没有做。`LinePanel.canBecomeKey` 恒为 `false`，是上游刻意的设计：绳子永远不抢你正在用的 App 的键盘焦点。要支持空格只能改成抢焦点，或挂需要「辅助功能」权限的全局事件拦截，两者代价都大于收益。

## 0.2.0 — 2026-10-31

多桌面（Spaces）修复版。基于 Picline 0.1.9 源码。

### 修复

- **晾衣绳在多桌面下无法显示。** macOS 会把带 `canJoinAllSpaces` 的窗口在 `orderOut` / `orderFront` 之后永久绑定到某一个 Space，换桌面后再拉绳子什么都出不来（上游 [issue #80](https://github.com/alejandrobujan/tendedero/issues/80)）。
  - `AppDelegate.swift`：切换桌面通知回调中，0.8 秒动画结束后复检一次窗口所在 Space。
  - `AppDelegate.swift`：新增 `keepOnActiveSpace()`，`panel.isOnActiveSpace == false` 时重建窗口，`contentView` 与全部状态原样迁移。
  - `AppDelegate.swift`：把绳子拉下来的瞬间（`setRevealed(true)`）也补检一次。

### 改动

- 版本号 `0.1.9 (10)` → `0.2.0 (11)`。
- `scripts/build-picline.sh`：release 默认构建通用二进制（arm64 + x86_64）；构建前清空旧 bundle，避免残留旧的本地化与图标。
- 新增 `scripts/package-dmg.sh`：一条命令产出可分发的 dmg（含 `Applications` 快捷方式与安装说明）。

### 未改动

- `ClipboardWatcher.swift`、`CaptureReceiver.swift` 等老张的收图与第三方剪贴板逻辑，完全保持原样。

### 已知限制

- adhoc 签名，未做 Apple 公证。他人下载后首次打开需在「系统设置 → 隐私与安全性」点「仍然打开」，或执行 `xattr -dr com.apple.quarantine /Applications/Picline.app`。
- bundle id 沿用 `local.captureline.preview`，安装后会覆盖旧版 Picline，偏好设置保留。

## 0.1.9 — 上游基线

见 Picline 0.1.9 源码包（`base_revision` 2c3ffd95）。
