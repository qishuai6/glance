import Foundation

/// 通用高亮引擎：代码 / 日志 / 结构化配置 / 纯文本四种模式，输出带行号的 HTML。
enum CodeRenderer {

    // MARK: - 组合正则扫描器

    /// 多模式合并为一个正则，按 named group 取类别，一次扫描上色。
    final class Scanner {
        let regex: NSRegularExpression
        // group 名 → CSS class；空串表示不上色；"@word" 表示交给 classifyWord 动态判定
        let classes: [String: String]
        let classifyWord: ((String, String) -> String?)?

        init(parts: [(name: String, pattern: String)],
             classes: [String: String],
             classifyWord: ((String, String) -> String?)? = nil) {
            self.classes = classes
            self.classifyWord = classifyWord
            let joined = parts.map { "(?<\($0.name)>\($0.pattern))" }.joined(separator: "|")
            self.regex = try! NSRegularExpression(pattern: joined)
        }

        func run(_ text: Substring, inBlock: Bool = false) -> (html: String, nextInBlock: Bool) {
            var out = ""
            var last = text.startIndex
            var blockNext = inBlock
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for m in regex.matches(in: String(text), range: range) {
                var cls: String? = nil
                for (name, c) in classes {
                    if m.range(withName: name).location != NSNotFound { cls = c; break }
                }
                guard let c = cls, let r = Range(m.range, in: text) else { continue }
                if r.lowerBound > last { out += HTML.escape(String(text[last..<r.lowerBound])) }
                let word = String(text[r])
                if c == "@word", let cw = classifyWord {
                    let isCall = r.upperBound < text.endIndex && text[r.upperBound] == "("
                    if let klass = cw(word, isCall ? "f" : ""), !klass.isEmpty {
                        out += "<span class=\"\(klass)\">\(HTML.escape(word))</span>"
                    } else {
                        out += HTML.escape(word)
                    }
                } else if c.isEmpty {
                    out += HTML.escape(word)
                } else {
                    out += "<span class=\"\(c)\">\(HTML.escape(word))</span>"
                }
                last = r.upperBound
            }
            if last < text.endIndex {
                let rest = text[last...]
                // 本行残留未闭合的 /* → 到行尾全部视为注释，并保持块注释状态
                if let p = rest.range(of: "/*"), !rest[p.upperBound...].contains("*/") {
                    out += HTML.escape(String(rest[..<p.lowerBound]))
                    out += "<span class=\"c\">\(HTML.escape(String(rest[p.lowerBound...])))</span>"
                    blockNext = true
                } else {
                    out += HTML.escape(String(rest))
                }
            }
            return (out, blockNext)
        }
    }

    // MARK: - 代码模式（逐行 + 块注释状态）

    private static var scannerCache: [String: Scanner] = [:]
    private static let cacheLock = NSLock()

    private static func scanner(for lang: Lang) -> Scanner {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let s = scannerCache[lang.name] { return s }
        var parts: [(String, String)] = []
        var classes: [String: String] = [:]
        if let (bs, be) = lang.blockComment {
            parts.append(("bc", "\(escRe(bs)).*?(?:\(escRe(be))|$)"))
            classes["bc"] = "c"
        }
        for (i, lc) in lang.lineComments.enumerated() {
            parts.append(("lc\(i)", "\(escRe(lc)).*"))
            classes["lc\(i)"] = "c"
        }
        parts.append(("str", "\"(?:\\\\.|[^\"\\\\\\n])*\"|'(?:[^'\\n]*)'|`(?:\\\\.|[^`\\\\])*`"))
        classes["str"] = "s"
        parts.append(("num", "\\b(?:0[xX][0-9a-fA-F]+|\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?[a-zA-Z]{0,3})\\b"))
        classes["num"] = "n"
        parts.append(("word", "[A-Za-z_][A-Za-z0-9_]*"))
        classes["word"] = "@word"
        let s = Scanner(parts: parts, classes: classes) { w, call in
            let lw = w.lowercased() // SQL 等语言大小写不敏感
            if lang.keywords.contains(w) || lang.keywords.contains(lw) { return "k" }
            if lang.types.contains(w) || lang.types.contains(lw) { return "t" }
            if call == "f" { return "f" }
            return nil
        }
        scannerCache[lang.name] = s
        return s
    }

    private static func escRe(_ s: String) -> String {
        NSRegularExpression.escapedPattern(for: s)
    }

    /// 供其他渲染器（JSON 等）复用的扫描器工厂。
    static func makeScanner(parts: [(name: String, pattern: String)],
                            classes: [String: String]) -> Scanner {
        Scanner(parts: parts, classes: classes)
    }

    /// 高亮整段代码（含跨行块注释状态机），返回已着色 HTML。
    static func highlight(code text: String, lang: Lang) -> String {
        var out = ""
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let (html, next) = scanner(for: lang).run(line, inBlock: inBlock)
            out += html + "\n"
            inBlock = next
        }
        return out
    }

    // MARK: - XML / CSS

    private static let xmlScanner = Scanner(
        parts: [("c", "<!--.*?-->"), ("tag", "</?[A-Za-z?!][^>]*>?"), ("str", "\"[^\"]*\"|'[^']*'")],
        classes: ["c": "c", "tag": "t", "str": "s"])

    private static let cssScanner = Scanner(
        parts: [("c", "/\\*.*?\\*/"), ("str", "\"[^\"]*\"|'[^']*'"),
                ("at", "@[a-zA-Z-]+"), ("prop", "[a-zA-Z-]+(?=\\s*:)"),
                ("num", "#[0-9a-fA-F]{3,8}\\b|\\b\\d+(?:\\.\\d+)?(?:px|em|rem|vh|vw|%|s|ms|deg|fr)?\\b")],
        classes: ["c": "c", "str": "s", "at": "t", "prop": "k", "num": "n"])

    // MARK: - 日志模式

    private static let logScanner = Scanner(
        parts: [("ts", "\\b\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(?:[.,]\\d+)?(?:Z|[+-]\\d{2}:?\\d{2})?\\b"),
                ("lvErr", "\\b(?:ERROR|ERR|FATAL|CRITICAL)\\b"),
                ("lvWarn", "\\b(?:WARN|WARNING)\\b"),
                ("lvInfo", "\\b(?:INFO|NOTICE)\\b"),
                ("lvDebug", "\\b(?:DEBUG|TRACE)\\b")],
        classes: ["ts": "ts", "lvErr": "lv-err", "lvWarn": "lv-warn",
                  "lvInfo": "lv-info", "lvDebug": "lv-debug"])

    static func highlight(log text: String) -> String {
        var out = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let (html, _) = logScanner.run(line)
            out += html + "\n"
        }
        return out
    }

    // MARK: - 结构化配置（yaml / toml / ini / env）

    static func highlight(structured text: String) -> String {
        let kv = try! NSRegularExpression(
            pattern: "^(?<pre>\\s*)(?<dash>- )?(?<key>[^:#=\\n]{1,120}?)(?<eq>[:=]\\s*)(?<val>.*)$")
        let valueScanner = Scanner(
            parts: [("str", "\"[^\"]*\"|'[^']*'"),
                    ("bool", "\\b(?:true|false|null|yes|no|on|off|True|False|None)\\b"),
                    ("num", "\\b\\d+(?:\\.\\d+)?\\b")],
            classes: ["str": "s", "bool": "t", "num": "n"])
        let section = try! NSRegularExpression(pattern: "^\\s*\\[[^\\]\\n]+\\]")
        let comment = try! NSRegularExpression(pattern: "^\\s*[#;]")

        var out = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = Substring(line)
            let r = NSRange(s.startIndex..., in: s)
            if comment.firstMatch(in: String(s), range: r) != nil {
                out += "<span class=\"c\">\(HTML.escape(String(s)))</span>\n"
                continue
            }
            if section.firstMatch(in: String(s), range: r) != nil {
                out += "<span class=\"t\">\(HTML.escape(String(s)))</span>\n"
                continue
            }
            if let m = kv.firstMatch(in: String(s), range: r),
               let keyR = Range(m.range(withName: "key"), in: s),
               let eqR = Range(m.range(withName: "eq"), in: s),
               let valR = Range(m.range(withName: "val"), in: s),
               let preR = Range(m.range(withName: "pre"), in: s) {
                let dash = m.range(withName: "dash")
                let dashText = dash.location != NSNotFound ? String(s[Range(dash, in: s)!]) : ""
                let (vh, _) = valueScanner.run(s[valR])
                out += "\(HTML.escape(String(s[preR])))\(dashText)<span class=\"k\">\(HTML.escape(String(s[keyR])))</span>\(HTML.escape(String(s[eqR])))\(vh)\n"
                continue
            }
            out += HTML.escape(String(s)) + "\n"
        }
        return out
    }

    // MARK: - 渲染入口

    static func render(text: String, mode: Mode, truncated: Bool, shownLines: Int) -> String {
        var body = ""
        if truncated {
            body += "<div class=\"hint\">文件较大，仅显示前 \(shownLines) 行，其余内容已省略。</div>"
        }
        let colored: String
        switch mode {
        case .code(let lang): colored = highlight(code: text, lang: lang)
        case .log: colored = highlight(log: text)
        case .structured: colored = highlight(structured: text)
        case .plain: colored = HTML.escape(text)
        case .xml: colored = xmlScanner.run(Substring(text)).html
        case .css: colored = cssScanner.run(Substring(text)).html
        }
        var rows = ""
        var i = 0
        for line in colored.split(separator: "\n", omittingEmptySubsequences: false) {
            i += 1
            rows += "<tr><td class=\"ln\">\(i)</td><td class=\"cl\">\(line)</td></tr>"
        }
        body += "<table class=\"code\">\(rows)</table>"
        return body
    }

    enum Mode {
        case code(Lang)
        case log
        case structured
        case plain
        case xml
        case css
    }
}
