import Foundation

/// Jupyter Notebook（.ipynb）预览：按 cell 渲染 markdown / 代码 / 输出。
enum NotebookRenderer {

    static func render(url: URL, totalBytes: Int) -> String {
        guard let data = try? Data(contentsOf: url), data.count < 20_000_000,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "<div class=\"unsupported\"><div class=\"em\">📓</div>无法解析 Notebook</div>"
        }
        let cells = obj["cells"] as? [[String: Any]] ?? []
        let kernel = ((obj["metadata"] as? [String: Any])?["language_info"] as? [String: Any])?["name"] as? String ?? "python"

        var body = """
        <div class="stats">
          <div class="stat"><b>\(cells.count)</b><span>Cell 数</span></div>
          <div class="stat"><b>\(HTML.escape(kernel))</b><span>内核</span></div>
          <div class="stat"><b>\(HTML.fmtBytes(totalBytes))</b><span>文件大小</span></div>
        </div>
        """

        let lang = Lang.table[kernel] ?? Lang(name: kernel, keywords: Set(), lineComments: ["#"], blockComment: nil, types: Set())
        var shown = 0
        for cell in cells.prefix(60) {
            let type = cell["cell_type"] as? String ?? "raw"
            let source = joinSource(cell["source"])
            shown += 1

            switch type {
            case "markdown":
                body += "<div class=\"md\" style=\"border-top:1px dashed #eee9e0;padding-top:12px;margin-top:12px\">"
                body += MarkdownRenderer.render(text: String(source.prefix(20_000)), baseURL: url.deletingLastPathComponent(), truncated: source.count > 20_000)
                body += "</div>"
            case "code":
                body += "<div style=\"border-top:1px dashed #eee9e0;padding-top:12px;margin-top:12px\">"
                body += "<div style=\"font-size:11px;color:#98928a;margin-bottom:4px\">In [\((cell["execution_count"] as? Int).map(String.init) ?? " ")]:</div>"
                body += CodeRenderer.render(text: String(source.prefix(10_000)),
                                            mode: .code(lang), truncated: false, shownLines: 0)
                // 输出
                for out in (cell["outputs"] as? [[String: Any]] ?? []).prefix(6) {
                    body += renderOutput(out)
                }
                body += "</div>"
            default:
                if !source.isEmpty {
                    body += "<pre style=\"background:#f8f6f1;border-radius:8px;padding:10px 14px;font-size:12px;white-space:pre-wrap\">\(HTML.escape(String(source.prefix(3000))))</pre>"
                }
            }
        }
        if cells.count > shown {
            body += "<div class=\"hint\">仅显示前 \(shown) 个 Cell，共 \(cells.count) 个。</div>"
        }
        return body
    }

    private static func renderOutput(_ out: [String: Any]) -> String {
        let type = out["output_type"] as? String ?? ""
        if type == "stream" {
            let text = joinSource(out["text"])
            return "<pre style=\"background:#fbfaf7;border-left:3px solid #d8d2c6;border-radius:0 8px 8px 0;padding:8px 12px;font-size:12px;white-space:pre-wrap\">\(HTML.escape(String(text.prefix(5000))))</pre>"
        }
        if let dataDict = out["data"] as? [String: Any] {
            if let b64 = dataDict["image/png"] as? String, !b64.isEmpty {
                return "<img src=\"data:image/png;base64,\(b64)\" style=\"max-width:100%;border-radius:8px;margin:6px 0;box-shadow:0 2px 10px rgba(0,0,0,.07)\">"
            }
            if let text = dataDict["text/plain"] {
                let t = joinSource(text)
                return "<pre style=\"font-size:12px;white-space:pre-wrap;color:#2b7a8c\">\(HTML.escape(String(t.prefix(3000))))</pre>"
            }
        }
        return ""
    }

    private static func joinSource(_ source: Any?) -> String {
        if let s = source as? String { return s }
        if let arr = source as? [String] { return arr.joined() }
        return ""
    }
}
