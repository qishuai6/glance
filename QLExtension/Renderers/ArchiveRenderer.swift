import Foundation
import Compression

/// 压缩包预览：zip（中央目录解析）、tar、tar.gz（流式解析，不落盘）。
enum ArchiveRenderer {

    struct Entry {
        let path: String
        let size: Int
        let compSize: Int   // -1 表示无压缩概念（tar）
        let isDir: Bool
    }

    // MARK: - 对外入口

    static func renderZip(url: URL, totalBytes: Int) -> String {
        guard let entries = parseZip(url: url) else {
            return "<div class=\"unsupported\"><div class=\"em\">📦</div>无法解析 zip 目录结构，文件可能已损坏。</div>"
        }
        return page(entries: entries, badge: "ZIP", totalBytes: totalBytes, hasCompression: true)
    }

    static func renderTar(url: URL, totalBytes: Int, gz: Bool) -> String {
        let badge = gz ? "TGZ" : "TAR"
        guard let entries = parseTarStream(url: url, gz: gz) else {
            return "<div class=\"unsupported\"><div class=\"em\">🗜️</div>无法解析 tar 内容，文件可能已损坏。</div>"
        }
        return page(entries: entries, badge: badge, totalBytes: totalBytes, hasCompression: gz)
    }

    private static func page(entries: [Entry], badge: String, totalBytes: Int, hasCompression: Bool) -> String {
        let files = entries.filter { !$0.isDir }
        let dirs = entries.filter { $0.isDir }
        let raw = files.reduce(0) { $0 + $1.size }
        let comp = files.reduce(0) { $0 + max($1.compSize, 0) }
        let ratio = (hasCompression && comp > 0) ? String(format: "%.0f%%", Double(raw) / Double(comp) * 100) : "—"

        var stats = """
        <div class="stats">
          <div class="stat"><b>\(files.count)</b><span>文件</span></div>
          <div class="stat"><b>\(dirs.count)</b><span>目录</span></div>
          <div class="stat"><b>\(HTML.fmtBytes(raw))</b><span>解压后</span></div>
        """
        if hasCompression {
            stats += """
              <div class="stat"><b>\(HTML.fmtBytes(comp))</b><span>压缩后</span></div>
              <div class="stat"><b>\(ratio)</b><span>压缩比</span></div>
            """
        }
        stats += "</div>"

        return stats + tree(entries: files)
    }

    // MARK: - 树形展示

    private static func tree(entries: [Entry]) -> String {
        final class Node {
            var name: String
            var isDir = false
            var size = 0
            var comp = -1
            var children: [String: Node] = [:]
            init(_ name: String) { self.name = name }
        }

        let root = Node("")
        for e in entries.prefix(20000) {
            let parts = e.path.split(separator: "/").map(String.init)
            var node = root
            for (idx, p) in parts.enumerated() {
                let last = idx == parts.count - 1
                node = node.children[p] ?? {
                    let n = Node(p)
                    node.children[p] = n
                    return n
                }()
                if last {
                    node.isDir = e.isDir
                    node.size = e.size
                    node.comp = e.compSize
                }
            }
        }
        _ = root.children.values

        var rowCount = 0
        var truncated = false
        var html = "<table class=\"tree\">"

        func walk(_ node: Node, depth: Int) {
            guard rowCount < 1500 else { truncated = true; return }
            let sorted = node.children.values.sorted {
                if ($0.isDir || !$0.children.isEmpty) != ($1.isDir || !$1.children.isEmpty) {
                    return ($0.isDir || !$0.children.isEmpty)
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            for child in sorted {
                guard rowCount < 1500 else { truncated = true; return }
                let pad = "<span style=\"display:inline-block;width:\(depth * 18)px\"></span>"
                let isDirLike = !child.children.isEmpty || child.isDir
                let icon = isDirLike ? "📁" : "📄"
                let nameHTML = isDirLike ? "<span class=\"dir\">\(HTML.escape(child.name))</span>"
                                         : HTML.escape(child.name)
                let sizeHTML = isDirLike && child.size == 0 ? "—" : HTML.fmtBytes(child.size)
                let compHTML: String
                if child.comp >= 0 {
                    let r = child.size > 0 ? String(format: "%.0f%%", Double(child.comp) / Double(child.size) * 100) : "—"
                    compHTML = "\(HTML.fmtBytes(child.comp)) · \(r)"
                } else {
                    compHTML = ""
                }
                html += "<tr><td>\(pad)\(icon) \(nameHTML)</td><td class=\"sz\">\(sizeHTML)</td>\(compHTML.isEmpty ? "" : "<td class=\"ratio\">\(compHTML)</td>")</tr>"
                rowCount += 1
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        html += "</table>"
        if truncated {
            html = "<div class=\"hint\">条目较多，仅显示前 1500 项。</div>" + html
        }
        return html
    }

    // MARK: - ZIP 中央目录解析

    private static func parseZip(url: URL) -> [Entry]? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let size = (try? fh.seekToEnd()), size >= 22 else { return nil }

        let tailMax = min(65_557, Int(size))
        try? fh.seek(toOffset: UInt64(size - UInt64(tailMax)))
        guard let tail = try? fh.read(upToCount: tailMax), tail.count >= 22 else { return nil }

        // 从尾部向前找 EOCD PK\x05\x06
        var eocdOff = -1
        let scan = tail.count - 22
        var i = scan
        while i >= 0 {
            if tail[i] == 0x50, tail[i + 1] == 0x4b, tail[i + 2] == 0x05, tail[i + 3] == 0x06 {
                eocdOff = i
                break
            }
            i -= 1
        }
        guard eocdOff >= 0 else { return nil }

        func u32(_ d: Data, _ off: Int) -> Int {
            Int(d[off]) | Int(d[off + 1]) << 8 | Int(d[off + 2]) << 16 | Int(d[off + 3]) << 24
        }
        func u16(_ d: Data, _ off: Int) -> Int {
            Int(d[off]) | Int(d[off + 1]) << 8
        }

        var cdSize = u32(tail, eocdOff + 12)
        var cdOffset = u32(tail, eocdOff + 16)
        var entryCount = u16(tail, eocdOff + 10)

        // zip64：EOCD 前面找 locator PK\x06\x07
        if eocdOff >= 20,
           tail[eocdOff - 20] == 0x50, tail[eocdOff - 19] == 0x4b,
           tail[eocdOff - 18] == 0x06, tail[eocdOff - 17] == 0x07 {
            let z64Off = u32(tail, eocdOff - 20 + 8)
            if z64Off > 0, z64Off < Int(size) {
                try? fh.seek(toOffset: UInt64(z64Off))
                if let z = try? fh.read(upToCount: 56), z.count >= 56,
                   z[0] == 0x50, z[1] == 0x4b, z[2] == 0x06, z[3] == 0x06 {
                    cdSize = Int(qword(z, 40))
                    cdOffset = Int(qword(z, 48))
                    entryCount = min(Int(qword(z, 32)), 50_000)
                }
            }
        }
        guard cdOffset > 0, cdOffset < Int(size), cdSize > 0 else { return nil }

        try? fh.seek(toOffset: UInt64(cdOffset))
        guard let cd = try? fh.read(upToCount: min(cdSize, 64_000_000)) else { return nil }

        var entries: [Entry] = []
        var pos = 0
        while pos + 46 <= cd.count, entries.count < entryCount {
            guard cd[pos] == 0x50, cd[pos + 1] == 0x4b, cd[pos + 2] == 0x01, cd[pos + 3] == 0x02 else { break }
            let flags = u16(cd, pos + 8)
            var compSize = u32(cd, pos + 20)
            var uncompSize = u32(cd, pos + 24)
            let nameLen = u16(cd, pos + 28)
            let extraLen = u16(cd, pos + 30)
            let commentLen = u16(cd, pos + 32)
            guard pos + 46 + nameLen <= cd.count else { break }
            let nameData = cd.subdata(in: (pos + 46)..<(pos + 46 + nameLen))

            // zip64 extra field (0x0001)
            var epos = pos + 46 + nameLen
            let eend = epos + extraLen
            if uncompSize == 0xFFFFFFFF || compSize == 0xFFFFFFFF {
                while epos + 4 <= eend, epos + 4 <= cd.count {
                    let id = u16(cd, epos)
                    let sz = u16(cd, epos + 2)
                    var fpos = epos + 4
                    if id == 0x0001 {
                        if uncompSize == 0xFFFFFFFF, fpos + 8 <= eend {
                            uncompSize = Int(qword(cd, fpos)); fpos += 8
                        }
                        if compSize == 0xFFFFFFFF, fpos + 8 <= eend {
                            compSize = Int(qword(cd, fpos)); fpos += 8
                        }
                        break
                    }
                    epos += 4 + sz
                }
            }

            let name = decodeName(nameData, utf8Flag: flags & 0x0800 != 0)
            let isDir = name.hasSuffix("/") || (uncompSize == 0 && name.hasSuffix("/"))
            entries.append(Entry(path: name, size: uncompSize, compSize: compSize, isDir: isDir))
            pos = eend + commentLen
        }
        return entries
    }

    private static func qword(_ d: Data, _ off: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in (0..<8).reversed() {
            v = v << 8 | UInt64(d[off + k])
        }
        return v
    }

    /// 文件名解码：UTF-8 标志位 → UTF-8；否则优先 GB18030（国内压缩包常见），兜底 Latin-1。
    private static func decodeName(_ data: Data, utf8Flag: Bool) -> String {
        if utf8Flag, let s = String(data: data, encoding: .utf8) { return s }
        let gbEnc = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gbEnc)) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? data.base64EncodedString()
    }

    // MARK: - tar / tar.gz 流式解析

    private static func parseTarStream(url: URL, gz: Bool) -> [Entry]? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        let feeder = TarFeeder()
        var entries: [Entry] = []

        func drain() -> Bool {
            for e in feeder.pending {
                entries.append(e)
                feeder.pending.removeAll()
            }
            return entries.count < 5000 && !feeder.limitHit
        }

        if gz {
            guard let gunzip = GzipDecoder() else { return nil }
            while let chunk = try? fh.read(upToCount: 256 * 1024), !chunk.isEmpty {
                guard let out = gunzip.push(chunk) else { return entries.isEmpty ? nil : entries }
                feeder.feed(out)
                if !drain() { break }
            }
        } else {
            while let chunk = try? fh.read(upToCount: 256 * 1024), !chunk.isEmpty {
                feeder.feed(chunk)
                if !drain() { break }
            }
        }
        drain()
        return entries.isEmpty ? nil : entries
    }

    /// 增量 tar 解析：512B 头 + 跳过数据块。
    final class TarFeeder {
        var pending: [Entry] = []
        var limitHit = false
        private var buffer = Data()
        private var totalSeen = 0

        func feed(_ data: Data) {
            buffer.append(data)
            while true {
                if buffer.count < 512 { return }
                let header = buffer.subdata(in: 0..<512)
                // 结束块：全零
                if header.allSatisfy({ $0 == 0 }) {
                    buffer = Data(buffer.dropFirst(min(512, buffer.count)))
                    limitHit = true
                    return
                }
                guard let name = tarName(header), let size = tarSize(header) else { return }

                let typeflag = header[156]
                let isDir = typeflag == 53 // '5'
                let padded = (size + 511) / 512 * 512
                guard buffer.count >= 512 + padded else { return } // 数据未到齐
                // 注意：不能用 removeFirst——它会把 Data 变成非 0 起点的切片，subdata 索引全错
                buffer = Data(buffer.dropFirst(512 + padded))
                totalSeen += padded
                if totalSeen > 512 * 1024 * 1024 { limitHit = true; return }
                pending.append(Entry(path: name, size: size, compSize: -1, isDir: isDir))
            }
        }

        private func tarName(_ h: Data) -> String? {
            var name = cstr(h, 0, 100)
            let prefix = cstr(h, 345, 155)
            if !prefix.isEmpty { name = prefix + "/" + name }
            return name.isEmpty ? nil : name
        }

        private func cstr(_ d: Data, _ off: Int, _ len: Int) -> String {
            var end = off
            let maxEnd = min(off + len, d.count)
            while end < maxEnd, d[end] != 0 { end += 1 }
            return String(data: d.subdata(in: off..<end), encoding: .utf8)
                ?? String(data: d.subdata(in: off..<end), encoding: .isoLatin1) ?? ""
        }

        private func tarSize(_ h: Data) -> Int? {
            // GNU base-256
            if h[124] & 0x80 != 0 {
                var v: UInt64 = 0
                for k in 0..<12 { v = v << 8 | UInt64(h[124 + k]) }
                return Int(v & 0x7FFF_FFFF_FFFF_FFFF)
            }
            let s = cstr(h, 124, 12).trimmingCharacters(in: .whitespaces)
            return Int(s, radix: 8)
        }
    }

    /// gzip 流式解码：剥离 gzip 头 + libcompression raw deflate。输出上限 512MB 防炸弹。
    final class GzipDecoder {
        private var stream: compression_stream
        private var streamValid = false
        private var headerDone = false
        private var headerBuf = Data()
        private var produced = 0
        let maxOutput = 512 * 1024 * 1024

        init?() {
            // bitPattern 0 会得到 nil；compression_stream_init 只设置 state，不会碰这两个指针
            let dummyOut = UnsafeMutablePointer<UInt8>(bitPattern: 1)!
            let dummyIn = UnsafePointer<UInt8>(bitPattern: 1)!
            stream = compression_stream(dst_ptr: dummyOut, dst_size: 0,
                                        src_ptr: dummyIn, src_size: 0, state: nil)
            let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard status == COMPRESSION_STATUS_OK else { return nil }
            streamValid = true
        }

        deinit {
            if streamValid { compression_stream_destroy(&stream) }
        }

        /// 输入压缩数据，返回解压输出；返回 nil 表示 gzip 损坏。
        func push(_ input: Data) -> Data? {
            var body = input
            if !headerDone {
                headerBuf.append(input)
                guard let consumed = parseHeader(headerBuf) else { return Data() } // 头未完整
                headerDone = true
                body = headerBuf[consumed...]
                headerBuf = Data()
            }

            var out = Data()
            var failed = false
            let dstChunk = 256 * 1024
            let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: dstChunk)
            defer { dstBuf.deallocate() }

            body.withUnsafeBytes { raw in
                let srcBuf = raw.bindMemory(to: UInt8.self)
                if let base = srcBuf.baseAddress {
                    stream.src_ptr = base
                } else {
                    stream.src_size = 0 // 空 body：不消费输入
                }
                stream.src_size = body.count
                while true {
                    stream.dst_ptr = dstBuf
                    stream.dst_size = dstChunk
                    let status = compression_stream_process(&stream, 0)
                    let got = dstChunk - stream.dst_size
                    if got > 0 {
                        produced += got
                        out.append(dstBuf, count: got)
                    }
                    if produced > maxOutput { break }
                    if status == COMPRESSION_STATUS_END { break }
                    if status == COMPRESSION_STATUS_ERROR {
                        out = Data(); failed = true; break
                    }
                    if stream.src_size == 0 { break } // 本块输入消费完
                }
            }
            if failed { return nil }
            return out
        }

        /// 解析 gzip 头，返回头部长度；未完整返回 nil。
        private func parseHeader(_ d: Data) -> Int? {
            guard d.count >= 10 else { return nil }
            guard d[0] == 0x1f, d[1] == 0x8b, d[2] == 8 else { return nil }
            let flg = d[3]
            var pos = 10
            if flg & 0x04 != 0 { // FEXTRA
                guard d.count >= pos + 2 else { return nil }
                let xlen = Int(d[pos]) | Int(d[pos + 1]) << 8
                guard d.count >= pos + 2 + xlen else { return nil }
                pos += 2 + xlen
            }
            if flg & 0x08 != 0 { // FNAME
                guard let z = zeroAt(d, pos) else { return nil }
                pos = z + 1
            }
            if flg & 0x10 != 0 { // FCOMMENT
                guard let z = zeroAt(d, pos) else { return nil }
                pos = z + 1
            }
            if flg & 0x02 != 0 { pos += 2 } // FHCRC
            return pos
        }

        private func zeroAt(_ d: Data, _ from: Int) -> Int? {
            var i = from
            while i < d.count {
                if d[i] == 0 { return i }
                i += 1
            }
            return nil
        }
    }
}
