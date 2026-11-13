# BetterMonitor 打包 · 部署 · 安装指南

## 环境要求

- macOS 13 (Ventura) 及以上
- 打包机器需安装 Xcode Command Line Tools：`xcode-select --install`
- 使用者的 Mac 无需任何依赖

---

## 一、打包

项目根目录执行：

```bash
./build-app.sh
```

脚本做三件事：

1. `swift build -c release` —— Release 编译；
2. 组装 `build.noindex/BetterMonitor.app`（拷贝二进制 + `Info.plist`，`LSUIElement` 使其只出现在菜单栏、不占 Dock）；
3. `codesign --force --sign -` —— **ad-hoc 签名**（仅本机可信，见"部署"一节）。

产物：`build.noindex/BetterMonitor.app`（约 1 MB，无任何外部依赖）。

---

## 二、安装（本机）

```bash
cp -R build.noindex/BetterMonitor.app /Applications/
open /Applications/BetterMonitor.app
```

启动后菜单栏右上角出现 🖥 图标，点开即可使用：

- **✨ 推荐模式**：一键切到该显示器的记忆/最佳模式；
- 主列表只显示值得用的模式（像素完美 + 1600×900 折中档），悬停约 1 秒显示使用场景说明；
- **全部模式**子菜单：其余所有模式；
- **自动应用最佳模式（插拔时）**：外接屏断开重接后自动恢复你保存的模式（不会碰内置屏）；
- **登录时启动**：建议勾上，开机即受保护。

> 首次启动后 app 会把当前"像素完美"的模式自动记为该显示器的推荐模式；之后在菜单里点选的任何模式都会成为新的记忆值。

---

## 三、部署（分发给其他 Mac）

### 方式 A：源码分发（最简单，适合开发者）

对方克隆/拷贝整个项目目录后自行执行 `./build-app.sh`。本机编译 + 本机签名，无 Gatekeeper 问题。

### 方式 B：直接拷贝 .app（小范围，免费）

把 `build.noindex/BetterMonitor.app` 压缩后发给对方：

```bash
ditto -c -k --keepParent build.noindex/BetterMonitor.app BetterMonitor.zip
```

**注意**：ad-hoc 签名的 app 在其他 Mac 上首次打开会被 Gatekeeper 拦截，对方需要任选其一：

- 右键 app → 打开 → 再点"打开"；或
- 系统设置 → 隐私与安全性 → 点"仍要打开"；或
- 终端执行 `xattr -cr /Applications/BetterMonitor.app` 后正常打开。

### 方式 C：正式分发（公开发布，需 Apple Developer 账号，$99/年）

1. 用 Developer ID 证书替换 ad-hoc 签名：

   ```bash
   codesign --force --deep --options runtime \
     --sign "Developer ID Application: <你的名字> (<TEAM_ID>)" \
     build.noindex/BetterMonitor.app
   ```

2. 打 dmg 并公证：

   ```bash
   hdiutil create -volname BetterMonitor -srcfolder build.noindex/BetterMonitor.app \
     -ov -format UDZO BetterMonitor.dmg
   xcrun notarytool submit BetterMonitor.dmg \
     --apple-id <你的AppleID> --team-id <TEAM_ID> --password <应用专用密码> --wait
   xcrun stapler staple BetterMonitor.dmg
   ```

3. 把 dmg 挂到官网 / GitHub Releases，用户下载后拖入"应用程序"即可，无任何 Gatekeeper 提示。

---

## 四、卸载

```bash
osascript -e 'quit app "BetterMonitor"'
rm -rf /Applications/BetterMonitor.app
defaults delete com.bettermonitor.app   # 清除记忆的模式设置（可选）
```

登录启动项随 app 删除自动失效。app 不写入其他任何文件、不联网。

---

## 五、常见问题

| 现象 | 处理 |
|---|---|
| 启动后"没反应" | 它是菜单栏应用，看屏幕右上角 🖥 图标，没有主窗口 |
| 切换某模式失败（弹窗报错误码） | 该模式可能被当前连接方式（线材/接口带宽）限制，换一档试试 |
| 外接屏重接后模式不对 | 确认菜单里"自动应用最佳模式（插拔时）"处于勾选状态 |
| 想恢复"出厂"状态 | 执行 `defaults delete com.bettermonitor.app` 后重启 app |
| 显示器名字显示为"显示器 N" | 个别杂牌屏不上报名称，不影响功能 |

---

## 附：项目结构

```
bettermonitor/
├── Package.swift                      # Swift Package 定义
├── Sources/BetterMonitor/main.swift   # 全部逻辑（约 330 行，纯公开 API）
├── Info.plist                         # 菜单栏应用配置（LSUIElement）
├── build-app.sh                       # 一键打包脚本
├── README.md                          # 功能与原理说明
└── INSTALL.md                         # 本文档
```
