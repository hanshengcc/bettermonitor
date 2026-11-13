import AppKit
import CoreGraphics
import ServiceManagement

// MARK: - 显示模式工具

struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let nativePixelWidth: Int
    let nativePixelHeight: Int
    let ppi: Double
    let modes: [CGDisplayMode]

    var isBuiltin: Bool { CGDisplayIsBuiltin(id) != 0 }

    /// 面板是否为高分屏（值得整体跑 HiDPI）
    var isHighDensity: Bool { ppi >= 140 }
}

enum DisplayScanner {
    static func onlineDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)

        return ids.compactMap { id in
            let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            guard let all = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { return nil }
            let usable = all.filter { $0.isUsableForDesktopGUI() }
            guard !usable.isEmpty else { return nil }

            let nativeW = usable.map(\.pixelWidth).max() ?? 0
            let nativeH = usable.filter { $0.pixelWidth == nativeW }.map(\.pixelHeight).max() ?? 0
            let sizeMM = CGDisplayScreenSize(id)
            let ppi = sizeMM.width > 0 ? Double(nativeW) / (sizeMM.width / 25.4) : 0

            return DisplayInfo(
                id: id,
                name: displayName(for: id),
                nativePixelWidth: nativeW,
                nativePixelHeight: nativeH,
                ppi: ppi,
                modes: usable
            )
        }
    }

    static func displayName(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let num = screen.deviceDescription[key] as? NSNumber, num.uint32Value == id {
                return screen.localizedName
            }
        }
        return "显示器 \(id)"
    }
}

extension CGDisplayMode {
    var isHiDPI: Bool { pixelWidth > width }

    /// 输出像素与面板原生一致，即无缩放模糊
    func isPixelPerfect(in display: DisplayInfo) -> Bool {
        pixelWidth == display.nativePixelWidth && pixelHeight == display.nativePixelHeight
    }

    func matches(_ other: CGDisplayMode) -> Bool {
        width == other.width && height == other.height
            && pixelWidth == other.pixelWidth
            && abs(refreshRate - other.refreshRate) < 1
    }
}

enum Recommender {
    /// 自动检测后给出的最佳模式：
    /// - 高分屏（PPI ≥ 140）：半原生 HiDPI（2x 渲染），最高刷新率
    /// - 低分屏：原生分辨率 1x，最高刷新率（无缩放、最清晰）
    /// 共同前提：输出像素必须等于面板原生像素，否则必糊
    static func bestMode(for display: DisplayInfo) -> CGDisplayMode? {
        let pixelPerfect = display.modes.filter { $0.isPixelPerfect(in: display) }
        let preferred = pixelPerfect.filter { $0.isHiDPI == display.isHighDensity }
        let pool = preferred.isEmpty ? pixelPerfect : preferred
        return pool.max { a, b in
            if a.refreshRate != b.refreshRate { return a.refreshRate < b.refreshRate }
            return a.width < b.width
        }
    }
}

// MARK: - 按显示器持久化用户选择

enum ModeStore {
    private static let autoApplyKey = "autoApplyBestMode"

    static var autoApplyBest: Bool {
        get { UserDefaults.standard.object(forKey: autoApplyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoApplyKey) }
    }

    // 用显示器 UUID 做 key，断开重接、重启后依然能对上号
    private static func key(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return "savedMode." + (CFUUIDCreateString(nil, uuid) as String)
    }

    static func save(_ mode: CGDisplayMode, for id: CGDirectDisplayID) {
        guard let key = key(for: id) else { return }
        UserDefaults.standard.set([
            "w": mode.width, "h": mode.height,
            "hidpi": mode.isHiDPI, "hz": Int(mode.refreshRate.rounded()),
        ], forKey: key)
    }

    static func saved(for display: DisplayInfo) -> CGDisplayMode? {
        guard let key = key(for: display.id),
              let dict = UserDefaults.standard.dictionary(forKey: key),
              let w = dict["w"] as? Int, let h = dict["h"] as? Int,
              let hidpi = dict["hidpi"] as? Bool, let hz = dict["hz"] as? Int
        else { return nil }
        return display.modes.first {
            $0.width == w && $0.height == h && $0.isHiDPI == hidpi
                && abs($0.refreshRate - Double(hz)) < 1
        }
    }
}

// MARK: - 菜单栏 App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menuModes: [(display: CGDirectDisplayID, mode: CGDisplayMode)] = []
    private var enforceWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "display",
            accessibilityDescription: "BetterMonitor"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // 显示器插拔 / 主屏变化时自动重新检测并恢复模式
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleEnforce()
        }
        scheduleEnforce()
    }

    /// 插拔瞬间系统会连发多次通知，且显示器刚接入时未必能立刻切模式，
    /// 所以去抖 1.5 秒后再统一处理
    private func scheduleEnforce() {
        enforceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.enforceModes() }
        enforceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// 对每台在线的【外接】显示器：优先恢复用户保存的模式。没保存过的：
    /// - 当前已是像素完美 → 采纳当前模式为该显示器的记忆/推荐模式；
    /// - 当前在糊（输出像素 ≠ 面板原生）→ 自动应用最佳模式
    /// 内置 Retina 屏由 macOS 自己管理，永不自动调整（菜单中仍可手动切换）
    private func enforceModes() {
        for display in DisplayScanner.onlineDisplays() where !display.isBuiltin {
            let current = CGDisplayCopyDisplayMode(display.id)
            var desired = ModeStore.saved(for: display)
            if desired == nil, let current {
                if current.isPixelPerfect(in: display) {
                    ModeStore.save(current, for: display.id)
                    continue
                }
                if ModeStore.autoApplyBest {
                    desired = Recommender.bestMode(for: display)
                }
            }
            guard let desired else { continue }
            if let current, current.matches(desired) { continue }
            let err = apply(desired, to: display.id)
            if err != .success {
                NSLog("BetterMonitor: auto-apply \(desired.width)x\(desired.height) on \(display.name) failed: \(err.rawValue)")
            }
        }
    }

    // 每次打开菜单时重建，天然适应显示器热插拔
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menuModes.removeAll()

        let displays = DisplayScanner.onlineDisplays()
        for (index, display) in displays.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            addSection(for: display, to: menu)
        }

        menu.addItem(.separator())

        let autoItem = NSMenuItem(
            title: "自动应用最佳模式（插拔时）",
            action: #selector(toggleAutoApply),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.state = ModeStore.autoApplyBest ? .on : .off
        menu.addItem(autoItem)

        let launchItem = NSMenuItem(
            title: "登录时启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem(
            title: "退出 BetterMonitor",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    private func addSection(for display: DisplayInfo, to menu: NSMenu) {
        let header = NSMenuItem()
        let ppiText = display.ppi > 0 ? String(format: "%.0f PPI", display.ppi) : ""
        header.attributedTitle = NSAttributedString(
            string: "\(display.name)  ·  面板 \(display.nativePixelWidth)×\(display.nativePixelHeight)  \(ppiText)",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        header.isEnabled = false
        menu.addItem(header)

        let current = CGDisplayCopyDisplayMode(display.id)
        // 推荐 = 用户为该显示器保存过的模式优先，其次才是自动算出的最佳
        let best = ModeStore.saved(for: display) ?? Recommender.bestMode(for: display)

        // 一键推荐
        if let best {
            let isCurrent = current.map(best.matches) ?? false
            let item = NSMenuItem(
                title: "✨ 推荐模式：\(modeTitle(best))" + (isCurrent ? "（当前）" : ""),
                action: isCurrent ? nil : #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            if !isCurrent {
                item.target = self
                item.tag = registerMode(best, for: display.id)
            }
            item.toolTip = usageHint(for: best, in: display)
            menu.addItem(item)
        }

        // 常用模式只保留真正值得用的：像素完美模式（原生 1x + HiDPI），
        // 外加经典折中档 1600×900；其余全部折叠进"全部模式"
        let deduped = dedupedModes(display.modes)
        let curated = deduped.filter { mode in
            mode.isPixelPerfect(in: display)
                || (!mode.isHiDPI && mode.width == 1600 && mode.height == 900)
        }

        for mode in curated {
            menu.addItem(modeItem(mode, display: display, current: current, best: best))
        }

        // 其余模式收进子菜单
        let rest = deduped.filter { m in !curated.contains(where: m.matches) }
        if !rest.isEmpty {
            let subItem = NSMenuItem(title: "全部模式", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for mode in rest {
                submenu.addItem(modeItem(mode, display: display, current: current, best: best))
            }
            subItem.submenu = submenu
            menu.addItem(subItem)
        }
    }

    /// 同一 (分辨率, HiDPI) 只保留最高刷新率
    private func dedupedModes(_ modes: [CGDisplayMode]) -> [CGDisplayMode] {
        var best: [String: CGDisplayMode] = [:]
        for mode in modes {
            let key = "\(mode.width)x\(mode.height):\(mode.isHiDPI)"
            if let kept = best[key], kept.refreshRate >= mode.refreshRate { continue }
            best[key] = mode
        }
        return best.values.sorted { a, b in
            if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
            if a.width != b.width { return a.width > b.width }
            return a.height > b.height
        }
    }

    private func modeItem(
        _ mode: CGDisplayMode,
        display: DisplayInfo,
        current: CGDisplayMode?,
        best: CGDisplayMode?
    ) -> NSMenuItem {
        var title = modeTitle(mode)
        if let best, best.matches(mode) { title += "  ⭐️" }
        let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
        item.target = self
        item.tag = registerMode(mode, for: display.id)
        item.toolTip = usageHint(for: mode, in: display)
        if let current, current.matches(mode) { item.state = .on }
        return item
    }

    /// 悬停提示：这一档适合什么场景
    private func usageHint(for mode: CGDisplayMode, in display: DisplayInfo) -> String {
        let native = "\(display.nativePixelWidth)×\(display.nativePixelHeight)"
        var hint: String
        if mode.isPixelPerfect(in: display) {
            hint = mode.isHiDPI
                ? "最锐利：2x 超采样渲染，文字如 Retina 般饱满；UI 较大、可用空间较少。适合长时间读代码、写文档、护眼。"
                : "空间最大：逐像素输出到面板（\(native)），清晰不发虚；UI 偏小。适合多窗口并排、需要大桌面的工作。"
        } else if mode.isHiDPI {
            hint = "渲染锐利，但输出 \(mode.pixelWidth)×\(mode.pixelHeight) 低于面板原生 \(native)，会被拉伸发虚。仅在需要超大 UI 时临时使用。"
        } else {
            hint = "输出 \(mode.pixelWidth)×\(mode.pixelHeight) ≠ 面板原生 \(native)，画面被拉伸、文字发虚。仅作兼容用途，不建议日常使用。"
        }
        let hz = Int(mode.refreshRate.rounded())
        if hz >= 100 { hint += "（\(hz)Hz 高刷，滚动更顺滑）" }
        return hint
    }

    private func modeTitle(_ mode: CGDisplayMode) -> String {
        var s = "\(mode.width) × \(mode.height)"
        if mode.isHiDPI { s += "  HiDPI" }
        s += "  @\(Int(mode.refreshRate.rounded()))Hz"
        return s
    }

    private func registerMode(_ mode: CGDisplayMode, for display: CGDirectDisplayID) -> Int {
        menuModes.append((display, mode))
        return menuModes.count - 1
    }

    private func apply(_ mode: CGDisplayMode, to display: CGDirectDisplayID) -> CGError {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        let err = CGCompleteDisplayConfiguration(config, .permanently)
        if err != .success { CGCancelDisplayConfiguration(config) }
        return err
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard menuModes.indices.contains(sender.tag) else { return }
        let (display, mode) = menuModes[sender.tag]

        let err = apply(mode, to: display)
        if err == .success {
            ModeStore.save(mode, for: display)
        } else {
            let alert = NSAlert()
            alert.messageText = "切换失败"
            alert.informativeText = "无法切换到 \(modeTitle(mode))（错误码 \(err.rawValue)）"
            alert.runModal()
        }
    }

    @objc private func toggleAutoApply() {
        ModeStore.autoApplyBest.toggle()
        if ModeStore.autoApplyBest { scheduleEnforce() }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
