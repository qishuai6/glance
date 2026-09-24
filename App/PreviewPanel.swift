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
        index = (index + delta + files.count) % files.count
        renderCurrent()
    }

    private func renderCurrent() {
        let url = files[index]
        title = url.lastPathComponent
        let html = RendererHub.render(url: url)
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        // 切换文件后回到页面顶部
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.webView.evaluateJavaScript("window.scrollTo(0,0)", completionHandler: nil)
        }
    }
}
