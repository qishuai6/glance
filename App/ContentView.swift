import SwiftUI
import ApplicationServices

struct ContentView: View {
    @State private var registered: Bool? = nil
    @State private var tapRunning = false
    @State private var axTrusted = false

    private let formatGroups: [(name: String, items: [String])] = [
        ("文档", ["Markdown 渲染", "log 日志高亮", "txt 兜底纯文本"]),
        ("压缩包", ["zip 清单（含中文名）", "tar / tar.gz / tgz", "大小与压缩比统计"]),
        ("数据", ["json 格式化", "jsonl / ndjson", "csv / tsv 表格"]),
        ("配置", ["yaml / toml / ini", "conf / cfg / env", "plist（含二进制）"]),
        ("代码", ["sql / swift / py / js", "ts / go / rust / java", "c / cpp / sh / rb 等 30+"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    stepsCard
                    statusCard
                    formatsCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 600, height: 600)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .init("GlanceStatusChanged"))) { _ in
            refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(colors: [Color(red: 1.0, green: 0.83, blue: 0.55),
                                            Color(red: 0.91, green: 0.64, blue: 0.24)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Text("␣")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("秒览 Glance")
                    .font(.system(size: 20, weight: .bold))
                Text("让空格键预览一切")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var stepsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                row(no: "1", text: "把 秒览.app 放进「应用程序」文件夹")
                row(no: "2", text: "授权辅助功能权限（接管空格键需要，仅用于读取 Finder 选中项）")
                row(no: "3", text: "在 Finder 选中 md、zip、sql 等文件，按空格键 ✓（←→ 可切换文件）")
            }
        }
    }

    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("运行状态").font(.system(size: 13, weight: .semibold))

                statusRow(
                    icon: tapRunning ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    color: tapRunning ? .green : .orange,
                    text: tapRunning ? "空格键接管：运行中" : "空格键接管：未运行（需要辅助功能权限）"
                )
                statusRow(
                    icon: axTrusted ? "checkmark.seal.fill" : "lock.fill",
                    color: axTrusted ? .green : .orange,
                    text: axTrusted ? "辅助功能权限：已授权" : "辅助功能权限：未授权"
                )
                statusRow(
                    icon: registered == true ? "checkmark.seal.fill" : "clock.fill",
                    color: registered == true ? .green : .secondary,
                    text: registered == true
                        ? "Quick Look 扩展：已注册（md 等系统不管的格式走秒览渲染）"
                        : "Quick Look 扩展：检查中…"
                )

                HStack {
                    Button("授权辅助功能") { SpaceTapController.shared.requestPermission() }
                        .controlSize(.small)
                    Button("重新检查") { refresh() }
                        .controlSize(.small)
                    Button("打开测试文件夹") { openFixtures() }
                        .controlSize(.small)
                    Spacer()
                    if !tapRunning {
                        Text("授权后点「重新检查」")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statusRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text).font(.system(size: 12))
            Spacer()
        }
    }

    private var formatsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("支持的格式").font(.system(size: 13, weight: .semibold))
                ForEach(formatGroups, id: \.name) { group in
                    HStack(alignment: .top, spacing: 10) {
                        Text(group.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.78, green: 0.55, blue: 0.18))
                            .frame(width: 42, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(group.items, id: \.self) { item in
                                Text("· \(item)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                        }
                    }
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private func row(no: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(no)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color(red: 0.91, green: 0.64, blue: 0.24)))
            Text(text).font(.system(size: 12.5))
            Spacer()
        }
    }

    private func refresh() {
        tapRunning = SpaceTapController.shared.isRunning
        axTrusted = AXIsProcessTrusted()
        DispatchQueue.global().async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            task.arguments = ["-m", "-p", "com.apple.quicklook.preview"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            try? task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.registered = text.contains("com.qishuai.glance.QLExtension")
            }
        }
    }

    private func openFixtures() {
        NSWorkspace.shared.open(URL(fileURLWithPath: ProjectPath.fixtures))
    }
}

enum ProjectPath {
    /// 开发环境测试样例目录（装进 /Applications 后回退到常见位置）
    static let fixtures: String = {
        let dev = "/Users/qishuai/ZCodeProject/Glance/fixtures"
        if FileManager.default.fileExists(atPath: dev) { return dev }
        return "~/Documents"
    }()
}
