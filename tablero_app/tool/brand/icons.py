import os
# Iconos de interfaz propios de Escaque: rejilla 24, trazo 1.75, extremos y
# uniones redondeados, sin relleno salvo donde se indica. currentColor = color
# del tema (flutter_svg: SvgTheme.currentColor).
I = {
 'back': '<path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/>',
 'chevron_right': '<path d="M9 6l6 6-6 6"/>',
 'chevron_left': '<path d="M15 6l-6 6 6 6"/>',
 'first': '<path d="M17 6l-6 6 6 6"/><path d="M7 6v12"/>',
 'last': '<path d="M7 6l6 6-6 6"/><path d="M17 6v12"/>',
 'online': '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17"/><path d="M12 3.5c2.6 2.4 3.8 5.2 3.8 8.5s-1.2 6.1-3.8 8.5c-2.6-2.4-3.8-5.2-3.8-8.5S9.4 5.9 12 3.5z"/>',
 'flip': '<path d="M5 9.5A7.5 7.5 0 0 1 18 7"/><path d="M18.5 3.5V7.5H14.5"/><path d="M19 14.5A7.5 7.5 0 0 1 6 17"/><path d="M5.5 20.5V16.5H9.5"/>',
 'copy': '<rect x="9" y="9" width="11" height="11" rx="2.5"/><path d="M15 9V6.5A2.5 2.5 0 0 0 12.5 4h-6A2.5 2.5 0 0 0 4 6.5v6A2.5 2.5 0 0 0 6.5 15H9"/>',
 'eye': '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
 'eye_off': '<path d="M2.5 12S6 5.5 12 5.5c2 0 3.7.7 5.1 1.7M21.5 12s-3.5 6.5-9.5 6.5c-2 0-3.7-.7-5.1-1.7"/><path d="M4 4l16 16"/>',
 'undo': '<path d="M9 14L4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
 'settings': '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
 'local': '<circle cx="8.5" cy="8" r="3"/><path d="M3 19c.5-3.2 2.6-5 5.5-5s5 1.8 5.5 5"/><circle cx="16.5" cy="9" r="2.5"/><path d="M16 14c2.8 0 4.6 1.6 5 4.5"/>',
 'ai': '<rect x="6" y="6" width="12" height="12" rx="2.5"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3"/>',
 'mail': '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="M3.5 7l8.5 6.5L20.5 7"/>',
 'chat': '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8a2.5 2.5 0 0 1-2.5 2.5H10l-4.5 4v-4h0A2.5 2.5 0 0 1 4 13.5z"/><path d="M8.5 8.5h7M8.5 11.5h4.5"/>',
 'friends': '<circle cx="9" cy="8" r="3.25"/><path d="M3 19.5a6 6 0 0 1 12 0"/><path d="M15.5 4.9a3.25 3.25 0 0 1 0 6.2M17.5 14a6 6 0 0 1 3.5 5.5"/>',
 'trophy': '<path d="M8 4h8v5a4 4 0 0 1-8 0z"/><path d="M8 6H5v1.5A3.5 3.5 0 0 0 8.5 11M16 6h3v1.5a3.5 3.5 0 0 1-3.5 3.5"/><path d="M12 13v4M8.5 20.5h7M9.5 17h5v3.5h-5z"/>',
 'hint': '<path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-3.6 10.8c.7.5 1.1 1.3 1.1 2.1V16h5v-.1c0-.8.4-1.6 1.1-2.1A6 6 0 0 0 12 3z"/>',
 'info': '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/><path d="M12 7.6v.1"/>',
 'home': '<path d="M3.5 11L12 4l8.5 7"/><path d="M6 9.5V20h12V9.5"/><path d="M10 20v-5h4v5"/>',
 'history': '<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1"/><path d="M3.5 4v4h4"/><path d="M12 8v4.5l3 2"/>',
 'draw': '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5a8.5 8.5 0 0 0 0 17z" fill="currentColor" stroke="none"/>',
 'resign': '<path d="M5.5 21V4"/><path d="M5.5 4.5h11l-2 4 2 4h-11"/>',
 'error': '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5v6"/><path d="M12 16.4v.1"/>',
 'check': '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
 'check_circle': '<circle cx="12" cy="12" r="8.5"/><path d="M8 12.3l2.8 2.8L16.2 9.5"/>',
 'cancel': '<circle cx="12" cy="12" r="8.5"/><path d="M9 9l6 6M15 9l-6 6"/>',
 'account': '<circle cx="12" cy="9" r="3.5"/><path d="M5 20c.8-3.6 3.5-5.5 7-5.5s6.2 1.9 7 5.5"/>',
 'rules': '<path d="M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5z"/><path d="M5 19.5A1.5 1.5 0 0 0 6.5 21H19"/><path d="M9 7.5h6M9 11h4"/>',
 'stats': '<path d="M4 20h16"/><rect x="5.5" y="12" width="3" height="5" rx="1"/><rect x="10.5" y="7" width="3" height="10" rx="1"/><rect x="15.5" y="10" width="3" height="7" rx="1"/>',
 'board': '<rect x="4" y="4" width="16" height="16" rx="2.5"/><path d="M9.3 4v16M14.7 4v16M4 9.3h16M4 14.7h16"/><path d="M9.3 9.3h5.4v5.4H9.3z" fill="currentColor" stroke="none"/>',
 'chess': '<g transform="translate(0 -0.6) scale(0.24)" stroke-width="7.3"><path d="M33 72 C33 60 38 54 44 49 C40 47 33 49 27 52 C22 54 19 50 21 46 L36 27 C37 22 40 18 44 17 L45 10 L51 17 C66 20 75 34 73 52 C72 61 70 66 70 72 Z"/><path d="M26 86 H74"/><path d="M30 79 H70"/></g>',
 'draughts': '<ellipse cx="12" cy="14" rx="8" ry="4"/><path d="M4 14v-3c0-2.2 3.6-4 8-4s8 1.8 8 4v3"/><path d="M4 11c0 2.2 3.6 4 8 4s8-1.8 8-4"/>',
 'star': '<path d="M12 3l3.2 5.5H21l-3 5 3 5h-5.8L12 21l-3.2-2.5H3l3-5-3-5h5.8z"/>',
 'bell': '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
 'sound': '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
 'logout': '<path d="M10 4.5H6.5A2 2 0 0 0 4.5 6.5v11a2 2 0 0 0 2 2H10"/><path d="M14 8l4 4-4 4"/><path d="M18 12H9"/>',
 'drag': '<circle cx="9" cy="6.5" r="1"/><circle cx="15" cy="6.5" r="1"/><circle cx="9" cy="12" r="1"/><circle cx="15" cy="12" r="1"/><circle cx="9" cy="17.5" r="1"/><circle cx="15" cy="17.5" r="1"/>',
}
SW = 1.75

def svg(name):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
            f'stroke="currentColor" stroke-width="{SW}" stroke-linecap="round" stroke-linejoin="round">{I[name]}</svg>')

if __name__ == '__main__':
    import cairosvg, io
    from PIL import Image, ImageDraw
    names = list(I)
    cols = 8
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 110, rows * 110), '#FFFFFF')
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        png = cairosvg.svg2png(bytestring=svg(n).replace('currentColor', '#16201C').encode(), output_width=48, output_height=48)
        im = Image.open(io.BytesIO(png)).convert('RGBA')
        x, y = (i % cols) * 110, (i // cols) * 110
        sheet.paste(im, (x + 31, y + 18), im)
        d.text((x + 6, y + 80), n, fill='#4F5C56')
    here = os.path.dirname(os.path.abspath(__file__))
    sheet.save(os.path.join(here, 'previews', 'icons_preview.png'))
    # Los SVG de la app (assets/icons/<nombre>.svg)
    out = os.path.join(here, '..', '..', 'assets', 'icons')
    for n in names:
        with open(os.path.join(out, f'{n}.svg'), 'w') as f:
            f.write(svg(n))
    print(len(names), 'iconos')
