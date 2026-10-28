# 秒览 Glance

> 让 macOS 空格键预览一切：md、zip、sql、json、csv、yaml、toml、log、30+ 编程语言……

macOS 的空格预览（Quick Look）对很多开发者文件无能为力——zip 只显示图标卡、sql/json/csv 只有干巴巴的纯文本。**秒览**把这一切变成排版精美、带语法高亮和统计信息的富预览。

## 它是怎么工作的

macOS 27 有条硬规则：**系统自带内容预览器的文件类型，第三方 Quick Look 扩展永远抢不过**（连 WPS 的 docx 预览扩展都被压着）。所以秒览采取双引擎：

| 引擎 | 接管范围 | 需要权限 |
|---|---|---|
| Quick Look 预览扩展 | 系统完全不管的类型（如 Markdown 富渲染） | 无，安装即用 |
| 空格键接管器（CGEventTap + AX） | 其余全部类型（zip/sql/json/csv/log…） | 辅助功能权限 |

空格键接管器只拦截「Finder 前台 + 选中了秒览支持的文件」时的空格键，其余按键原样放行，不影响任何其他软件。

> **边界：秒览只接管空格键预览，不改变任何文件的默认打开方式。** 双击文件的行为与你装秒览之前完全一致。

## 功能

- **Markdown**：标题/列表（含任务列表）/表格/代码块（带语言高亮）/引用/图片（本地图片转内嵌）
- **压缩包**：zip（含中文文件名 GBK 兜底、zip64）、tar、tar.gz/tgz 流式解析，目录树 + 压缩比统计，不落盘
- **数据**：json 格式化着色、jsonl/ndjson 逐行、csv/tsv 表格化（RFC4180 状态机）
- **配置**：yaml/toml/ini/conf/env 结构高亮、plist（含二进制转可读结构）
- **代码**：sql/swift/python/js/ts/go/rust/java/c/cpp/objc/ruby/php/kotlin/lua/perl/sh/lua/css/xml/汇编/Makefile/Dockerfile 等 30+ 语言语法高亮 + 行号
- **日志**：时间戳/ERROR/WARN/INFO 分级着色
- 大文件智能截断、←→ 在多选文件间切换、空格/Esc 关闭
- 菜单栏常驻、登录自启动、随时开关

## 构建

```bash
brew install xcodegen   # 若未安装
./build.sh              # xcodegen + xcodebuild，产物在 build/DerivedData/Build/Products/Debug/Glance.app
```

## 安装

1. 把 `Glance.app` 拖进「应用程序」
2. 打开一次，点「授权辅助功能」（空格键接管需要；仅用于读取 Finder 选中项）
3. Finder 里选中任意支持的文件，按空格 ✓

## 目录结构

```
Glance/
├── project.yml            # XcodeGen 工程（App + QL 扩展双 target）
├── App/                   # 主 App：设置界面、菜单栏、空格接管、预览面板
│   ├── GlanceApp.swift
│   ├── SpaceTap.swift     # CGEventTap + AX 取 Finder 选中项
│   ├── PreviewPanel.swift # NSPanel + WKWebView 预览面板
│   ├── ContentView.swift
│   └── Assets.xcassets
├── QLExtension/           # Quick Look 预览扩展
│   ├── PreviewProvider.swift
│   └── Renderers/         # 全套渲染器（App 与扩展共用）
│       ├── RendererHub.swift    # 分发中枢
│       ├── MarkdownRenderer.swift
│       ├── ArchiveRenderer.swift # zip/tar/tgz 纯 Swift 解析
│       ├── CodeRenderer.swift   # 语法高亮引擎
│       ├── TableRenderer.swift
│       ├── JSONRenderer.swift
│       └── HTMLShell.swift      # 统一视觉（暖白 + 杏黄 + 轻阴影）
├── fixtures/              # 各格式测试样例
└── tools/                 # 构建辅助（图标生成、渲染 CLI、样例生成）
```

## 验证渲染效果（不装 App）

```bash
swiftc -O QLExtension/Renderers/*.swift tools/main.swift -o tools/render_cli
./tools/render_cli fixtures/demo.sql /tmp/out.html && open /tmp/out.html
```

## 更新日志

- **2026-10-28** 修复设置窗口无法打开：改用 SwiftUI Settings 场景（主菜单新增「设置… ⌘,」，可反复开关），替换原 WindowGroup + makeKeyAndOrderFront 在窗口关闭后失效的方案。
- **2026-10-28** 品牌视觉升级：App 图标与设置窗口 logo 换预览卡片图（蓝紫渐变 + 日落山景卡片 + 星光），图标生成脚本 make_icon.py 兼容成品 squircle 源图。
- **2026-09-30** 品牌视觉定型：App 图标与设置窗口 logo 换空格键键帽图，状态栏图标改单色键帽剪影（模板自适配菜单栏深浅色）。
- **2026-09-24** 格式大扩容：新增 svg / psd 空格预览（PSD 合成图解析）、ai / eps / 字体 / ipynb / gz / apk-ipa-jar 与 40+ 编程语言；方向键导航浏览整个文件夹 + Finder 选中项同步跟随；空格接管遍历访达全部窗口取选中项的稳定性修复、辅助功能授权自动引导。
- **2026-09-24** v1.0 发布：Quick Look 扩展 + 空格键接管双引擎，14+ 格式富预览（Markdown 渲染 / 压缩包目录树 / 数据表格化 / 配置高亮 / 30+ 代码语言 / 日志分级着色）。

---

© 2026 [qishuai.vip](https://qishuai.vip) · Design: 暖白拟物 × 杏黄点缀
