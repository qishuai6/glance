import Foundation
import AppKit
import PDFKit

/// Adobe Illustrator（.ai）预览：定位内嵌 PDF 载荷 → PDFKit 渲染首页。
enum AIRenderer {

    static func render(url: URL, totalBytes: Int) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return info("无法读取文件")
        }
        guard data.count > 4 else { return info("文件过小") }

        // 定位 %PDF- 载荷（新版本 AI 是「PostScript 头 + PDF 主体」结构）
        guard let pdfStart = findPDFPayload(data) else {
            return metadataCard(data: data, totalBytes: totalBytes, note: "未找到 PDF 兼容载荷（老版本 PostScript 格式），暂无法渲染图形。")
        }
        let pdfData = data.subdata(in: pdfStart..<data.count)
        guard let doc = PDFDocument(data: pdfData), doc.pageCount > 0 else {
            return metadataCard(data: data, totalBytes: totalBytes, note: "PDF 载荷解析失败，文件可能已损坏。")
        }
        let page = doc.page(at: 0)!
        let bounds = page.bounds(for: .mediaBox)

        var stats = """
        <div class="stats">
          <div class="stat"><b>\(Int(bounds.width))×\(Int(bounds.height))</b><span>画板 pt</span></div>
          <div class="stat"><b>\(doc.pageCount)</b><span>页</span></div>
          <div class="stat"><b>\(HTML.fmtBytes(totalBytes))</b><span>文件大小</span></div>
        </div>
        """
        // 首页渲染（最宽 1800pt，白底）
        let scale = min(1800.0 / max(bounds.width, 1), 2.0)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        if let png = pngBase64(thumb) {
            stats += "<div class=\"imgview\"><img src=\"data:image/png;base64,\(png)\" alt=\"ai\"></div>"
        } else {
            stats += "<div class=\"hint\">首页渲染失败。</div>"
        }
        return stats
    }

    /// 在前 8MB 内找 %PDF- 标记。
    private static func findPDFPayload(_ data: Data) -> Int? {
        let marker = Data("%PDF-".utf8)
        let limit = min(data.count - marker.count, 8_000_000)
        var i = 0
        while i <= limit {
            if data[i] == 0x25 { // %
                var match = true
                for k in 0..<marker.count where data[i + k] != marker[k] { match = false; break }
                if match { return i }
            }
            i += 1
        }
        return nil
    }

    private static func metadataCard(data: Data, totalBytes: Int, note: String) -> String {
        // 提取 PostScript 头部的 %%Title / %%Creator 行做信息展示
        let head = String(data: data.prefix(4096), encoding: .isoLatin1) ?? ""
        var lines: [String] = []
        for line in head.split(separator: "\n") {
            if line.hasPrefix("%%Title") || line.hasPrefix("%%Creator") || line.hasPrefix("%%CreationDate") {
                lines.append(HTML.escape(String(line).trimmingCharacters(in: .whitespaces)))
            }
        }
        let meta = lines.isEmpty ? "" : "<pre style=\"font-size:12px;color:#6b665e\">\(lines.joined(separator: "\n"))</pre>"
        return """
        <div class="stats"><div class="stat"><b>\(HTML.fmtBytes(totalBytes))</b><span>文件大小</span></div></div>
        \(meta)
        <div class="hint">\(HTML.escape(note))</div>
        """
    }

    private static func pngBase64(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }

    private static func info(_ s: String) -> String {
        "<div class=\"unsupported\"><div class=\"em\">✏️</div><p>\(HTML.escape(s))</p></div>"
    }
}
