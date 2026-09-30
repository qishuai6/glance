#!/usr/bin/env python3
"""秒览 Glance 图标：官方品牌图（蓝底 + 白色空格键键帽）
源图 tools/icon_source.png 是 iOS 全出血方图；macOS 需裁成官方 squircle
（1024 画布、824×824 图形区居中、圆角 185），否则 Dock 里是方角满铺。
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
