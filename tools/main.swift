import Foundation

// 渲染器 CLI 调试工具：把任一文件渲染成 HTML，便于脱离 Quick Look 检查效果。
// 用法：render_cli <file> [out.html]
let args = CommandLine.arguments
guard args.count > 1 else {
    print("用法：render_cli <file> [out.html]")
    exit(1)
}
let url = URL(fileURLWithPath: args[1])
let html = RendererHub.render(url: url)
let out = args.count > 2 ? args[2] : "/tmp/glance_out.html"
try Data(html.utf8).write(to: URL(fileURLWithPath: out))
print("✅ \(out)")
