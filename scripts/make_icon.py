"""Renders the Saints app icon (1024x1024) into the asset catalog."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
out = sys.argv[1] if len(sys.argv) > 1 else "Saints/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
font_path = sys.argv[2] if len(sys.argv) > 2 else "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"

# Diagonal gradient: deep violet -> indigo -> warm magenta.
top, mid, bot = (40, 18, 74), (88, 46, 150), (196, 84, 132)
img = Image.new("RGB", (S, S))
px = img.load()
for y in range(S):
    for x in range(S):
        t = (x * 0.35 + y * 0.65) / S
        if t < 0.55:
            k = t / 0.55
            c = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.55) / 0.45
            c = tuple(int(mid[i] + (bot[i] - mid[i]) * k) for i in range(3))
        px[x, y] = c

# Soft glow behind the halo.
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((262, 150, 762, 420), fill=170)
glow = glow.filter(ImageFilter.GaussianBlur(70))
img.paste(Image.new("RGB", (S, S), (255, 214, 120)), (0, 0), glow)

# Halo ring.
halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(halo)
d.ellipse((292, 200, 732, 360), outline=(255, 222, 140, 255), width=46)
halo_glow = halo.filter(ImageFilter.GaussianBlur(18))
img.paste(halo_glow, (0, 0), halo_glow)
img.paste(halo, (0, 0), halo)

# The "S".
font = ImageFont.truetype(font_path, 600)
text = Image.new("RGBA", (S, S), (0, 0, 0, 0))
td = ImageDraw.Draw(text)
bbox = td.textbbox((0, 0), "S", font=font)
w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
pos = ((S - w) // 2 - bbox[0], 360 + (560 - h) // 2 - bbox[1])
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).text((pos[0], pos[1] + 14), "S", font=font, fill=(20, 6, 40, 140))
shadow = shadow.filter(ImageFilter.GaussianBlur(16))
img.paste(shadow, (0, 0), shadow)
td.text(pos, "S", font=font, fill=(255, 255, 255, 255))
img.paste(text, (0, 0), text)

img.save(out, "PNG")
print("wrote", out)
