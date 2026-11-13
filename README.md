# BetterMonitor

macOS 菜单栏工具：解决外接显示器发糊、不锐利的问题。

## 功能

- **模式切换器**：菜单栏列出每台显示器的可用模式（分辨率 / HiDPI / 刷新率），一键切换；不常用的模式收在"全部模式"子菜单。
- **推荐模式**：你为某台显示器选定（或接入时已在用）的像素完美模式会被记住，作为它的推荐模式，显示在菜单顶部"✨ 推荐模式"并以 ⭐️ 标注。没有记忆值的新显示器由自动检测兜底：读取面板原生像素与物理尺寸计算 PPI——
  - 高分屏（PPI ≥ 140）：半原生 HiDPI（2x 渲染）+ 最高刷新率；
  - 低分屏：原生分辨率 1x + 最高刷新率。
- **插拔守护**：监听显示器接入/断开，自动恢复你为该显示器保存的模式；从未设置过的显示器若处于"输出像素 ≠ 面板原生"的模糊状态，自动应用最佳模式（可在菜单中关闭）。**仅作用于外接显示器**——内置 Retina 屏由 macOS 自行管理，永不自动调整（菜单中仍可手动切换）。
- **登录时启动**：菜单内开关。

## 构建与运行

```bash
./build-app.sh
open build.noindex/BetterMonitor.app
```

要求 macOS 13+，Xcode Command Line Tools。打包、部署（分发）、安装、卸载的完整说明见 [INSTALL.md](INSTALL.md)。

## 原理

外接屏发糊通常是两件事叠加：① 输出分辨率 ≠ 面板原生像素，被面板非整数倍拉伸；② 非 HiDPI（1x）渲染在低 PPI 屏上文字发虚。本工具保证"输出像素 = 面板原生"（消除①），并在面板允许时优先 HiDPI 模式（缓解②）。

仅使用公开 CoreGraphics API（`CGDisplayCopyAllDisplayModes` / `CGConfigureDisplayWithDisplayMode`）。

## Roadmap

- [ ] 虚拟 HiDPI 显示器 + 镜像（私有 API `CGVirtualDisplay`）：提供系统缺失的"看起来像 1600×900 / 1920×1080 且 2x 超采样"档位，空间与清晰度兼得。
- [ ] DDC/CI 亮度、音量控制（Apple Silicon 走 `IOAVService`）。

## License

MIT，见 [LICENSE](LICENSE)。
