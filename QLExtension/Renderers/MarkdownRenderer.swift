import Foundation
import UniformTypeIdentifiers

/// Markdown → HTML：块级逐行状态机 + 行内格式，支持本地图片转 data URI、代码块语法高亮。
enum MarkdownRenderer {

    static func render(text: String, baseURL: URL, truncated: Bool) -> String {
        var body = ""
        if truncated {
            body += "<div class=\"hint\">文件较大，仅显示开头部分内容。</div>"
        }
        body += "<div class=\"md\">\(blocks(text, baseURL: baseURL))</div>"
        return body
    }

    // MARK: - 块级解析

    private static func blocks(_ text: String, baseURL: URL) -> String {
        var out = ""
        var lines = Array(text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        if let last = lines.last, last.isEmpty { lines.removeLast() }

        var i = 0
        var para: [String] = []
        func flushPara() {
            if !para.isEmpty {
                out += "<p>\(inline(para.joined(separator: " "), baseURL: baseURL))</p>"
                para = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码围栏 ```…```
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushPara()
                let fence = String(line.prefix(3))
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].hasPrefix(fence) {
                    codeLines.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }
                let code = codeLines.joined(separator: "\n")
                if let l = Lang.table[lang] {
                    out += "<pre><code>\(CodeRenderer.highlight(code: code, lang: l))</code></pre>"
                } else {
                    out += "<pre><code>\(HTML.escape(code))</code></pre>"
                }
                continue
            }

            // ATX 标题 # ~ ######
            if trimmed.hasPrefix("#") {
                let level = min(trimmed.prefix(while: { $0 == "#" }).count, 6)
                var content = trimmed.dropFirst(level)
                if content.hasPrefix(" ") { content = content.dropFirst() }
                if !content.isEmpty {
                    flushPara()
                    out += "<h\(level)>\(inline(String(content), baseURL: baseURL))</h\(level)>"
                    i += 1
                    continue
                }
            }

            // 分隔线
            if trimmed.count >= 3,
               Set(trimmed).isSubset(of: Set("-*_ ")),
               trimmed.contains("--") || trimmed.contains("**") {
                flushPara()
                out += "<hr>"
                i += 1
                continue
            }

            // 表格
            if line.contains("|"), i + 1 < lines.count, isTableDivider(lines[i + 1]) {
                flushPara()
                let header = splitTableRow(line)
                i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(splitTableRow(lines[i])); i += 1
                }
                var t = "<table><thead><tr>"
                for h in header { t += "<th>\(inline(h, baseURL: baseURL))</th>" }
                t += "</tr></thead><tbody>"
                for row in rows {
                    t += "<tr>"
                    for c in 0..<max(header.count, row.count) {
                        let cell = c < row.count ? row[c] : ""
                        t += "<td>\(inline(cell, baseURL: baseURL))</td>"
                    }
                    t += "</tr>"
                }
                t += "</tbody></table>"
                out += t
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                flushPara()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                        .drop(while: { $0 == " " })))
                    i += 1
                }
                out += "<blockquote>\(inline(quote.joined(separator: " "), baseURL: baseURL))</blockquote>"
                continue
            }

            // 列表
            if listMarker(trimmed) != nil {
                flushPara()
                let (html, next) = renderList(lines: lines, start: i, baseIndent: indent(of: line), baseURL: baseURL)
                out += html
                i = next
                continue
            }

            // 空行分段
            if trimmed.isEmpty {
                flushPara()
                i += 1
                continue
            }

            para.append(line)
            i += 1
        }
        flushPara()
        return out
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.allSatisfy({ "|-: \t".contains($0) }) else { return false }
        return true
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// 列表标记：无序 - * +；有序 1. —— 返回该项内容。
    private static func listMarker(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return String(trimmed.dropFirst(2))
        }
        if let dot = trimmed.firstIndex(of: "."), dot != trimmed.startIndex,
           trimmed.distance(from: trimmed.startIndex, to: dot) <= 3,
           trimmed.prefix(upTo: dot).allSatisfy(\.isNumber),
           trimmed.distance(from: dot, to: trimmed.endIndex) > 1 {
            return String(trimmed[trimmed.index(after: dot)...]).drop(while: { $0 == " " }).description
        }
        return nil
    }

    /// 行首缩进列数（tab 记 4）。
    private static func indent(of line: String) -> Int {
        var n = 0
        for ch in line {
            if ch == " " { n += 1 }
            else if ch == "\t" { n += 4 }
            else { break }
        }
        return n
    }

    /// 递归渲染列表；返回（HTML，下一行下标）。
    private static func renderList(lines: [String], start: Int, baseIndent: Int, baseURL: URL) -> (String, Int) {
        guard start < lines.count, listMarker(lines[start].trimmingCharacters(in: .whitespaces)) != nil
        else { return ("", start) }
        let ordered = orderedList(lines[start])
        var out = ordered ? "<ol>" : "<ul>"
        var i = start
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let ind = indent(of: line)

            if trimmed.isEmpty {
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                if j < lines.count, indent(of: lines[j]) == baseIndent,
                   listMarker(lines[j].trimmingCharacters(in: .whitespaces)) != nil {
                    i = j
                    continue
                }
                break
            }

            if ind < baseIndent { break }

            if ind > baseIndent {
                guard listMarker(trimmed) != nil else { break }
                let (sub, next) = renderList(lines: lines, start: i, baseIndent: ind, baseURL: baseURL)
                if sub.isEmpty { break }
                out += sub
                i = next
                continue
            }

            guard let content = listMarker(trimmed) else { break }
            // 任务列表
            if content.hasPrefix("[ ] ") {
                out += "<li>☐ \(inline(String(content.dropFirst(4)), baseURL: baseURL))</li>"
            } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                out += "<li>☑ \(inline(String(content.dropFirst(4)), baseURL: baseURL))</li>"
            } else {
                out += "<li>\(inline(content, baseURL: baseURL))</li>"
            }
            i += 1
        }
        out += ordered ? "</ol>" : "</ul>"
        return (out, i)
    }

    private static func orderedList(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if let dot = t.firstIndex(of: "."), dot != t.startIndex,
           t.prefix(upTo: dot).allSatisfy(\.isNumber) { return true }
        return false
    }

    // MARK: - 行内解析

    private static func inline(_ raw: String, baseURL: URL) -> String {
        var s = HTML.escape(raw)

        // 行内代码先摘出来，避免内部被格式化
        var codes: [String] = []
        while let r = s.range(of: "`([^`]+)`", options: .regularExpression) {
            let content = String(s[s.index(after: r.lowerBound)..<s.index(before: r.upperBound)])
            codes.append(content)
            s.replaceSubrange(r, with: "\u{E000}CODE\(codes.count - 1)\u{E001}")
        }

        // 图片（先于链接）
        while let r = s.range(of: "!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)", options: .regularExpression) {
            let m = String(s[r])
            let alt = capture(m, pattern: "!\\[([^\\]]*)\\]")
            let src = capture(m, pattern: "\\(([^)\\s]+)\\)")
            s.replaceSubrange(r, with: imageTag(alt: alt, src: unescapeMinimal(src), baseURL: baseURL))
        }

        // 链接
        while let r = s.range(of: "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", options: .regularExpression) {
            let m = String(s[r])
            let text2 = capture(m, pattern: "\\[([^\\]]+)\\]")
            let url = capture(m, pattern: "\\(([^)\\s]+)\\)")
            s.replaceSubrange(r, with: "<a href=\"\(HTML.escape(url))\">\(text2)</a>")
        }

        // 粗体、斜体、删除线
        s = regexReplace(s, pattern: "\\*\\*([^*]+)\\*\\*", tpl: "<strong>$1</strong>")
        s = regexReplace(s, pattern: "__([^_]+)__", tpl: "<strong>$1</strong>")
        s = regexReplace(s, pattern: "(?<![\\w*])\\*([^*\\n]+)\\*(?![\\w*])", tpl: "<em>$1</em>")
        s = regexReplace(s, pattern: "~~([^~]+)~~", tpl: "<del>$1</del>")

        for (idx, c) in codes.enumerated() {
            s = s.replacingOccurrences(of: "\u{E000}CODE\(idx)\u{E001}",
                                       with: "<code>\(HTML.escape(c))</code>")
        }
        return s
    }

    private static func regexReplace(_ s: String, pattern: String, tpl: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length),
                                           withTemplate: tpl)
    }

    private static func capture(_ text: String, pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return "" }
        return String(text[r])
    }

    private static func unescapeMinimal(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 本地图片 → data URI；网络图片保留 URL。
    private static func imageTag(alt: String, src: String, baseURL: URL) -> String {
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            return "<img src=\"\(HTML.escape(src))\" alt=\"\(HTML.escape(alt))\">"
        }
        var fileURL: URL?
        if src.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: src)
        } else if src.hasPrefix("~") {
            fileURL = URL(fileURLWithPath: NSString(string: src).expandingTildeInPath)
        } else {
            fileURL = URL(string: src, relativeTo: baseURL)?.standardizedFileURL
        }
        if let u = fileURL, let data = try? Data(contentsOf: u), !data.isEmpty,
           data.count <= 3_000_000,
           let type = UTType(filenameExtension: u.pathExtension), type.conforms(to: .image),
           let mime = type.preferredMIMEType {
            return "<img src=\"data:\(mime);base64,\(data.base64EncodedString())\" alt=\"\(HTML.escape(alt))\">"
        }
        return "<span style=\"color:#b85c38\">[图片: \(HTML.escape(alt.isEmpty ? src : alt))]</span>"
    }
}
