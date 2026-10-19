# Piezas de ajedrez propias de Escaque. viewBox 0 0 100 100.
# FILL = cuerpo, LINE = contorno, DETAIL = detalles interiores.
SW = 3.2
BASE = '<path d="M30 72 H70 L74 80 H26 Z"/><rect x="21" y="80" width="58" height="9" rx="3.5"/>'
P = {
 'pawn': '<circle cx="50" cy="27" r="11"/>'
         '<path d="M40 40 H60 Q57 44 58.5 48 Q62 60 67 72 H33 Q38 60 41.5 48 Q43 44 40 40 Z"/>'
         '<rect x="37" y="38" width="26" height="6" rx="3"/>' + BASE,
 'rook': '<path d="M27 14 H37 V21 H45 V14 H55 V21 H63 V14 H73 V30 H27 Z"/>'
         '<path d="M33 30 H67 L64 64 H36 Z"/><path d="M31 64 H69 V72 H31 Z"/>' + BASE,
 'bishop': '<circle cx="50" cy="13" r="5"/>'
           '<path d="M50 18 C63 27 67 42 59 56 H41 C33 42 37 27 50 18 Z"/>'
           '<rect x="36" y="56" width="28" height="6" rx="3"/>'
           '<path d="M42 62 H58 Q60 67 66 72 H34 Q40 67 42 62 Z"/>' + BASE,
 'knight': '<path d="M33 72 C33 60 38 54 44 49 C40 47 33 49 27 52 C22 54 19 50 21 46 L36 27 '
           'C37 22 40 18 44 17 L45 10 L51 17 C66 20 75 34 73 52 C72 61 70 66 70 72 Z"/>' + BASE,
 'queen': '<circle cx="26" cy="27" r="4.5"/><circle cx="38" cy="19" r="4.5"/><circle cx="50" cy="15" r="4.5"/>'
          '<circle cx="62" cy="19" r="4.5"/><circle cx="74" cy="27" r="4.5"/>'
          '<path d="M27 31 L36 62 H64 L73 31 L61 46 L60 23 L50 41 L40 23 L39 46 Z"/>'
          '<rect x="34" y="62" width="32" height="6" rx="3"/><path d="M36 68 H64 L66 72 H34 Z"/>' + BASE,
 'king': '<path d="M46.5 6 H53.5 V12.5 H60 V19.5 H53.5 V26 H46.5 V19.5 H40 V12.5 H46.5 Z"/>'
         '<path d="M50 26 C65 26 74 34 69 48 L63 63 H37 L31 48 C26 34 35 26 50 26 Z"/>'
         '<rect x="34" y="63" width="32" height="6" rx="3"/><path d="M36 69 H64 L66 72 H34 Z"/>' + BASE,
}
D = {
 'pawn': '<path d="M30 72 H70"/>',
 'rook': '<path d="M36 36 H64"/><path d="M33 64 H67"/><path d="M30 72 H70"/>',
 'bishop': '<path d="M53 30 L45 42"/><path d="M39 59 H61"/><path d="M30 72 H70"/>',
 'knight': '<path d="M56 23 C63 30 66 40 65 52"/><circle cx="43" cy="30" r="2.4" fill="DETAIL" stroke="none"/><path d="M30 72 H70"/>',
 'queen': '<path d="M37 65 H63"/><path d="M30 72 H70"/>',
 'king': '<path d="M37 66 H63"/><path d="M30 72 H70"/>',
}
NAMES = ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn']

def svg(name, fill='FILL', line='LINE', detail='DETAIL'):
    d = D[name].replace('DETAIL', detail)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
            f'<g fill="{fill}" stroke="{line}" stroke-width="{SW}" stroke-linejoin="round" stroke-linecap="round">{P[name]}</g>'
            f'<g fill="none" stroke="{detail}" stroke-width="{SW * 0.8}" stroke-linecap="round">{d}</g></svg>')

if __name__ == '__main__':
    import cairosvg, io
    from PIL import Image
    sheet = Image.new('RGB', (6 * 130 + 20, 2 * 130 + 20), '#E9D8B4')
    for row, (fill, line, det) in enumerate([('#F6F3EA', '#3A2E22', '#3A2E22'), ('#23201D', '#0E0C0A', '#B9AE98')]):
        for i, n in enumerate(NAMES):
            png = cairosvg.svg2png(bytestring=svg(n, fill, line, det).encode(), output_width=120, output_height=120)
            im = Image.open(io.BytesIO(png)).convert('RGBA')
            bg = Image.new('RGBA', (130, 130), '#A0704A' if (i + row) % 2 else '#E9D8B4')
            bg.alpha_composite(im, (5, 5))
            sheet.paste(bg.convert('RGB'), (10 + i * 130, 10 + row * 130))
    sheet.save('pieces_preview.png')
