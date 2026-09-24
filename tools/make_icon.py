#!/usr/bin/env python3
"""秒览 Glance 图标生成：暖白圆角底板 + 白色空格键帽 + 杏黄侧边（Rams 风格）"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# ---------- 底板：暖白垂直渐变 + 大圆角 ----------
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

# ---------- 键帽阴影 ----------
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle([200, 420, 824, 660], radius=72, fill=(60, 50, 30, 60))
shadow = shadow.filter(ImageFilter.GaussianBlur(22))
img.alpha_composite(shadow)

# ---------- 键帽：杏黄侧边 + 白色帽面 ----------
d.rounded_rectangle([192, 400, 824, 648], radius=64, fill=(233, 166, 66, 255))   # 侧边
d.rounded_rectangle([192, 384, 824, 620], radius=64, fill=(255, 255, 255, 255))  # 帽面
# 帽面高光：上缘淡白渐变
hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
hd.rounded_rectangle([204, 396, 812, 470], radius=44, fill=(255, 255, 255, 120))
img.alpha_composite(hl)

# ---------- 键帽文字：空格 ----------
font = None
for path, idx in [("/System/Library/Fonts/Hiragino Sans GB.ttc", 1),
                  ("/System/Library/Fonts/Hiragino Sans GB.ttc", 0),
                  ("/System/Library/Fonts/PingFang.ttc", 0)]:
    if os.path.exists(path):
        try:
            font = ImageFont.truetype(path, 150, index=idx)
            break
        except Exception:
            continue
text = "空格"
bbox = d.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
tx, ty = (S - tw) / 2 - bbox[0], 384 + (236 - th) / 2 - bbox[1]
d.text((tx, ty), text, font=font, fill=(60, 55, 48, 255))

# ---------- 输出 ----------
out_root = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets")
iconset = os.path.join(out_root, "AppIcon.appiconset")
os.makedirs(iconset, exist_ok=True)
img.save(os.path.join(iconset, "icon_1024.png"))

with open(os.path.join(out_root, "Contents.json"), "w") as f:
    f.write('{\n  "info": { "author": "xcode", "version": 1 }\n}\n')
with open(os.path.join(iconset, "Contents.json"), "w") as f:
    f.write('''{
  "images" : [
    { "filename" : "icon_1024.png", "idiom" : "universal", "platform" : "macos", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
''')
print("✅ 图标已生成", iconset)
