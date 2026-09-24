import Foundation

/// 字体预览（ttf/otf/ttc/woff/woff2）：@font-face 内嵌渲染字样页。
enum FontRenderer {

    static func render(url: URL, totalBytes: Int) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return "<div class=\"unsupported\"><div class=\"em\">🔤</div>无法读取文件</div>"
        }
        if data.count > 15_000_000 {
            return "<div class=\"hint\">字体文件超过 15MB，过大不渲染字样。</div>"
        }
        let ext = url.pathExtension.lowercased()
        let (mime, format): (String, String)
        switch ext {
        case "woff": (mime, format) = ("font/woff", "woff")
        case "woff2": (mime, format) = ("font/woff2", "woff2")
        case "otf": (mime, format) = ("font/otf", "opentype")
        case "ttc": (mime, format) = ("font/collection", "collection")
        default: (mime, format) = ("font/ttf", "truetype")
        }
        let b64 = data.base64EncodedString()
        let isTTC = ext == "ttc"

        var body = """
        <style>
        @font-face{font-family:'Spec';src:url(data:\(mime);base64,\(b64)) format('\(format)')}
        .spec{font-family:'Spec',-apple-system,'PingFang SC'}
        </style>
        <div class="stats">
          <div class="stat"><b>\(HTML.fmtBytes(totalBytes))</b><span>文件大小</span></div>
          <div class="stat"><b>\(ext.uppercased())</b><span>格式</span></div>
        </div>
        """
        if isTTC {
            body += """
            <div class="hint">字体合集（ttc）浏览器只能加载第一个字库；若下方字样与系统默认一致，说明该字库未内嵌成功。</div>
            """
        }
        body += """
        <div class="card" style="margin-bottom:14px">
          <div class="spec" style="font-size:44px;line-height:1.25">永 A 1 中 g 岁</div>
          <div class="spec" style="font-size:15px;color:#6b665e;margin-top:10px">做有复利的事，普通人别想一夜暴富。</div>
        </div>
        <div class="card" style="margin-bottom:14px">
          <div class="spec" style="font-size:22px;letter-spacing:1px">ABCDEFGHIJKLMN</div>
          <div class="spec" style="font-size:22px;letter-spacing:1px">OPQRSTUVWXYZ</div>
          <div class="spec" style="font-size:22px;margin-top:6px">abcdefghijklmn 0123456789</div>
          <div class="spec" style="font-size:22px;margin-top:6px">，。！？；：""（）——…</div>
        </div>
        <div class="card">
          <div class="spec" style="font-size:13px;line-height:1.9">厚德载物，自强不息。Gratitude turns what we have into enough. 38.5% ¥€$ ←↑→↓</div>
        </div>
        """
        return body
    }
}
