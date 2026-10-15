"""Renders the SV Browser app icon (1024x1024): plain "SV" lettering on a flat background."""
import sys
from PIL import Image, ImageDraw, ImageFont

S = 1024
out = sys.argv[1] if len(sys.argv) > 1 else "Saints/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
font_path = sys.argv[2] if len(sys.argv) > 2 else "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"

img = Image.new("RGB", (S, S), (18, 18, 20))
draw = ImageDraw.Draw(img)
font = ImageFont.truetype(font_path, 430)
bbox = draw.textbbox((0, 0), "SV", font=font)
w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
draw.text(((S - w) / 2 - bbox[0], (S - h) / 2 - bbox[1]), "SV", font=font, fill=(255, 255, 255))
img.save(out, "PNG")
print("wrote", out)
