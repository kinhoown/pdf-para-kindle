"""Gera o ícone do app (leitor de e-book + documento PDF + seta) em todas as densidades."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

RES = sys.argv[1]
S = 1024  # desenha grande e reduz (antialiasing)
BG = (31, 111, 92)

def font(size):
    for f in ['C:/Windows/Fonts/arialbd.ttf', 'C:/Windows/Fonts/segoeuib.ttf']:
        if os.path.exists(f): return ImageFont.truetype(f, size)
    return ImageFont.load_default()

def foreground(scale=1.0):
    """Desenho transparente centrado; scale<1 deixa margem para o ícone adaptativo."""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def r(v): return int(S / 2 + (v - S / 2) * scale)
    def box(x0, y0, x1, y1): return [r(x0), r(y0), r(x1), r(y1)]
    k = scale
    # leitor de e-book
    d.rounded_rectangle(box(380, 170, 830, 830), radius=int(60 * k), fill=(30, 30, 32))
    d.rounded_rectangle(box(420, 215, 790, 740), radius=int(14 * k), fill=(236, 232, 220))
    for i, w in enumerate([300, 330, 280, 330, 310, 200, 320, 290]):
        y = 260 + i * 56
        d.rounded_rectangle(box(450, y, 450 + w, y + 18), radius=int(9 * k), fill=(150, 145, 135))
    d.rounded_rectangle(box(560, 765, 650, 790), radius=int(12 * k), fill=(90, 90, 95))
    # documento PDF (canto dobrado)
    x0, y0, x1, y1, fold = 150, 420, 470, 850, 90
    d.polygon([(r(x0), r(y0)), (r(x1 - fold), r(y0)), (r(x1), r(y0 + fold)), (r(x1), r(y1)), (r(x0), r(y1))], fill=(255, 255, 255))
    d.polygon([(r(x1 - fold), r(y0)), (r(x1 - fold), r(y0 + fold)), (r(x1), r(y0 + fold))], fill=(205, 205, 205))
    d.rounded_rectangle(box(130, 600, 430, 740), radius=int(18 * k), fill=(220, 38, 38))
    f = font(int(110 * k))
    tw = d.textlength('PDF', font=f)
    d.text((r(280) - tw / 2, r(670)), 'PDF', font=f, fill='white', anchor='lm')
    for i, w in enumerate([200, 240, 170]):
        y = 470 + i * 40 if i < 2 else 780
        d.rounded_rectangle(box(190, y, 190 + w, y + 16), radius=int(8 * k), fill=(200, 200, 200))
    # seta do PDF para o leitor
    d.line([(r(200), r(370)), (r(330), r(245))], fill=(255, 196, 0), width=int(36 * k))
    d.polygon([(r(372), r(200)), (r(353), r(292)), (r(283), r(222))], fill=(255, 196, 0))
    return im

def legacy():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle([40, 40, S - 40, S - 40], radius=220, fill=BG)
    im.alpha_composite(foreground(0.86))
    return im

sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
leg, fg = legacy(), foreground(0.62)
for dens, px in sizes.items():
    d = os.path.join(RES, f'mipmap-{dens}'); os.makedirs(d, exist_ok=True)
    leg.resize((px, px), Image.LANCZOS).save(os.path.join(d, 'ic_launcher.png'))
    fg.resize((px * 9 // 4, px * 9 // 4), Image.LANCZOS).save(os.path.join(d, 'ic_launcher_foreground.png'))
os.makedirs(os.path.join(RES, 'mipmap-anydpi-v26'), exist_ok=True)
open(os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
open(os.path.join(RES, 'values', 'ic_launcher_background.xml'), 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1F6F5C</color>
</resources>
''')
legacy().resize((512, 512), Image.LANCZOS).save(os.path.join(os.path.dirname(RES.rstrip('/')), '..', '..', '..', '..', 'icone.png'))
print('ok')
