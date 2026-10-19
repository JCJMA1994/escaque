# Icono de Escaque: un escaque de latón con el caballo propio en marfil sobre
# fieltro verde. Fuente única en SVG; de aquí salen todos los PNG.
import cairosvg, io, os
from PIL import Image
from pieces import P, D

FELT, FELT_DARK, BRASS, BRASS_DARK = '#17543F', '#124634', '#C99A3A', '#9C7424'
IVORY, EBONY, DETAIL = '#F6F3EA', '#1B1612', '#1B1612'
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'icon')
STORE = os.path.join(HERE, '..', '..', 'store')
os.makedirs(OUT, exist_ok=True); os.makedirs(STORE, exist_ok=True)

def knight(fill, line, detail, sw=3.2):
    d = D['knight'].replace('DETAIL', detail)
    return (f'<g fill="{fill}" stroke="{line}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round">{P["knight"]}</g>'
            f'<g fill="none" stroke="{detail}" stroke-width="{sw*0.8}" stroke-linecap="round">{d}</g>')

def background(size=108):
    # Fieltro con un damero apenas visible: 6×6 casillas en el lienzo de 108 dp.
    cell = size / 6
    sq = ''.join(f'<rect x="{c*cell:.2f}" y="{r*cell:.2f}" width="{cell:.2f}" height="{cell:.2f}"/>'
                 for r in range(6) for c in range(6) if (r + c) % 2)
    return f'<rect width="{size}" height="{size}" fill="{FELT}"/><g fill="{FELT_DARK}">{sq}</g>'

def foreground():
    # Zona segura de los iconos adaptativos: círculo de 66 dp centrado en 108.
    # El escaque mide 44 dp y el caballo cabe dentro del círculo.
    # Escaque de 50 dp con esquinas de 9: sus esquinas quedan a 31,6 dp del
    # centro, dentro del círculo seguro de 33. La oreja del caballo sobresale.
    return (f'<rect x="29" y="29" width="50" height="50" rx="9" fill="{BRASS}"/>'
            f'<rect x="29" y="29" width="50" height="50" rx="9" fill="none" stroke="{BRASS_DARK}" stroke-width="1.3"/>'
            f'<g transform="translate(20.6 18) scale(0.6)">{knight(IVORY, EBONY, DETAIL, 4.2)}</g>')

def monochrome():
    return ('<rect x="29" y="29" width="50" height="50" rx="9" fill="none" stroke="#FFFFFF" stroke-width="3.5"/>'
            f'<g transform="translate(20.6 18) scale(0.6)"><g fill="#FFFFFF">{P["knight"]}</g></g>')

def svg(body, size=108):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}">{body}</svg>'

def png(svg_text, w, h=None):
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg_text.encode(), output_width=w, output_height=h or w))).convert('RGBA')

full = background() + foreground()
for name, body in {'icon_background': background(), 'icon_foreground': foreground(),
                   'icon_monochrome': monochrome(), 'icon_full': full}.items():
    open(f'{OUT}/{name}.svg', 'w').write(svg(body))
    png(svg(body), 1024).save(f'{OUT}/{name}.png')

# Icono heredado (Android < 8) y de Play Store: el lienzo completo. Play aplica
# su propia máscara redondeada: se entrega cuadrado, sin sombras.
png(svg(full), 512).convert('RGB').save(f'{STORE}/play_icon_512.png', optimize=True)

# Gráfico destacado de Play Store: 1024×500, sin transparencia.
cells = ''.join(f'<rect x="{c*50}" y="{r*50}" width="50" height="50"/>' for r in range(10) for c in range(21) if (r + c) % 2)
def feature_graphic(tagline):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 500">'
           f'<rect width="1024" height="500" fill="{FELT}"/><g fill="{FELT_DARK}">{cells}</g>'
           f'<rect x="96" y="130" width="240" height="240" rx="38" fill="{BRASS}" stroke="{BRASS_DARK}" stroke-width="6"/>'
           f'<g transform="translate(66 92) scale(2.95)">{knight(IVORY, EBONY, DETAIL, 4.2)}</g>'
           f'<text x="392" y="262" font-family="ArchivoExpandedBlack" font-size="104" fill="{IVORY}">Escaque</text>'
           f'<text x="396" y="322" font-family="ArchivoMedium" font-size="34" fill="#DCE8E1">{tagline}</text>'
           f'</svg>')
for suffix, tagline in (('', 'Ajedrez y damas con reglas oficiales'), ('_en', 'Chess and draughts with official rules')):
    svg_text = feature_graphic(tagline)
    open(f'{STORE}/feature_graphic{suffix}.svg', 'w').write(svg_text)
    png(svg_text, 1024, 500).convert('RGB').save(f'{STORE}/feature_graphic{suffix}_1024x500.png', optimize=True)

# Vista previa: máscaras de Android (círculo, squircle, redondeado) y tamaños pequeños.
prev = Image.new('RGB', (900, 260), '#EEF1EC')
from PIL import ImageDraw
big = png(svg(full), 1024)
def masked(shape, size):
    im = big.resize((size, size), Image.LANCZOS)
    m = Image.new('L', (size, size), 0); dr = ImageDraw.Draw(m)
    if shape == 'circle': dr.ellipse((0, 0, size, size), fill=255)
    else: dr.rounded_rectangle((0, 0, size, size), radius=int(size * (0.3 if shape == 'squircle' else 0.18)), fill=255)
    im.putalpha(m); return im
x = 20
for shape in ['circle', 'squircle', 'rounded']:
    im = masked(shape, 200); prev.paste(im, (x, 30), im); x += 230
for s in (48, 32):
    im = masked('circle', s); prev.paste(im, (x, 60 if s == 48 else 140), im)
prev.save(os.path.join(STORE, 'icon_masks_preview.png'))
print('ok')
