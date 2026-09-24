import Foundation

/// JSON：解析后重排版 + 语法着色；JSONL 逐行处理。
enum JSONRenderer {

    private static let scanner = CodeRenderer.makeScanner(
        parts: [
            ("key", "\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)"),
            ("str", "\"(?:\\\\.|[^\"\\\\])*\""),
            ("bool", "\\b(?:true|false|null)\\b"),
            ("num", "-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"),
        ],
        classes: ["key": "f", "str": "s", "bool": "t", "num": "n"])

    static func render(text: String, truncated: Bool, isJSONL: Bool) -> String {
        var body = ""
        if truncated {
            body += "<div class=\"hint\">文件较大，仅显示开头部分。</div>"
        }

        if isJSONL {
            var rows = ""
            var shown = 0
            var failed = 0
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                shown += 1
                if shown > 500 {
                    body += "<div class=\"hint\">行数较多，仅显示前 500 行。</div>"
                    break
                }
                let s = String(line)
                if let pretty = Self.prettyLine(s) {
                    rows += "<tr><td class=\"cl\">\(highlight(pretty))</td></tr>"
                } else {
                    failed += 1
                    rows += "<tr><td class=\"cl\">\(HTML.escape(s))</td></tr>"
                }
            }
            if failed > 0 {
                body += "<div class=\"hint\">\(failed) 行不是合法 JSON，按原文显示。</div>"
            }
            body += "<table class=\"code\">\(rows)</table>"
            return body
        }

        if let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: []) {
            let pretty = prettyText(obj: obj) ?? text
            let lines = pretty.split(separator: "\n", omittingEmptySubsequences: false)
            var rows = ""
            for (idx, line) in lines.enumerated() {
                rows += "<tr><td class=\"ln\">\(idx + 1)</td><td class=\"cl\">\(highlight(String(line)))</td></tr>"
            }
            body += "<table class=\"code\">\(rows)</table>"
        } else {
            body += "<div class=\"hint\">不是合法 JSON，按纯文本显示。</div>"
            body += CodeRenderer.render(text: text, mode: .plain, truncated: false, shownLines: 0)
        }
        return body
    }

    private static func prettyLine(_ s: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8), options: []) else {
            return nil
        }
        return prettyText(obj: obj)
    }

    private static func prettyText(obj: Any) -> String? {
        if JSONSerialization.isValidJSONObject(obj) {
            guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                  let s = String(data: d, encoding: .utf8) else { return nil }
            return s
        }
        if let n = obj as? NSNumber { return n.stringValue }
        if let s = obj as? String { return s }
        return nil
    }

    private static func highlight(_ line: String) -> String {
        scanner.run(Substring(line)).html
    }
}
