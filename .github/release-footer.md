---

## 安装

1. 下载上面的 `Picline-<版本>.dmg`，双击打开，把 `Picline` 拖进「应用程序」。
2. 首次打开会被 Gatekeeper 拦（本版未做 Apple 公证，属正常现象）。两种放行办法：
   - 系统设置 → 隐私与安全性 → 拉到下面点「仍要打开」，再确认一次；
   - 或终端执行：`xattr -dr com.apple.quarantine /Applications/Picline.app`
3. 启动后菜单栏出现图标。要收截图，先在菜单里勾选「接收剪贴板图片」。

要求：macOS 14 或更高，Apple 芯片与 Intel 通用（同一个包，双架构）。

## 从源码构建

```bash
scripts/build-picline.sh release    # 编译通用二进制，产物在 build/Picline.app
scripts/package-dmg.sh              # 打包成 build/Picline-<版本>.dmg
```

---

本版由 GitHub Actions 自动构建，产物与源码一一对应，构建日志可在仓库的 Actions 页面查到。
