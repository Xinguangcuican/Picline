<p align="center">
  <img src="Sources/Tendedero/Resources/Artwork/Picline-AppIcon.png" width="128" alt="Picline">
</p>

<h1 align="center">Picline</h1>

<p align="center">
连截几张图、连着复制几张图，剪贴板都只留最后一张 —— 把图挂成一排，用哪张取哪张。<br>
Mac 菜单栏下的图片晾衣绳 · 读第三方截图工具与浏览器/访达复制来的图 · 多桌面（Spaces）通用 · 可标记与快速预览<br>
这个分支修好了多桌面，并加上<b>隔空投送</b>、<b>长按预览</b>与<b>访达右键「打开方式 → Picline」</b>。
</p>

<p align="center">
macOS 14+ · Apple 芯片与 Intel 通用 · 约 3.5 MB · 免费开源
</p>

<p align="center">
<a href="https://github.com/Xinguangcuican/Picline/releases/latest"><b>↓ 下载 Picline 0.2.5</b></a>
</p>

<p align="center">
  <img src="docs/demo/picline-demo.gif" width="880" alt="鼠标推到屏幕顶部，绳子落下，新截图依次挂上去">
</p>

---

## 这是什么

Picline 是 [Tendedero](https://github.com/alejandrobujan/tendedero) 的一个修改分支，由 **老张** 在原版基础上增强了收图能力（能读第三方截图工具的剪贴板、跨工具去重、指定打开图片的应用）。

但老张那版有个 macOS 的老毛病：**晾衣绳的窗口会被系统钉死在某一个桌面上**，换到别的桌面后，鼠标压到屏幕顶部什么都不出现。

这个仓库的 0.2.0 只解决这一个问题，其他功能一行没动。之后的版本在它上面陆续加了隔空投送、长按预览，以及访达里的「挂到 Picline」。

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

## 三个入口

### 一、读第三方截图工具的剪贴板

老张那版已经放开了上游的过滤条件：上游会丢弃"同时带 `fileURL` 或纯文本"的剪贴板内容，而这恰好是 PixPin、Shottr、Snapzy、CleanShot 这类工具复制图片时的典型形态。

现在的处理是：

- 带 `fileURL` 的，读文件本体，并校验扩展名确实是图片；
- 同时保留位图数据做 `fallbackImage`，防止临时文件被工具删掉后挂不上；
- 仍然跳过密码管理器标记的隐私内容（`org.nspasteboard.ConcealedType` 等）。

需要在菜单栏菜单里勾上 **「接收剪贴板图片」** 才会生效，默认关闭。开启之后，浏览器里右键复制图片、聊天窗口里复制别人发的图、访达里选中几个文件按 `Command + C`，都会挂到绳子上；图片文件来自任何文件夹都可以，不限于已经添加的截图文件夹。

### 二、多桌面

切换桌面后，把鼠标压到屏幕顶部中间，绳子照常落下。见上文改动说明。

### 三、让访达把图交给 Picline

在访达（或 QSpace）里选中任意图片 → 右键 → **打开方式** → **Picline**，图片会被复制一份进来并挂上。原文件之后改名、挪走或删掉，绳上那张都不受影响。

## 怎么用

### 把绳子放下来

| 操作 | 结果 |
| --- | --- |
| 指针碰到菜单栏 | 立刻在那一块屏幕上把绳子放下来，不用等 —— 绳子上没有图也照样放下来，看到的就是那条空绳和一句提示 |
| 点击菜单栏任意处 | 把绳子收起来 |
| 指针移开超过 0.5 秒 | 绳子自己收回去 |
| `Control + Option + T` | 显示 / 隐藏绳子（菜单栏「快捷键」里可改） |

### 绳子上的每一张图

| 操作 | 结果 |
| --- | --- |
| 单击 | 复制到剪贴板 |
| 双击 | 用默认 app 打开（默认「预览」，「双击图片打开方式」里可换） |
| **按住 0.45 秒** | **快速查看**，之后左右方向键翻整条绳子，空格或 Esc 关闭 |
| 力触控（触控板） | 快速查看 |
| 中键（带滚轮的鼠标） | 标记 |
| 拖进 app | 送一份副本过去，原图仍挂在绳上 |
| 拖进文件夹或桌面 | 存在那儿，图从绳上取下 |
| 拖到废纸篓 | 删除 |
| 点卡片左上角叉号 | 丢弃 |
| 右键 | 见下一节 |

### 右键菜单

| 菜单项 | 做什么 | 什么时候出现 |
| --- | --- | --- |
| 复制 / 打开 / 快速查看 | 同单击、双击、长按 | 总是 |
| 标记 | 打开标记窗口（录屏中不显示） | 总是 |
| 在访达中显示 | 在访达里定位这个文件 | 总是 |
| **隔空投送** | 系统窗口列出附近设备，选一台发过去，图不从绳上取下 | 文件还在时；已被移走则置灰 |
| 存储到桌面 | 把图存到桌面，并沿用「存储到桌面」的命名 | 图来自截图文件夹或剪贴板时 |
| 丢弃 | 从绳上取下并删除文件 | 图来自截图文件夹或剪贴板时 |
| 取下 | 只从绳上取下，文件留在原处 | 图是外部引用的文件时 |
| 移到废纸篓 | 从绳上取下并删掉文件 | 同上 |
| 取下左侧 / 右侧全部 | 一次清掉一半 | 那一侧还有图时 |

### 从访达挂图：右键 → 打开方式 → Picline

选中一张或多张图片（桌面、下载、移动硬盘、素材库都行），右键 → **打开方式** → **Picline**，图会复制一份进应用并挂到绳上。

QSpace 有自己的右键菜单，但「打开方式」同样走系统那一套，所以里面也会有 Picline。也可以把图片直接拖到 Picline 的图标上。

> 为什么不是「服务 → 挂到 Picline」：应用里其实仍然声明了这个服务，但 macOS 15 只会把服务列给能验证签名来历的应用。本项目是 adhoc 签名，实测这颗声明在同一台机器上时有时无，重装一次就可能消失，不能当主力入口。而「打开方式」是 LaunchServices 的文件类型声明，稳定得多。

> 为什么不是「左键选中 + 空格预览」：绳子的窗口（`LinePanel`）`canBecomeKey` 恒为 `false`，这是上游刻意的设计 —— 它永远不抢你正在用的 App 的键盘焦点。要支持空格，只能改成抢焦点，或挂需要「辅助功能」权限的全局事件拦截，两者代价都大于收益。

## 安装

1. 从 [Releases](https://github.com/Xinguangcuican/Picline/releases/latest) 下载 `Picline-0.2.5.dmg`。
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
git clone git@github.com:Xinguangcuican/Picline.git
cd Picline
scripts/build-picline.sh release     # 产出 build/Picline.app 和 build/Picline.zip
scripts/package-dmg.sh               # 额外产出 build/Picline-<版本>.dmg
```

本地构建是 adhoc 签名，重新编译后 macOS 会再询问一次文件夹访问权限。

## 发版

打一个 tag 推上去就行，编译、打包、发 Release 全部由 GitHub Actions 完成：

```sh
git tag v0.2.5
git push origin v0.2.5
```

1. **版本号取自 tag**，代码里的任何数字都不用改。
2. **发布说明取自 `CHANGELOG.md`** 里对应版本的段落，末尾自动附上安装说明。所以发版前先写好那一节。
3. **产物同时留在 Actions 页面**（保留 14 天），构建日志可查，出问题能追溯。

在 Actions 页面手动点 `Run workflow` 则只构建、不发版，用来验证代码能不能过。

## 与上游的关系

```
Tendedero (Alejandro Buján, MIT)
   └── Picline 0.1.9 (老张，增强剪贴板与收图)
          └── Picline 0.2.0 多桌面版
                 └── Picline 0.2.1（隔空投送、长按预览）
                        └── Picline 0.2.3（访达服务）
                               └── Picline 0.2.5（本仓库当前版本，空绳子也能唤出）
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
