"""生成 App 图标（1024×1024 PNG）。纯 Pillow，无外部素材。"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # 超采样后缩放，边缘更干净
OUT_SIZE = 1024
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Sources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

BG_TOP = (19, 74, 62)
BG_BOTTOM = (5, 24, 21)
GOLD = (240, 195, 104)

img = Image.new("RGB", (S, S), BG_BOTTOM)
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / (S - 1)
    d.line([(0, y), (S, y)], fill=tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)))

# 五线谱
staff_top = int(S * 0.505)
gap = int(S * 0.055)
line_color = tuple(min(255, int(BG_TOP[i] * 1.0 + 34)) for i in range(3))
for i in range(5):
    y = staff_top + i * gap
    d.line([(int(S * 0.09), y), (int(S * 0.91), y)], fill=line_color, width=int(S * 0.0055))

# 符头
head_w, head_h = int(S * 0.225), int(S * 0.165)
head = Image.new("RGBA", (head_w, head_h), (0, 0, 0, 0))
hd = ImageDraw.Draw(head)
hd.ellipse([0, 0, head_w - 1, head_h - 1], fill=GOLD + (255,))
head = head.rotate(-20, expand=True, resample=Image.BICUBIC)
head_cx, head_cy = int(S * 0.355), int(S * 0.665)
img.paste(head, (head_cx - head.width // 2, head_cy - head.height // 2), head)
d = ImageDraw.Draw(img)

# 符干
stem_x = int(S * 0.443)
stem_w = int(S * 0.026)
stem_top = int(S * 0.255)
stem_bottom = int(S * 0.665)
d.rounded_rectangle([stem_x, stem_top, stem_x + stem_w, stem_bottom],
                    radius=stem_w // 2, fill=GOLD)

# 符尾
flag = [stem_x + stem_w - int(S * 0.008), stem_top - int(S * 0.005),
        stem_x + int(S * 0.155), stem_top + int(S * 0.148)]
d.arc(flag, start=205, end=15, fill=GOLD, width=int(S * 0.019))

# 底部细线，压住构图
d.line([(int(S * 0.09), int(S * 0.885)), (int(S * 0.91), int(S * 0.885))],
       fill=(38, 104, 88), width=int(S * 0.004))

img = img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, "PNG")
print("saved", OUT)
