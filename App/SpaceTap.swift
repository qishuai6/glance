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
        "svg", "psd",
        "sql", "swift", "py", "js", "ts", "go", "rs", "kt", "java",
        "c", "h", "cpp", "cc", "cxx", "hpp", "m", "rb", "php", "pl",
        "lua", "sh", "bash", "zsh", "s", "make", "dockerfile", "makefile",
    ]

    var isEnabled = true
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var lastMissingPermission = false
    private var takeoverBusy = false
    /// 补发空格的自定义标记（避免自己再拦截）
    static let repostMarker: Int64 = 0x6731

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

        // 自己补发的空格（接管失败后还给系统）：直接放行不处理
        if event.getIntegerValueField(.eventSourceUserData) == Self.repostMarker {
            return event
        }

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

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              !takeoverBusy else { return event }
        takeoverBusy = true
        // 异步取选中项（剪贴板兜底可能要等 1 秒+，不能阻塞监听回调）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = self?.finderSelection() ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.takeoverBusy = false
                guard !urls.isEmpty else {
                    GlanceLog.log("Finder 选中项为空，补发空格走系统 QL")
                    self.repostSpace()
                    return
                }
                GlanceLog.log("Finder 选中 \(urls.count) 项：\(urls.map(\.lastPathComponent).joined(separator: ", "))")
                let supported = urls.enumerated().filter { self.isTakeover($0.element) }
                guard let first = supported.first else {
                    GlanceLog.log("选中项均不支持，补发空格走系统 QL")
                    self.repostSpace()
                    return
                }
                GlanceLog.log("接管空格，预览 \(first.element.lastPathComponent)")
                PreviewPanel.shared.show(files: urls, index: first.offset)
            }
        }
        return nil // 吞掉本次空格，结果出来前不打扰系统
    }

    /// 接管失败时把空格还给系统（带标记避免自己再拦截；前台已不是访达时放弃）。
    private func repostSpace() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: 49, keyDown: true)!
        down.setIntegerValueField(.eventSourceUserData, value: Self.repostMarker)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 49, keyDown: false)!
        up.setIntegerValueField(.eventSourceUserData, value: Self.repostMarker)
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06) // 模拟真实按住时长，Finder 才认
        up.post(tap: .cghidEventTap)
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
        // ① AX：行/子树上的 AXURL（桌面与部分窗口有效，无副作用）
        if let urls = selectionViaAX(finder: finder), !urls.isEmpty {
            return urls
        }
        // ② AppleScript（若用户授过「控制访达」即刻生效；被拒时快速失败）
        if let urls = selectionViaAppleEvents(), !urls.isEmpty {
            return urls
        }
        // ③ 剪贴板：模拟 ⌘C 复制读文件 URL 后还原剪贴板（文件夹窗口的行不带 AXURL 的兜底）
        if let urls = selectionViaClipboard(), !urls.isEmpty {
            return urls
        }
        return []
    }

    /// AX 路径：仅取主窗口选中行上的 AXURL（其余窗口的选中项可能是陈旧状态，
    /// 会遮蔽真正的活跃选中项；主窗口取不到就交给后续兜底）。
    private func selectionViaAX(finder: NSRunningApplication) -> [URL]? {
        let appEl = AXUIElementCreateApplication(finder.processIdentifier)
        var wv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, "AXWindows" as CFString, &wv) == .success,
              let windows = wv as? [AXUIElement] else { return nil }
        for w in windows {
            if subrole(of: w) == "Quick Look" { continue }
            if isMain(w), let urls = findSelection(in: w, depth: 0), !urls.isEmpty {
                return urls
            }
        }
        return nil
    }

    /// 模拟 ⌘C → 读剪贴板文件 URL → 还原剪贴板。
    private func selectionViaClipboard() -> [URL]? {
        let pb = NSPasteboard.general
        let savedChangeCount = pb.changeCount
        // 备份现有剪贴板（可能多条目多类型）
        let savedItems: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }

        guard let src = CGEventSource(stateID: .combinedSessionState) else { return nil }
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)!
        cDown.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)!
        cUp.flags = .maskCommand
        cDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.04)
        cUp.post(tap: .cghidEventTap)

        var urls: [URL] = []
        let pollDeadline = Date().addingTimeInterval(1.5)
        while Date() < pollDeadline {
            Thread.sleep(forTimeInterval: 0.02)
            if let list = pb.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL],
               !list.isEmpty {
                urls = list
                break
            }
        }

        if !urls.isEmpty {
            // Finder 的写入可能分多拍：等 changeCount 稳定再还原（最多 400ms）
            var last = pb.changeCount
            let stableDeadline = Date().addingTimeInterval(0.4)
            while Date() < stableDeadline {
                Thread.sleep(forTimeInterval: 0.08)
                let c = pb.changeCount
                if c == last { break }
                last = c
            }
            // 还原并校验（被覆盖则重试）
            for _ in 0..<3 {
                pb.clearContents()
                if !savedItems.isEmpty {
                    let items = savedItems.map { pairs -> NSPasteboardItem in
                        let i = NSPasteboardItem()
                        for (t, d) in pairs { i.setData(d, forType: t) }
                        return i
                    }
                    pb.writeObjects(items)
                }
                Thread.sleep(forTimeInterval: 0.1)
                let stillFile = (pb.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                if stillFile.isEmpty { break }
            }
        }
        GlanceLog.log("剪贴板兜底：\(urls.count) 个 URL")
        return urls.isEmpty ? nil : urls
    }

    /// AppleScript 取选中项 POSIX 路径。
    private func selectionViaAppleEvents() -> [URL]? {
        let source = """
        tell application "Finder"
            set out to {}
            repeat with f in (selection as alias list)
                copy (POSIX path of f) to end of out
            end repeat
            return out
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let err = error {
            GlanceLog.log("AppleScript 取选中项失败：\(err["NSAppleScriptErrorNumber"] ?? "?")")
            return nil
        }
        var urls: [URL] = []
        for i in 1...max(result.numberOfItems, 0) {
            if let p = result.atIndex(i)?.stringValue, !p.isEmpty {
                urls.append(URL(fileURLWithPath: p, isDirectory: p.hasSuffix("/")))
            }
        }
        return urls
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
