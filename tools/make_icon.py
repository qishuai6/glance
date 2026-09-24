#!/usr/bin/env python3
"""秒览 Glance 图标：暖白底板 + 一根短横线（极简空格符号）"""
from PIL import Image, ImageDraw
import os

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# 底板：暖白垂直渐变 + 大圆角
plate = Image.new("RGBA", (S, S), (0, 0, 0, 0))
pd = ImageDraw.Draw(plate)
top, bottom = (253, 252, 250, 255), (238, 234, 227, 255)
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    t = y / S
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
    gd.line([(0, y), (S, y)], fill=c)
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([56, 56, S - 56, S - 56], radius=232, fill=255)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)

# 唯一的元素：一根短横线（圆角端点，深灰棕）
line_w, line_h = 260, 34
x0 = (S - line_w) / 2
y0 = (S - line_h) / 2
d.rounded_rectangle([x0, y0, x0 + line_w, y0 + line_h], radius=line_h / 2, fill=(58, 54, 48, 255))

# 输出：1024 png + 全尺寸 iconset
out_root = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets")
iconset_dir = os.path.join(out_root, "AppIcon.appiconset")
os.makedirs(iconset_dir, exist_ok=True)
img.save(os.path.join(iconset_dir, "icon_1024.png"))

iconset = "/tmp/AppIcon.iconset"
os.makedirs(iconset, exist_ok=True)
for sz in (16, 32, 64, 128, 256, 512):
    img.resize((sz, sz), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}.png")
    img.resize((sz * 2, sz * 2), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}@2x.png")
img.resize((1024, 1024), Image.LANCZOS).save(f"{iconset}/icon_512x512@2x.png")
print("✅ png 就绪")
