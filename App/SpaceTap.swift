import AppKit
import ApplicationServices

// AX 属性常量（与系统头文件中的 CFString 等价）
private let AXSelectedObjects = "AXSelectedObjects" as CFString
private let AXURL = "AXURL" as CFString

/// 全局空格键接管：Finder 里按空格时，秒览支持的文件用自己的面板预览，其余放行给系统。
final class SpaceTapController {
    static let shared = SpaceTapController()

    /// 秒览接管的扩展名（系统 Quick Look 有内容预览器的类型它不会让给第三方，这里全部由我们自己接管）
    static let takeoverExts: Set<String> = [
        "md", "markdown", "zip", "tar", "tgz",
        "csv", "tsv", "json", "jsonl", "ndjson",
        "yaml", "yml", "toml", "ini", "conf", "cfg", "env", "properties",
        "log", "plist", "xml", "css",
        "sql", "swift", "py", "js", "ts", "go", "rs", "kt", "java",
        "c", "h", "cpp", "cc", "cxx", "hpp", "m", "rb", "php", "pl",
        "lua", "sh", "bash", "zsh", "s", "make", "dockerfile", "makefile",
    ]

    var isEnabled = true
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var lastMissingPermission = false

    private init() {}

    // MARK: - 启停

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            let result = SpaceTapController.shared.handle(type: type, event: event)
            return result.map { Unmanaged.passUnretained($0) }
        }
        // kCGSessionEventTap（Swift 导出名不稳定，直接用原始值 1）
        guard let sessionTap = CGEventTapLocation(rawValue: 1),
              let port = CGEvent.tapCreate(tap: sessionTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: nil) else {
            lastMissingPermission = !AXIsProcessTrusted()
            return
        }
        lastMissingPermission = false
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        runLoopSource = source
        NSLog("[Glance] 事件监听已启动")
    }

    func stop() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        runLoopSource = nil
        PreviewPanel.shared.orderOut(nil)
    }

    var isRunning: Bool { tap != nil }

    /// 触发系统辅助功能授权弹窗
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 事件处理（主线程 runloop 回调）

    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            return event
        }
        guard type == .keyDown, isEnabled else { return event }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let panel = PreviewPanel.shared

        // 面板打开时的按键：空格/Esc 关闭，←→ 切换文件
        if panel.isVisible {
            switch code {
            case 49, 53: // space, esc
                panel.orderOut(nil)
                return nil
            case 123: // ←
                panel.step(-1)
                return nil
            case 124: // →
                panel.step(1)
                return nil
            default:
                return event
            }
        }

        guard code == 49 else { return event } // 仅接管空格

        let urls = finderSelection()
        NSLog("[Glance] 空格按下，Finder 选中 \(urls.count) 项：\(urls.map(\.lastPathComponent))")
        guard !urls.isEmpty else { return event }
        // 找到第一个秒览支持的文件；支持则整体接管（←→ 可在选中项间切换，跳过不支持的）
        let supported = urls.enumerated().filter { isTakeover($0.element) }
        guard let first = supported.first else { return event }

        NSLog("[Glance] 接管空格，预览 \(first.element.lastPathComponent)")
        panel.show(files: urls, index: first.offset)
        return nil
    }

    private func isTakeover(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        return Self.takeoverExts.contains(ext) || name == "dockerfile" || name == "makefile"
    }

    // MARK: - 取 Finder 选中项（AX）

    private func finderSelection() -> [URL] {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else {
            NSLog("[Glance] 前台不是 Finder，放行")
            return []
        }
        let appEl = AXUIElementCreateApplication(finder.processIdentifier)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appEl, AXSelectedObjects, &value)
        guard status == .success, let elements = value as? [AXUIElement] else {
            NSLog("[Glance] AX 取选中项失败 status=\(status.rawValue)")
            return []
        }
        let urls = elements.compactMap { el -> URL? in
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, AXURL, &v) == .success else { return nil }
            if let url = v as? URL { return url }
            if let ns = v as? NSURL { return ns as URL }
            return nil
        }
        return urls
    }
}
