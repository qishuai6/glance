import Foundation

/// 公共 HTML 页面骨架与工具：秒览统一视觉（暖白 + 杏黄 + 轻阴影）。
enum HTML {
    static func escape(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&", with: "&amp;")
        r = r.replacingOccurrences(of: "<", with: "&lt;")
        r = r.replacingOccurrences(of: ">", with: "&gt;")
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        return r
    }

    static func fmtBytes(_ n: Int) -> String {
        let d = Double(n)
        if d < 1024 { return "\(n) B" }
        if d < 1024 * 1024 { return String(format: "%.1f KB", d / 1024) }
        if d < 1024 * 1024 * 1024 { return String(format: "%.1f MB", d / 1024 / 1024) }
        return String(format: "%.2f GB", d / 1024 / 1024 / 1024)
    }

    /// 完整页面：顶栏（类型徽标 + 文件名 + 元信息）+ 内容卡片。
    static func page(badge: String, name: String, meta: String, body: String, card: Bool = true) -> String {
        let inner = card ? "<div class=\"card\">\(body)</div>" : body
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}
        body{margin:0;background:#f6f5f2;color:#2b2a28;
             font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;font-size:14px}
        .topbar{position:sticky;top:0;z-index:9;display:flex;align-items:center;gap:10px;
                padding:10px 22px;background:rgba(255,255,255,.9);
                border-bottom:1px solid #e9e6e0}
        .badge{background:#e8a33d;color:#fff;font-weight:600;font-size:11px;
               border-radius:6px;padding:3px 9px;letter-spacing:.8px}
        .fname{font-weight:600;font-size:14px}
        .meta{margin-left:auto;color:#98928a;font-size:12px;white-space:nowrap}
        .content{max-width:900px;margin:22px auto;padding:0 22px 44px}
        .card{background:#fff;border-radius:12px;padding:26px 30px;
              box-shadow:0 1px 2px rgba(0,0,0,.05),0 6px 24px rgba(0,0,0,.06)}
        .hint{background:#fbf3e4;border:1px solid #f0dfba;color:#8a6a2f;
              border-radius:8px;padding:8px 14px;font-size:12px;margin-bottom:16px}
        .glance{color:#c8c2b8;font-size:11px;text-align:center;margin-top:14px}
        /* 代码与行号 */
        table.code{border-collapse:collapse;width:100%;font-family:ui-monospace,'SF Mono',Menlo,monospace;
                   font-size:12px;line-height:1.55}
        table.code td{padding:0 8px;white-space:pre-wrap;word-break:break-all}
        table.code td.ln{width:1%;min-width:44px;text-align:right;color:#c4beb2;
                         border-right:1px solid #eee9e0;user-select:none;background:#fbfaf8}
        table.code tr:hover td.cl{background:#fdf8ee}
        /* 语法高亮 */
        .k{color:#c05f2a;font-weight:600}.s{color:#4c8f4c}.n{color:#3d6fb8}
        .c{color:#9a938b;font-style:italic}.t{color:#8a5fbf}.f{color:#2b7a8c}
        .lv-err{color:#c0392b;font-weight:700}.lv-warn{color:#c7742b;font-weight:600}
        .lv-info{color:#4c8f4c}.lv-debug{color:#98928a}.ts{color:#7a92b8}
        /* Markdown */
        .md h1,.md h2,.md h3,.md h4{margin:1.1em 0 .45em;line-height:1.3}
        .md h1{font-size:24px;border-bottom:1px solid #eee9e0;padding-bottom:.3em}
        .md h2{font-size:20px}.md h3{font-size:16px}.md h4{font-size:14px}
        .md p{line-height:1.75;margin:.6em 0}
        .md ul,.md ol{line-height:1.75;padding-left:1.6em}
        .md blockquote{margin:.8em 0;padding:.2em 1em;border-left:3px solid #e8a33d;
                       background:#fdfaf3;border-radius:0 8px 8px 0;color:#6b665e}
        .md code{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.9em;
                 background:#f4f1ea;border-radius:4px;padding:2px 5px;color:#b04a2f}
        .md pre{background:#f8f6f1;border:1px solid #eee9e0;border-radius:10px;
                padding:14px 16px;overflow-x:auto}
        .md pre code{background:none;padding:0;color:#3a3833}
        .md table{border-collapse:collapse;margin:.8em 0;font-size:13px}
        .md th,.md td{border:1px solid #e5e1d8;padding:6px 12px}
        .md th{background:#f8f5ee}
        .md tr:nth-child(even) td{background:#fbfaf7}
        .md img{max-width:100%;border-radius:8px;box-shadow:0 2px 12px rgba(0,0,0,.08)}
        .md hr{border:none;border-top:1px solid #e5e1d8;margin:1.4em 0}
        .md a{color:#c07a2a;text-decoration:none;border-bottom:1px dashed #dfc491}
        /* 表格（csv/tsv） */
        table.grid{border-collapse:collapse;font-size:12.5px;width:100%}
        table.grid th,table.grid td{border:1px solid #e7e3da;padding:5px 12px;
                                    text-align:left;white-space:nowrap;max-width:420px;
                                    overflow:hidden;text-overflow:ellipsis}
        table.grid th{background:#f8f5ee;font-weight:600;position:sticky;top:52px}
        table.grid tr:nth-child(even) td{background:#fbfaf7}
        /* 压缩包 */
        .stats{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:18px}
        .stat{background:#faf8f4;border:1px solid #eee9e0;border-radius:10px;
              padding:10px 18px;min-width:110px}
        .stat b{display:block;font-size:17px;color:#3a3833}
        .stat span{font-size:11px;color:#98928a}
        table.tree{border-collapse:collapse;width:100%;font-size:12.5px;
                   font-family:ui-monospace,'SF Mono',Menlo,monospace}
        table.tree td{padding:4px 10px;white-space:nowrap}
        table.tree tr:nth-child(even) td{background:#fbfaf7}
        table.tree .sz{text-align:right;color:#6b665e;width:1%}
        table.tree .ratio{text-align:right;color:#98928a;width:1%}
        .dir{color:#b06a1f;font-weight:600}
        .unsupported{text-align:center;padding:46px 20px;color:#98928a}
        .unsupported .em{font-size:44px}
        </style></head>
        <body>
        <div class="topbar"><span class="badge">\(escape(badge))</span>
        <span class="fname">\(escape(name))</span><span class="meta">\(meta)</span></div>
        <div class="content">\(inner)
        <div class="glance">由 秒览 Glance 渲染 · 在 Finder 按空格即可预览</div></div>
        </body></html>
        """
    }
}
