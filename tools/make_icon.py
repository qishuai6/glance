#!/usr/bin/env python3
"""秒览 Glance 图标：预览卡片图（蓝紫渐变 + 日落山景卡片 + 星光）
源图 tools/icon_source.png 支持两种形态：
- 全出血方图 → 裁成官方 squircle（1024 画布、824×824 图形区、圆角 185）
- 已带透明边的成品 squircle（四角 alpha=0）→ 直接缩放使用，不再二次裁剪
"""
from PIL import Image, ImageDraw
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "icon_source.png")

S = 1024      # icns 画布
SHAPE = 824   # macOS 官方图形区（Big Sur+ 规范）
RADIUS = 185  # 官方 squircle 圆角半径

src = Image.open(SRC).convert("RGBA")

corners_transparent = all(
    src.getpixel(p)[3] == 0
    for p in [(2, 2), (src.width - 3, 2), (2, src.height - 3), (src.width - 3, src.height - 3)]
)

if corners_transparent:
    # 成品 squircle：保持原设计（含星光等外溢装饰）直接归一到 1024
    img = src.resize((S, S), Image.LANCZOS)
else:
    art = src.resize((SHAPE, SHAPE), Image.LANCZOS)

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (SHAPE, SHAPE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SHAPE - 1, SHAPE - 1], radius=RADIUS, fill=255)
    off = (S - SHAPE) // 2
    img.paste(art, (off, off), mask)

# 输出 1：Assets.xcassets（保持仓库一致；实际打包走 App/AppIcon.icns）
iconset_dir = os.path.join(HERE, "..", "App", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(iconset_dir, exist_ok=True)
img.save(os.path.join(iconset_dir, "icon_1024.png"))

# 输出 2：全尺寸 iconset → iconutil → App/AppIcon.icns
iconset = "/tmp/AppIcon.iconset"
os.makedirs(iconset, exist_ok=True)
for f in os.listdir(iconset):
    os.remove(os.path.join(iconset, f))
for sz in (16, 32, 64, 128, 256, 512):
    img.resize((sz, sz), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}.png")
    img.resize((sz * 2, sz * 2), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}@2x.png")
img.resize((1024, 1024), Image.LANCZOS).save(f"{iconset}/icon_512x512@2x.png")

icns = os.path.join(HERE, "..", "App", "AppIcon.icns")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
print("✅ AppIcon.icns 已生成")

# 预览图（人眼验收用，不进仓库产物）
img.resize((512, 512), Image.LANCZOS).save("/tmp/glance_icon_preview.png")
print("✅ 预览: /tmp/glance_icon_preview.png")
