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
        "md", "markdown", "mdx", "mdown", "zip", "tar", "tgz", "gz",
        "apk", "ipa", "jar", "war",
        "csv", "tsv", "json", "jsonl", "ndjson", "ipynb",
        "yaml", "yml", "toml", "ini", "conf", "cfg", "env", "properties",
        "log", "plist", "xml", "css",
        "svg", "psd", "ai", "eps",
        "ttf", "otf", "ttc", "woff", "woff2",
        "vue", "svelte",
        "sql", "swift", "py", "js", "ts", "go", "rs", "kt", "java",
        "c", "h", "cpp", "cc", "cxx", "hpp", "m", "rb", "php", "pl",
        "lua", "sh", "bash", "zsh", "s", "make", "dockerfile", "makefile",
        "jsx", "tsx", "mjs", "cjs", "r", "scala", "dart", "ex", "exs",
        "bat", "cmd", "ps1", "tex",
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
            case 123, 126: // ← ↑
                panel.step(-1)
                return nil
            case 124, 125: // → ↓
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
        // AX 查询必须跑主线程（后台线程会静默失败）；剪贴板兜底有等待才放后台
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let fastUrls = self.finderSelectionAXOnly()
            if !fastUrls.isEmpty {
                self.finishTakeover(urls: fastUrls)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let urls = self?.finderSelectionSlow() ?? []
                DispatchQueue.main.async { self?.finishTakeover(urls: urls) }
            }
        }
        return nil // 吞掉本次空格，结果出来前不打扰系统
    }

    /// 接管收尾（主线程）：判支持 → 组文件夹清单（AX 显示顺序）→ 弹面板或补发。
    private func finishTakeover(urls: [URL]) {
        takeoverBusy = false
        guard !urls.isEmpty else {
            GlanceLog.log("Finder 选中项为空，补发空格走系统 QL")
            repostSpace()
            return
        }
        GlanceLog.log("Finder 选中 \(urls.count) 项：\(urls.map(\.lastPathComponent).joined(separator: ", "))")
        let supported = urls.enumerated().filter { isTakeover($0.element) }
        guard let first = supported.first else {
            GlanceLog.log("选中项均不支持，补发空格走系统 QL")
            repostSpace()
            return
        }
        GlanceLog.log("接管空格，预览 \(first.element.lastPathComponent)")
        // 方向键可浏览整个文件夹的文件（对齐系统 QL 体验）
        let (files, index) = Self.folderListing(around: first.element, fallback: urls, fallbackIndex: first.offset)
        PreviewPanel.shared.show(files: files, index: index)
    }

    /// 同目录文件清单：顺序优先取 Finder 窗口的显示行序（对齐当前排序设置），读不到再按名称自然排序。
    /// 返回（清单、当前文件下标）。
    static func folderListing(around url: URL, fallback: [URL], fallbackIndex: Int) -> ([URL], Int) {
        let dir = url.deletingLastPathComponent()
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return (fallback, fallbackIndex)
        }
        var files: [URL] = []
        var byName: [String: URL] = [:]
        for item in items {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue {
                files.append(item)
                byName[item.lastPathComponent] = item
            }
        }
        guard !files.isEmpty, files.count <= 2000 else { return (fallback, fallbackIndex) }

        // 从 Finder 主窗口按显示顺序取行名（就是用户当前排序的顺序）
        var ordered: [URL] = []
        if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }),
           let rowNames = axDisplayOrder(finder, byName: byName) {
            var seen = Set<String>()
            for name in rowNames {
                if let u = byName[name], seen.insert(name).inserted {
                    ordered.append(u)
                }
            }
            GlanceLog.log("Finder 显示顺序：取到 \(ordered.count)/\(files.count) 项")
        }

        let listing: [URL]
        if ordered.count >= max(1, files.count / 2) {
            // AX 覆盖大部分：按显示顺序，缺的（虚拟化未加载的行）按名称序补到尾部
            let missing = files.filter { !ordered.contains($0) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            listing = ordered + missing
        } else {
            listing = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        let idx = listing.firstIndex { $0.path == url.path } ?? 0
        return (listing, idx)
    }

    /// 读 Finder 主窗口的行显示顺序：收集窗口里所有行组（侧边栏/文件区各有 outline），
    /// 取「与目录文件名匹配最多」的那组，即文件区当前排序的显示顺序。
    private static func axDisplayOrder(_ finder: NSRunningApplication, byName: [String: URL]) -> [String]? {
        let appEl = AXUIElementCreateApplication(finder.processIdentifier)
        var wv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, "AXWindows" as CFString, &wv) == .success,
              let windows = wv as? [AXUIElement] else { return nil }
        for w in windows {
            if Self.subrole(of: w) == "Quick Look" { continue }
            var groups: [[AXUIElement]] = []
            collectRowGroups(el: w, into: &groups, depth: 0)
            var bestNames: [String]? = nil
            var bestMatches = 0
            for rows in groups.prefix(8) {
                let names = rows.compactMap { firstName(in: $0) }
                let matches = names.filter { byName[$0] != nil }.count
                if matches > bestMatches {
                    bestMatches = matches
                    bestNames = names
                }
            }
            if bestMatches > 0 { return bestNames }
        }
        return nil
    }

    /// 递归收集窗口子树里的全部行组：表格取 AXRows；图标/列表视图的文件区是 AXList，取其 AXChildren。
    private static func collectRowGroups(el: AXUIElement, into groups: inout [[AXUIElement]], depth: Int) {
        guard depth < 10, groups.count < 8 else { return }
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXRows" as CFString, &v) == .success,
           let rows = v as? [AXUIElement], !rows.isEmpty {
            groups.append(rows)
        }
        var rv: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXRole" as CFString, &rv) == .success,
           let role = rv as? String, role == "AXList" {
            var cv: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, "AXChildren" as CFString, &cv) == .success,
               let items = cv as? [AXUIElement], !items.isEmpty {
                groups.append(items)
            }
        }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXChildren" as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return }
        for c in children { collectRowGroups(el: c, into: &groups, depth: depth + 1) }
    }

    /// 行/项子树里的第一个文本（列表视图首列即文件名；图标视图的文本标签即文件名）。
    private static func firstName(in el: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 4 else { return nil }
        var rv: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXRole" as CFString, &rv) == .success,
           let role = rv as? String, role.contains("Text") {
            var vv: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, "AXValue" as CFString, &vv) == .success,
               let s = vv as? String, !s.isEmpty, s != "\t" {
                return s
            }
        }
        var kids: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXChildren" as CFString, &kids) == .success,
           let children = kids as? [AXUIElement] {
            for c in children {
                if let n = firstName(in: c, depth: depth + 1) { return n }
            }
        }
        return nil
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
        return windows.contains { Self.subrole(of: $0) == "Quick Look" }
    }

    private func isTakeover(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        return Self.takeoverExts.contains(ext) || name == "dockerfile" || name == "makefile"
    }

    // MARK: - 取 Finder 选中项（AX）

    /// 快路径（必须主线程调用）：AX 取选中行上的 AXURL。
    private func finderSelectionAXOnly() -> [URL] {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else { return [] }
        return selectionViaAX(finder: finder) ?? []
    }

    /// 慢路径（后台线程）：AppleScript → 剪贴板兜底（带等待）。
    private func finderSelectionSlow() -> [URL] {
        if let urls = selectionViaAppleEvents(), !urls.isEmpty {
            return urls
        }
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
            if Self.subrole(of: w) == "Quick Look" { continue }
            if Self.isMain(w), let urls = findSelection(in: w, depth: 0), !urls.isEmpty {
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

        guard let finderApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.finder" }) else { return nil }
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return nil }
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)!
        cDown.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)!
        cUp.flags = .maskCommand
        // 定向投递给访达进程：不受当前前台应用影响（投到 HID 会打到别的 App）
        cDown.postToPid(finderApp.processIdentifier)
        Thread.sleep(forTimeInterval: 0.04)
        cUp.postToPid(finderApp.processIdentifier)

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

    private static func subrole(of el: AXUIElement) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXSubrole" as CFString, &v) == .success, let val = v else { return "" }
        if let s = val as? String { return s }
        if let s = val as? NSString { return s as String }
        return ""
    }

    private static func isMain(_ el: AXUIElement) -> Bool {
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
