# 更新记录

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
