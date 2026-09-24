import SwiftUI
import ServiceManagement

@main
struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlanceLog.log("App 启动（窗口枚举取选中项版 v5）")
        NSApp.setActivationPolicy(.regular)
        SpaceTapController.shared.start()
        if !SpaceTapController.shared.isRunning, !AXIsProcessTrusted() {
            // 首次启动引导授权（空格键接管必需）
            SpaceTapController.shared.requestPermission()
        }
        setupStatusItem()
        watchPermission()

        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showDemoPreview()
            }
        }
    }

    /// 授权往往是滞后的：轮询权限状态，一旦用户在系统设置里勾选，立即启动接管。
    private func watchPermission() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            let c = SpaceTapController.shared
            if !c.isRunning, AXIsProcessTrusted() {
                c.start()
                self?.toggleMenuItem?.state = c.isRunning ? .on : .off
                NotificationCenter.default.post(name: .init("GlanceStatusChanged"), object: nil)
            }
            if c.isRunning, self?.permissionTimer != nil {
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "eye",
                                     accessibilityDescription: "秒览 Glance")
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "接管空格预览", action: #selector(toggleTap), keyEquivalent: "")
        toggle.target = self
        toggle.state = SpaceTapController.shared.isRunning ? .on : .off
        menu.addItem(toggle)
        toggleMenuItem = toggle

        let settings = NSMenuItem(title: "打开设置", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let demo = NSMenuItem(title: "预览测试文件", action: #selector(showDemoPreview), keyEquivalent: "")
        demo.target = self
        menu.addItem(demo)

        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = (try? SMAppService.mainApp.status) == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出秒览", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleTap() {
        let c = SpaceTapController.shared
        if c.isRunning {
            c.stop()
        } else {
            c.start()
            if !c.isRunning { c.requestPermission() }
        }
        toggleMenuItem?.state = c.isRunning ? .on : .off
        NotificationCenter.default.post(name: .init("GlanceStatusChanged"), object: nil)
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.frameAutosaveName.isEmpty == false || w.isVisible || true {
            if w is NSPanel { continue }
            w.makeKeyAndOrderFront(nil)
            break
        }
    }

    @objc private func showDemoPreview() {
        let dir = "/Users/qishuai/ZCodeProject/Glance/fixtures"
        let urls = ["sample.md", "demo.zip", "demo.sql", "data.json", "data.csv",
                    "config.yaml", "config.toml", "app.log", "demo.swift", "demo.tar"]
            .map { URL(fileURLWithPath: "\(dir)/\($0)") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        NSApp.activate(ignoringOtherApps: true)
        PreviewPanel.shared.show(files: urls, index: 0)
    }

    @objc private func toggleLogin() {
        switch try? SMAppService.mainApp.status {
        case .enabled:
            try? SMAppService.mainApp.unregister()
        default:
            try? SMAppService.mainApp.register()
        }
        if let menu = statusItem?.menu, let item = menu.items.first(where: { $0.title == "登录时启动" }) {
            item.state = (try? SMAppService.mainApp.status) == .enabled ? .on : .off
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
