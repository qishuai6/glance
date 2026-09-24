import Foundation
import UniformTypeIdentifiers

/// 分发中枢：按扩展名路由到对应渲染器，统一产出完整 HTML 页面。
enum RendererHub {

    static func render(url: URL) -> String {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let baseName = (name as NSString).deletingPathExtension
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        let size = bytes ?? 0
        let meta = "\(HTML.fmtBytes(size))"

        // Makefile / Dockerfile 等无扩展名特殊文件名
        let special = name.lowercased()
        switch ext.isEmpty ? special : ext {
        case "makefile":
            return textPage(url: url, name: name, badge: "MK", meta: meta, mode: .code(Lang.table["make"]!))
        case "dockerfile":
            return textPage(url: url, name: name, badge: "DK", meta: meta,
                            mode: .code(Lang(name: "Docker", keywords: Set("FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL as".split(separator: " ").map(String.init)),
                                             lineComments: ["#"], blockComment: nil, types: Set())))
        default:
            break
        }

        switch ext {
        // ---- 文档 ----
        case "md", "markdown":
            let (text, trunc, _) = readText(url, maxBytes: 2_000_000)
            let body = MarkdownRenderer.render(text: text, baseURL: url.deletingLastPathComponent(), truncated: trunc)
            return HTML.page(badge: "MD", name: name, meta: meta, body: body)

        // ---- 压缩包 ----
        case "zip":
            return HTML.page(badge: "ZIP", name: name, meta: meta,
                             body: ArchiveRenderer.renderZip(url: url, totalBytes: size))
        case "tar":
            return HTML.page(badge: "TAR", name: name, meta: meta,
                             body: ArchiveRenderer.renderTar(url: url, totalBytes: size, gz: false))
        case "tgz":
            return HTML.page(badge: "TGZ", name: name, meta: meta,
                             body: ArchiveRenderer.renderTar(url: url, totalBytes: size, gz: true))

        // ---- 表格 ----
        case "csv":
            let (text, trunc, _) = readText(url, maxBytes: 5_000_000)
            return HTML.page(badge: "CSV", name: name, meta: meta,
                             body: TableRenderer.render(text: text, separator: ",", truncated: trunc))
        case "tsv":
            let (text, trunc, _) = readText(url, maxBytes: 5_000_000)
            return HTML.page(badge: "TSV", name: name, meta: meta,
                             body: TableRenderer.render(text: text, separator: "\t", truncated: trunc))

        // ---- JSON ----
        case "json":
            let (text, trunc, _) = readText(url, maxBytes: 8_000_000)
            return HTML.page(badge: "JSON", name: name, meta: meta,
                             body: JSONRenderer.render(text: text, truncated: trunc, isJSONL: false))
        case "jsonl", "ndjson":
            let (text, trunc, _) = readText(url, maxBytes: 4_000_000)
            return HTML.page(badge: "JSONL", name: name, meta: meta,
                             body: JSONRenderer.render(text: text, truncated: trunc, isJSONL: true))

        // ---- 结构化配置 ----
        case "yaml", "yml", "toml", "ini", "conf", "cfg", "env", "properties":
            let badge = (ext == "yaml" || ext == "yml") ? "YAML" : ext.uppercased()
            return textPage(url: url, name: name, badge: badge, meta: meta, mode: .structured)

        // ---- 日志 ----
        case "log":
            return textPage(url: url, name: name, badge: "LOG", meta: meta, mode: .log)

        // ---- plist ----
        case "plist":
            if let body = Plistish.render(url: url, name: name) {
                return HTML.page(badge: "PLIST", name: name, meta: meta, body: body)
            }
            return textPage(url: url, name: name, badge: "PLIST", meta: meta, mode: .xml)

        // ---- XML / CSS / 已知代码语言 ----
        case "xml":
            return textPage(url: url, name: name, badge: "XML", meta: meta, mode: .xml)
        case "css":
            return textPage(url: url, name: name, badge: "CSS", meta: meta, mode: .css)
        case "h", "hpp":
            let lang = Lang.table[ext]!
            return textPage(url: url, name: name, badge: ext.uppercased(), meta: meta, mode: .code(lang))
        default:
            if let lang = Lang.table[ext] {
                return textPage(url: url, name: name, badge: ext.uppercased(), meta: meta, mode: .code(lang))
            }
            break
        }

        // ---- 兜底：纯文本（按 UTType 判断） ----
        if isProbablyText(url: url) {
            return textPage(url: url, name: name, badge: "TXT", meta: meta, mode: .plain)
        }
        return HTML.page(badge: "?", name: name, meta: meta, body: """
        <div class="unsupported"><div class="em">🫥</div>
        <p><b>\(HTML.escape(baseName))</b>（.\(HTML.escape(ext))）暂不支持富预览</p>
        </div>
        """)
    }

    // MARK: - 文本页面通用流程

    private static func textPage(url: URL, name: String, badge: String, meta: String, mode: CodeRenderer.Mode) -> String {
        let (text, trunc, lines) = readText(url, maxBytes: 1_000_000)
        let body = CodeRenderer.render(text: text, mode: mode, truncated: trunc, shownLines: lines)
        return HTML.page(badge: badge, name: name, meta: meta, body: body)
    }

    /// 最多读 maxBytes；返回（文本、是否截断、行数）。
    static func readText(_ url: URL, maxBytes: Int) -> (String, Bool, Int) {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return ("（无法读取文件）", false, 0) }
        defer { try? fh.close() }
        var data = (try? fh.read(upToCount: maxBytes + 1)) ?? Data()
        var truncated = false
        if data.count > maxBytes {
            truncated = true
            data = data.prefix(maxBytes)
        }
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
            ?? String(data: data, encoding: .isoLatin1)
            ?? "（无法按文本解码）"
        if truncated, let lastNL = text.lastIndex(of: "\n") {
            text = String(text[..<lastNL]) // 丢掉半截行
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return (text, truncated, lines)
    }

    private static func isProbablyText(url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url),
              let head = try? fh.read(upToCount: 4096) else { return false }
        try? fh.close()
        if head.isEmpty { return true }
        if head.prefix(4) == Data([0x25, 0x50, 0x44, 0x46]) { return false } // %PDF
        // 含 NUL 视为二进制
        return !head.contains(0)
    }
}

/// plist：二进制 → 结构化文本；XML → 标签高亮。
enum Plistish {
    static func render(url: URL, name: String) -> String? {
        guard let data = try? Data(contentsOf: url),
              data.count < 4_000_000 else { return nil }
        if data.starts(with: Data("bplist00".utf8)) {
            guard let obj = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) else { return nil }
            var out = "<table class=\"code\">"
            var i = 0
            for line in describe(obj).split(separator: "\n", omittingEmptySubsequences: false) {
                i += 1
                out += "<tr><td class=\"ln\">\(i)</td><td class=\"cl\">\(HTML.escape(String(line)))</td></tr>"
            }
            out += "</table>"
            return "<div class=\"hint\">二进制 plist 已转为可读结构。</div>" + out
        }
        return nil // XML plist 走 xml 高亮
    }

    private static func describe(_ obj: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch obj {
        case let d as [String: Any]:
            if d.isEmpty { return pad + "{}" }
            var lines: [String] = []
            for k in d.keys.sorted() {
                let v = d[k]!
                if isScalar(v) {
                    lines.append("\(pad)\(k): \(scalarText(v))")
                } else {
                    lines.append("\(pad)\(k):")
                    lines.append(describe(v, indent: indent + 1))
                }
            }
            return lines.joined(separator: "\n")
        case let a as [Any]:
            if a.isEmpty { return pad + "[]" }
            var lines: [String] = []
            for v in a {
                if isScalar(v) {
                    lines.append("\(pad)- \(scalarText(v))")
                } else {
                    lines.append("\(pad)-")
                    lines.append(describe(v, indent: indent + 1))
                }
            }
            return lines.joined(separator: "\n")
        default:
            return pad + scalarText(obj)
        }
    }

    private static func isScalar(_ v: Any) -> Bool {
        v is String || v is NSNumber || v is Date || v is Data || v is Bool
    }

    private static func scalarText(_ v: Any) -> String {
        switch v {
        case let d as Data:
            return "<Data \(d.count)B>"
        case let s as String:
            return "\"\(s)\""
        default:
            return "\(v)"
        }
    }
}
