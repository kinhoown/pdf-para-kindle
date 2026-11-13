"""Gera PDFs de teste: livro com capa ilustrada + capítulos, e um 'escaneado' (só imagens)."""
import os, random, sys
from fpdf import FPDF
from PIL import Image, ImageDraw

out = sys.argv[1]
os.makedirs(out, exist_ok=True)

# imagem de capa colorida
W, H = 800, 1200
im = Image.new('RGB', (W, H))
d = ImageDraw.Draw(im)
for y in range(H):
    d.line([(0, y), (W, y)], fill=(30 + y * 150 // H, 60, 160 - y * 100 // H))
for _ in range(40):
    x, y, r = random.randint(0, W), random.randint(0, H), random.randint(20, 120)
    d.ellipse([x - r, y - r, x + r, y + r], fill=(random.randint(150, 255), random.randint(80, 200), 40))
cover_path = os.path.join(out, 'cover.png'); im.save(cover_path)
fig = Image.new('RGB', (600, 300), (240, 240, 240)); fd = ImageDraw.Draw(fig)
for i in range(10): fd.rectangle([30 + i * 55, 280 - i * 25, 70 + i * 55, 280], fill=(40, 90 + i * 15, 200))
fig_path = os.path.join(out, 'fig.png'); fig.save(fig_path)

words = ('o livro conta uma história de aventura onde personagens viajam por terras distantes '
         'descobrindo segredos antigos e enfrentando desafios inesperados durante a jornada').split()
def para():
    return ' '.join(random.choice(words) for _ in range(random.randint(50, 110))).capitalize() + '.'

class Book(FPDF):
    def header(self):
        if self.page_no() > 2:
            self.set_font('Helvetica', 'I', 8); self.cell(0, 6, 'A Grande Jornada', align='C'); self.ln(8)
    def footer(self):
        if self.page_no() > 2:
            self.set_y(-12); self.set_font('Helvetica', '', 8); self.cell(0, 6, str(self.page_no()), align='C')

pdf = Book(format='A5'); pdf.set_auto_page_break(True, 18)
pdf.add_page(); pdf.image(cover_path, 0, 0, 148, 210)
pdf.set_font('Helvetica', 'B', 28); pdf.set_text_color(255, 255, 255); pdf.set_xy(10, 30); pdf.multi_cell(128, 12, 'A Grande Jornada', align='C')
pdf.set_text_color(0, 0, 0)
pdf.add_page(); pdf.set_font('Helvetica', '', 12); pdf.set_y(80); pdf.multi_cell(0, 8, 'A Grande Jornada\nEdição de teste\n2026', align='C')
for c in range(1, 5):
    pdf.add_page();
    pdf.set_font('Helvetica', 'B', 20); pdf.multi_cell(0, 12, f'Capítulo {c}'); pdf.ln(4)
    pdf.set_font('Times', '', 11)
    for p in range(8):
        pdf.multi_cell(0, 5.5, '      ' + para()); pdf.ln(1.5)
        if c == 2 and p == 3:
            pdf.image(fig_path, w=110); pdf.ln(2)
pdf.output(os.path.join(out, 'livro_teste.pdf'))

# "escaneado": páginas só com imagem
sc = FPDF(format='A5')
for i in range(6):
    sc.add_page(); sc.image(cover_path if i == 0 else fig_path, 0, 0, 148, 210)
sc.output(os.path.join(out, 'quadrinho_teste.pdf'))
print('ok')
