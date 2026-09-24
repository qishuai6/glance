import Foundation

/// CSV / TSV → HTML 表格。
enum TableRenderer {

    static func render(text: String, separator: Character, truncated: Bool) -> String {
        let rows = parse(text: text, separator: separator)
        guard !rows.isEmpty else {
            return "<div class=\"unsupported\"><div class=\"em\">🗂️</div>空表格</div>"
        }

        let totalRows = rows.count - 1
        let cols = rows.map(\.count).max() ?? 0
        let shownRows = Array(rows.prefix(201))   // 表头 + 200 行
        let hidden = rows.count - shownRows.count

        var body = ""
        if truncated {
            body += "<div class=\"hint\">文件较大，仅解析了开头部分。</div>"
        }
        body += """
        <div class="stats">
          <div class="stat"><b>\(totalRows)</b><span>数据行</span></div>
          <div class="stat"><b>\(cols)</b><span>列</span></div>
          <div class="stat"><b>\(HTML.fmtBytes(text.utf8.count))</b><span>文件大小</span></div>
        </div>
        """
        if hidden > 0 {
            body += "<div class=\"hint\">仅显示前 \(shownRows.count - 1) 行，还有 \(hidden) 行未展示。</div>"
        }

        body += "<table class=\"grid\"><thead><tr>"
        for (idx, h) in shownRows[0].enumerated() {
            body += "<th>\(HTML.escape(h.isEmpty ? "列\(idx + 1)" : h))</th>"
        }
        body += "</tr></thead><tbody>"
        for row in shownRows.dropFirst() {
            body += "<tr>"
            for c in 0..<cols {
                let cell = c < row.count ? row[c] : ""
                body += "<td>\(HTML.escape(cell))</td>"
            }
            body += "</tr>"
        }
        body += "</tbody></table>"
        return body
    }

    /// RFC4180 状态机解析（支持引号、双写转义、字段内换行）；TSV 同一状态机不同分隔符。
    static func parse(text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while i < text.endIndex {
            let ch = text[i]
            if inQuotes {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\""); i = text.index(after: next); continue
                    }
                    inQuotes = false
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" && field.isEmpty {
                inQuotes = true
            } else if ch == separator {
                endField()
            } else if ch == "\r" {
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "\n" { i = next }
                endRow()
            } else if ch == "\n" {
                endRow()
            } else {
                field.append(ch)
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
