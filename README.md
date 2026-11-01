<p align="center">
  <img src="Sources/Tendedero/Resources/Artwork/Picline-AppIcon.png" width="128" alt="Picline">
</p>

<h1 align="center">Picline 多桌面版</h1>

<p align="center">
截图不再落到桌面上，而是挂在菜单栏下面的一根绳子上，随用随取。<br>
这个版本修好了一件事：<b>多桌面（Spaces）里都能用</b>。<br>
0.2.1 又加了<b>隔空投送</b>和<b>长按预览</b>。
</p>

<p align="center">
macOS 14+ · Apple 芯片与 Intel 通用 · 约 3.5 MB · 免费开源
</p>

<p align="center">
<a href="https://github.com/Yixin2020818/picline-multispace/releases/latest"><b>↓ 下载 Picline 0.2.1</b></a>
</p>

---

## 这是什么

Picline 是 [Tendedero](https://github.com/alejandrobujan/tendedero) 的一个修改分支，由 **老张** 在原版基础上增强了收图能力（能读第三方截图工具的剪贴板、跨工具去重、指定打开图片的应用）。

但老张那版有个 macOS 的老毛病：**晾衣绳的窗口会被系统钉死在某一个桌面上**，换到别的桌面后，鼠标压到屏幕顶部什么都不出现。

这个仓库（0.2.0）只解决这一个问题，其他功能一行没动。

## 这个版本改了什么

核心是上游 [issue #80](https://github.com/alejandrobujan/tendedero/issues/80) 的修法：带 `canJoinAllSpaces` 的 NSPanel 一旦 `orderOut` 再 `orderFront`，系统可能把它永久绑在某个 Space 上。官方的解法不是去修那个窗口，而是**发现它不在当前桌面时，直接重建一个新窗口**。

全部改动集中在 `Sources/Tendedero/AppDelegate.swift`，共 31 行：

1. **切换桌面的回调里加一次复检**：等 0.8 秒动画结束后，确认窗口在不在当前桌面。
2. **新增 `keepOnActiveSpace()`**：`panel.isOnActiveSpace` 为 `false` 时，把 `contentView` 从旧窗口摘下来、`orderOut` 旧窗口、新建一个 `LinePanel` 顶上去（frame / `ignoresMouseEvents` / `alphaValue` / `onScroll` 全部抄回）。
3. **拉下绳子的瞬间再补检一次**：覆盖"人已经在另一个桌面、窗口还留在原桌面"这条路径。

配套改动：

- `scripts/build-picline.sh`：版本号升到 `0.2.0 (11)`，release 默认编**通用二进制**（arm64 + x86_64），构建前清空旧 bundle。
- `scripts/package-dmg.sh`：新增，一条命令出可分发的 dmg。

完整 diff 见 [`picline-multispace-0.2.1.patch`](picline-multispace-0.2.1.patch)。

## 两个关键功能

### 一、读第三方截图工具的剪贴板

老张那版已经放开了上游的过滤条件：上游会丢弃"同时带 `fileURL` 或纯文本"的剪贴板内容，而这恰好是 PixPin、Shottr、Snapzy、CleanShot 这类工具复制图片时的典型形态。

现在的处理是：

- 带 `fileURL` 的，读文件本体，并校验扩展名确实是图片；
- 同时保留位图数据做 `fallbackImage`，防止临时文件被工具删掉后挂不上；
- 仍然跳过密码管理器标记的隐私内容（`org.nspasteboard.ConcealedType` 等）。

需要在菜单栏菜单里勾上 **「接收剪贴板图片」** 才会生效，默认关闭。

### 二、多桌面

切换桌面后，把鼠标压到屏幕顶部中间，绳子照常落下。见上文改动说明。

## 怎么用

绳子挂下来之后，一张图能做的事：

| 操作 | 结果 |
| --- | --- |
| 单击 | 复制到剪贴板 |
| 双击 | 用默认应用打开 |
| **按住 0.45 秒** | **快速查看**，之后左右方向键翻整条绳子，空格或 Esc 关闭 |
| 力触控（触控板）/ 中键（鼠标） | 标记 |
| 拖出去 | 存成文件：拖到应用是给副本，拖到文件夹或桌面是留下原文件 |
| 拖到废纸篓 | 删除 |
| 左上角叉号 | 从绳子上取下 |
| 右键 | 菜单：复制、打开、快速查看、标记、在访达中显示、**隔空投送**、存储到桌面、丢弃、取下左右两侧全部 |

**隔空投送**：右键选「隔空投送」，系统窗口列出附近设备，选一台就发过去；绳子上的图不消失。文件已被移走或删除时，这一项会置灰。

> 为什么不是「左键选中 + 空格预览」：绳子的窗口（`LinePanel`）`canBecomeKey` 恒为 `false`，这是上游刻意的设计 —— 它永远不抢你正在用的 App 的键盘焦点。要支持空格，只能改成抢焦点，或挂需要「辅助功能」权限的全局事件拦截，两者代价都大于收益。

## 安装

1. 从 [Releases](https://github.com/Yixin2020818/picline-multispace/releases/latest) 下载 `Picline-0.2.1.dmg`。
2. 打开 dmg，把 Picline 拖进「应用程序」。
3. **首次打开会被 Gatekeeper 拦**（本项目是 adhoc 签名，未做 Apple 公证）：

   打开 `系统设置 → 隐私与安全性`，在「安全性」一栏点 **「仍然打开」**；

   或者打开终端执行：

   ```sh
   xattr -dr com.apple.quarantine /Applications/Picline.app
   ```

4. 首次运行会请求访问截图文件夹，必须允许，否则收不到新截图。

详细步骤见 [`安装说明.txt`](安装说明.txt)。

## 从源码构建

需要 macOS 14+ 和 Swift 工具链（Xcode 可选，Swift 5.9+）。

```sh
git clone <this-repo>
cd picline-multispace
scripts/build-picline.sh release     # 产出 build/Picline.app 和 build/Picline.zip
scripts/package-dmg.sh               # 额外产出 build/Picline-<版本>.dmg
```

本地构建是 adhoc 签名，重新编译后 macOS 会再询问一次文件夹访问权限。

## 与上游的关系

```
Tendedero (Alejandro Buján, MIT)
   └── Picline 0.1.9 (老张，增强剪贴板与收图)
          └── Picline 0.2.0 多桌面版
                 └── Picline 0.2.1（本仓库当前版本）
```

本仓库只做多桌面适配，不包含上游名称与图标的授权。详见 [`NOTICE`](NOTICE)。

## 许可

代码遵循 **MIT**，原始版权归 Alejandro Buján。Tendedero 与 Picline 的**名称和图标不在 MIT 授权范围内**，本项目沿用 Picline 的名称与自绘图标，不代表上游或原作者的官方发布与背书。

---

<details>
<summary>English</summary>

A fork of Picline (itself a fork of [Tendedero](https://github.com/alejandrobujan/tendedero) by Alejandro Buján) that fixes one thing: the clothesline window now follows you across every Space.

The upstream window can get permanently bound to a single Space after being ordered out and back in ([issue #80](https://github.com/alejandrobujan/tendedero/issues/80)). The fix rebuilds the window whenever `panel.isOnActiveSpace` is `false`, both after a Space change and right after the line is revealed.

MIT licensed. The Tendedero and Picline names and icons are not covered by that grant.

</details>
