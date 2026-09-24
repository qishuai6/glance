import AppKit
import WebKit

/// 全局预览面板：仿 Quick Look 的浮动窗口，渲染秒览的 HTML。
final class PreviewPanel: NSPanel {
    static let shared = PreviewPanel()

    private let webView: WKWebView
    private var files: [URL] = []
    private var index = 0

    private init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                   styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        backgroundColor = .clear
        contentView = webView
        center()

        // 点面板外任意处关闭（贴近系统 Quick Look 的习惯，避免面板残留遮蔽后续操作）
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return }
            let loc = NSEvent.mouseLocation
            if !self.frame.contains(loc) {
                self.orderOut(nil)
            }
        }
    }

    var currentIndex: Int { index }
    var fileCount: Int { files.count }

    func show(files: [URL], index: Int) {
        guard !files.isEmpty else { return }
        self.files = files
        self.index = max(0, min(index, files.count - 1))
        renderCurrent()
        // 居中偏上，贴近 Quick Look 的视觉位置
        if !isVisible, let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2,
                                   y: f.midY - frame.height / 2 + f.height * 0.04))
        }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    func step(_ delta: Int) {
        guard !files.isEmpty else { return }
        // 到头尾就停住（对齐系统 Quick Look，不循环）
        let next = index + delta
        guard next >= 0, next < files.count else { return }
        index = next
        renderCurrent()
        // Finder 选中项跟随预览的文件（对齐系统 Quick Look 行为）
        let url = files[index]
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func renderCurrent() {
        let url = files[index]
        title = url.lastPathComponent
        let html = RendererHub.render(url: url)
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        // 切换文件后回到页面顶部，并在顶栏标注「第几个/共几个」
        let pos = "\(index + 1)/\(files.count)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.webView.evaluateJavaScript(
                "window.scrollTo(0,0); var m=document.querySelector('.meta'); if(m&&!m.dataset.p){m.dataset.p=1;m.textContent+=' · \(pos)'}",
                completionHandler: nil)
        }
    }
}
