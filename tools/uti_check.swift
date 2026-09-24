import UniformTypeIdentifiers

// 校验 QLSupportedPreviewContentTypes 候选 UTI 在本系统是否真实存在
let list = [
    "net.daringfireball.markdown",
    "public.zip-archive",
    "org.gnu.gnu-zip-tar-archive",
    "org.gnu.gnu-zip-archive",
    "public.tar-archive",
    "public.json",
    "public.xml",
    "public.comma-separated-values-text",
    "public.tab-separated-values-text",
    "public.sql",
    "org.yaml",
    "public.shell-script",
    "public.swift-source",
    "public.python-script",
    "com.netscape.javascript-source",
    "public.c-source",
    "public.c-header",
    "public.c-plus-plus-source",
    "public.objective-c-source",
    "com.sun.java-source",
    "public.ruby-script",
    "public.php-script",
    "public.perl-script",
    "public.lua-script",
    "public.assembly-source",
    "com.microsoft.excel.xls",
    "org.openxmlformats.spreadsheetml.sheet",
    "com.apple.property-list",
    "public.css",
]

for id in list {
    if let t = UTType(id) {
        print("✅ \(id)  ext=\(t.preferredFilenameExtension ?? "-")")
    } else {
        print("❌ \(id)  不存在")
    }
}

print("---- 常量核对 ----")
print("UTType.yaml =", UTType.yaml.identifier)
print("UTType.json =", UTType.json.identifier)
print("UTType.svg  =", UTType.svg.identifier)
