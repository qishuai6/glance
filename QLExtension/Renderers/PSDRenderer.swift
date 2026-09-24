import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// PSD 预览：解析头部信息 + 提取合成图（flattened composite），RLE/raw 解压 → RGBA → PNG。
enum PSDRenderer {

    static let modeNames: [Int: String] = [
        0: "位图", 1: "灰度", 2: "索引颜色", 3: "RGB", 4: "CMYK",
        7: "多通道", 8: "双色调", 9: "Lab",
    ]

    static func render(url: URL, totalBytes: Int) -> String {
        guard let data = try? Data(contentsOf: url) else { return infoCard(error: "无法读取文件") }
        guard data.count >= 26, data.starts(with: Data("8BPS".utf8)) else {
            return infoCard(error: "不是有效的 PSD 文件")
        }

        let channels = u16be(data, 12)
        let height = u32be(data, 14)
        let width = u32be(data, 18)
        let depth = u16be(data, 22)
        let mode = u16be(data, 24)

        var stats = """
        <div class="stats">
          <div class="stat"><b>\(width)×\(height)</b><span>像素</span></div>
          <div class="stat"><b>\(HTML.fmtBytes(totalBytes))</b><span>文件大小</span></div>
          <div class="stat"><b>\(modeNames[mode] ?? "模式\(mode)")</b><span>颜色模式</span></div>
          <div class="stat"><b>\(channels)</b><span>通道</span></div>
        </div>
        """

        // 提取合成图（仅支持 8 位 RGB/灰度）
        if depth == 8, width > 0, height > 0, width * height <= 40_000_000,
           mode == 3 || mode == 1, channels >= 1, channels <= 5,
           let png = compositePNG(data: data, width: width, height: height, channels: channels, gray: mode == 1) {
            stats += """
            <div class="imgview"><img src="data:image/png;base64,\(png)" alt="psd"></div>
            """
        } else if depth != 8 || (mode != 3 && mode != 1) {
            stats += """
            <div class="hint">此 PSD 为 \(modeNames[mode] ?? "模式\(mode)")/\(depth) 位，暂只支持 8 位 RGB/灰度的图像预览，上方信息仍可查看。</div>
            """
        } else {
            stats += """
            <div class="hint">文件可能未包含合成预览图（保存时未开启「最大兼容」），或尺寸超出限制。</div>
            """
        }
        return stats
    }

    private static func infoCard(error: String) -> String {
        return "<div class=\"unsupported\"><div class=\"em\">🎨</div><p>\(HTML.escape(error))</p></div>"
    }

    // MARK: - 合成图提取

    private static func compositePNG(data: Data, width: Int, height: Int, channels: Int, gray: Bool) -> String? {
        var off = 26
        off += 4 + u32be(data, off)      // 颜色模式数据段
        guard off + 4 <= data.count else { return nil }
        off += 4 + u32be(data, off)      // 图像资源段
        guard off + 4 <= data.count else { return nil }
        off += 4 + u32be(data, off)      // 图层与蒙版段
        guard off + 2 <= data.count else { return nil }

        let compression = u16be(data, off)
        off += 2
        let rowBytes = width

        var planes: [[UInt8]] = []
        if compression == 0 {
            // raw：各通道平面连续存放
            let planeSize = rowBytes * height
            for c in 0..<channels {
                let s = off + c * planeSize
                guard s + planeSize <= data.count else { return nil }
                planes.append(Array(data[s..<(s + planeSize)]))
            }
        } else if compression == 1 {
            // RLE：先 [channels×height] 个行的字节数表，再是压缩数据
            let tableEnd = off + channels * height * 2
            guard tableEnd <= data.count else { return nil }
            var p = tableEnd
            for c in 0..<channels {
                var plane = [UInt8]()
                plane.reserveCapacity(rowBytes * height)
                for row in 0..<height {
                    let cnt = u16be(data, off + (c * height + row) * 2)
                    guard p + cnt <= data.count else { return nil }
                    plane += unpackBits(data, p, p + cnt, expected: rowBytes)
                    p += cnt
                }
                guard plane.count == rowBytes * height else { return nil }
                planes.append(plane)
            }
        } else {
            return nil
        }

        // 拼 RGBA（PSD 合成图通道顺序：灰度 [A]；RGB [R G B (A)]）
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        rgba.withUnsafeMutableBufferPointer { buf in
            for i in 0..<(width * height) {
                let r: UInt8, g: UInt8, b: UInt8, a: UInt8
                if gray {
                    let v = planes[0][i]
                    r = v; g = v; b = v
                    a = planes.count > 1 ? planes[1][i] : 255
                } else {
                    guard planes.count >= 3 else { return }
                    r = planes[0][i]; g = planes[1][i]; b = planes[2][i]
                    a = planes.count > 3 ? planes[3][i] : 255
                }
                buf[i * 4] = r; buf[i * 4 + 1] = g; buf[i * 4 + 2] = b; buf[i * 4 + 3] = a
            }
        }

        let pixelData = Data(rgba)
        guard let provider = CGDataProvider(data: pixelData as CFData),
              let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out.base64EncodedString()
    }

    // MARK: - PackBits（RLE）解压

    private static func unpackBits(_ d: Data, _ start: Int, _ end: Int, expected: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(expected)
        var i = start
        while i < end, out.count < expected {
            let n = Int8(bitPattern: d[i])
            i += 1
            if n >= 0 {
                let cnt = Int(n) + 1
                guard i + cnt <= end else { break }
                out.append(contentsOf: d[i..<(i + cnt)])
                i += cnt
            } else if n != -128 {
                guard i < end else { break }
                let b = d[i]
                i += 1
                out.append(contentsOf: [UInt8](repeating: b, count: 1 - Int(n)))
            }
        }
        return out
    }

    private static func u16be(_ d: Data, _ o: Int) -> Int {
        Int(d[o]) << 8 | Int(d[o + 1])
    }

    private static func u32be(_ d: Data, _ o: Int) -> Int {
        Int(d[o]) << 24 | Int(d[o + 1]) << 16 | Int(d[o + 2]) << 8 | Int(d[o + 3])
    }
}
