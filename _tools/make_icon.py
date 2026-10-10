# -*- coding: utf-8 -*-
"""生成 App 图标:橙红渐变底 + 白色猫爪(七猫风格)。"""
import os
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = r"D:\Pro\QiMao\QimaoReader-iOS\QimaoReader\Assets.xcassets\AppIcon.appiconset"
os.makedirs(OUT_DIR, exist_ok=True)

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# ---- 渐变底(#FF7038 -> #FF4D18 对角) ----
grad = Image.new("RGB", (S, S))
gd = ImageDraw.Draw(grad)
c1 = (255, 112, 56)
c2 = (255, 77, 24)
for y in range(S):
    t = y / (S - 1)
    # 对角混合
    r = int(c1[0] + (c2[0] - c1[0]) * t)
    g = int(c1[1] + (c2[1] - c1[1]) * t)
    b = int(c1[2] + (c2[2] - c1[2]) * t)
    gd.line([(0, y), (S, y)], fill=(r, g, b))

# 圆角遮罩(iOS 风格 superellipse 近似 → 圆角 ~22.5%)
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
radius = int(S * 0.225)
md.rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)

img.paste(grad, (0, 0), mask)

# ---- 白色猫爪 ----
paw = Image.new("RGBA", (S, S), (0, 0, 0, 0))
pd = ImageDraw.Draw(paw)
W = (255, 255, 255, 242)

def ellipse(cx, cy, rx, ry, rot=0):
    if rot:
        box = Image.new("RGBA", (rx * 2 + 4, ry * 2 + 4), (0, 0, 0, 0))
        bd = ImageDraw.Draw(box)
        bd.ellipse([2, 2, rx * 2 + 1, ry * 2 + 1], fill=W)
        box = box.rotate(rot, expand=True)
        paw.alpha_composite(box, (int(cx - box.width / 2), int(cy - box.height / 2)))
    else:
        pd.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=W)

# 掌心(大椭圆,微微倾斜)
ellipse(512, 635, 208, 172, rot=-6)
# 四个趾头(弧形排布)
ellipse(305, 415, 92, 112, rot=-26)
ellipse(432, 322, 92, 116, rot=-10)
ellipse(576, 318, 92, 116, rot=8)
ellipse(706, 400, 90, 110, rot=24)

paw = paw.filter(ImageFilter.GaussianBlur(0.6))
img.alpha_composite(paw)

img.save(os.path.join(OUT_DIR, "icon1024.png"))

# ---- Contents.json ----
contents = '''{
  "images" : [
    {
      "filename" : "icon1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'''
with open(os.path.join(OUT_DIR, "Contents.json"), "w", encoding="utf-8") as f:
    f.write(contents)

# 预览一张小图便于检查
img.resize((256, 256)).save(r"D:\Pro\QiMao\QimaoReader-iOS\_icon_preview.png")
print("icon done:", os.path.join(OUT_DIR, "icon1024.png"))
