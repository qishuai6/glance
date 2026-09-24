import AppKit
import ApplicationServices

// AX 属性常量（与系统头文件中的 CFString 等价）
private let AXSelectedObjects = "AXSelectedObjects" as CFString
private let AXURL = "AXURL" as CFString

/// 文件级调试日志（NSLog 在 debug dylib 构建下不可靠，落文件最稳）
enum GlanceLog {
    static func log(_ s: String) {
        let line = "\(Date()) [Glance] \(s)\n"
        let url = URL(fileURLWithPath: "/tmp/glance_debug.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

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
        GlanceLog.log("事件监听已启动")
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
            GlanceLog.log("监听被系统禁用(\(type == .tapDisabledByTimeout ? "超时" : "用户输入")，已重新启用")
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
                GlanceLog.log("面板可见，空格/Esc 关闭面板")
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
        GlanceLog.log("空格按下，前台=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        // 系统 Quick Look 面板开着时放行：空格先让它按原生习惯关闭，下一次空格才是秒览
        if systemQuickLookVisible() {
            GlanceLog.log("系统 QL 面板开着，放行本按键")
            return event
        }

        let urls = finderSelection()
        guard !urls.isEmpty else {
            GlanceLog.log("Finder 选中项为空，放行")
            return event
        }
        GlanceLog.log("Finder 选中 \(urls.count) 项：\(urls.map(\.lastPathComponent).joined(separator: ", "))")
        // 找到第一个秒览支持的文件；支持则整体接管（←→ 可在选中项间切换，跳过不支持的）
        let supported = urls.enumerated().filter { isTakeover($0.element) }
        guard let first = supported.first else {
            GlanceLog.log("选中项均不支持，放行")
            return event
        }

        GlanceLog.log("接管空格，预览 \(first.element.lastPathComponent)")
        panel.show(files: urls, index: first.offset)
        return nil
    }

    /// 检测系统 Quick Look 面板是否在屏幕上（访达名下 subrole=Quick Look 的窗口）。
    private func systemQuickLookVisible() -> Bool {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else { return false }
        let appEl = AXUIElementCreateApplication(finder.processIdentifier)
        var wv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, "AXWindows" as CFString, &wv) == .success,
              let windows = wv as? [AXUIElement] else { return false }
        return windows.contains { subrole(of: $0) == "Quick Look" }
    }

    private func isTakeover(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        return Self.takeoverExts.contains(ext) || name == "dockerfile" || name == "makefile"
    }

    // MARK: - 取 Finder 选中项（AX）

    private func finderSelection() -> [URL] {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else { return [] }
        let appEl = AXUIElementCreateApplication(finder.processIdentifier)
        var wv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, "AXWindows" as CFString, &wv) == .success,
              let windows = (wv as? [AXUIElement]) else { return [] }
        // 遍历所有窗口找选中行；优先主窗口，跳过系统 Quick Look 面板（subrole=Quick Look）
        var mainSel: [URL] = []
        var otherSel: [URL] = []
        for w in windows {
            if subrole(of: w) == "Quick Look" { continue }
            if let urls = findSelection(in: w, depth: 0), !urls.isEmpty {
                if isMain(w) { mainSel = urls } else { otherSel = urls }
            }
        }
        return mainSel.isEmpty ? otherSel : mainSel
    }

    private func subrole(of el: AXUIElement) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXSubrole" as CFString, &v) == .success, let val = v else { return "" }
        if let s = val as? String { return s }
        if let s = val as? NSString { return s as String }
        return ""
    }

    private func isMain(_ el: AXUIElement) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXMain" as CFString, &v) == .success else { return false }
        return (v as? Bool) ?? false
    }

    /// 深度优先在窗口子树里找选中元素，命中即返回其 URL 列表。
    private func findSelection(in element: AXUIElement, depth: Int) -> [URL]? {
        guard depth < 6 else { return nil }
        for attr in ["AXSelectedRows", "AXSelectedChildren"] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &v) == .success,
               let items = v as? [AXUIElement], !items.isEmpty {
                let urls = items.compactMap { Self.url(of: $0) }
                if !urls.isEmpty { return urls }
            }
        }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findSelection(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// 从文件元素提取 URL（兼容 CFURL/NSURL 两种桥接）。
    static func url(of element: AXUIElement) -> URL? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &v) == .success,
              let cf = v else { return nil }
        if let u = cf as? URL { return u }
        if let u = cf as? NSURL { return u as URL }
        // CFURL 原始对象走 CFURLGetString 桥接
        if CFGetTypeID(cf) == CFURLGetTypeID(),
           let pathStr = CFURLGetString(unsafeBitCast(cf, to: CFURL.self)) {
            let s = pathStr as String
            if s.hasPrefix("file://"), let u = URL(string: s) { return u }
        }
        return nil
    }
}
