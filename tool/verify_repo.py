"""Comprobaciones estáticas del monorepo (sin SDK de Dart): delimitadores,
imports y dependencias, APIs obsoletas, assets, iconos, rutas, JSON y YAML.

    python3 tool/verify_repo.py
"""
import os, re, json, glob, subprocess, sys, yaml
root=os.path.dirname(os.path.dirname(os.path.abspath(__file__))); os.chdir(root)
problems=[]
def P(msg): problems.append(msg)

# 1. Delimitadores
out=subprocess.run([sys.executable,os.path.join(root,'tool','balance.py')]+glob.glob('**/*.dart',recursive=True),capture_output=True,text=True).stdout
if 'problemas: 0' not in out: P('Delimitadores: '+out)

# 2-3. Imports y dependencias
def deps(pubspec):
    d=yaml.safe_load(open(pubspec, encoding='utf-8'))
    return set((d.get('dependencies') or {}).keys())|set((d.get('dev_dependencies') or {}).keys())|{d['name']}
pkgs={'tablero_app':'tablero_app','tablero_engine':'tablero_engine','tablero_server':'tablero_server'}
SDK={'flutter','flutter_test','integration_test','dart'}
for pkg in pkgs:
    declared=deps(f'{pkg}/pubspec.yaml')
    for f in glob.glob(f'{pkg}/**/*.dart',recursive=True):
        src=open(f, encoding='utf-8').read()
        for imp in re.findall(r"^(?:import|export) '([^']+)'",src,flags=re.M):
            if imp.startswith('dart:'): continue
            if imp.startswith('package:'):
                name=imp[8:].split('/')[0]
                if name not in declared and name not in SDK: P(f'{f}: paquete no declarado {name}')
                if name in pkgs:
                    path=f"{name}/lib/{imp.split('/',1)[1]}"
                    if not os.path.exists(path): P(f'{f}: no existe {imp}')
            else:
                path=os.path.normpath(os.path.join(os.path.dirname(f),imp))
                if not os.path.exists(path): P(f'{f}: import roto {imp}')
        imps=re.findall(r"^import '([^']+)'",src,flags=re.M)
        dup={i for i in imps if imps.count(i)>1}
        if dup: P(f'{f}: import duplicado {dup}')

# 4. APIs retiradas u obsoletas
bad={r'\bIcons\.':'Icono de Material','GoogleFonts':'google_fonts eliminado',r'AndroidProvider\.':'App Check antiguo',
     'getCurrentOrientationAnchoredAdaptiveBannerAdSize':'banner obsoleto',r'SemanticsService\.announce\(':'announce obsoleto',
     r'\.withOpacity\(':'withOpacity obsoleto',r'GoogleSignIn\(':'google_sign_in 6',r'_google\.signIn\(\)':'google_sign_in 6',
     'WillPopScope':'obsoleto','MaterialStateProperty':'obsoleto',r'statusOf\(':'función eliminada',r"\\u26[5-9A-F]":'glifo Unicode',
     r'c\.value\b':'Color.value obsoleto','dart:developer':'usar Log'}
for f in glob.glob('tablero_*/**/*.dart',recursive=True):
    s=open(f, encoding='utf-8').read()
    for pat,why in bad.items():
        if re.search(pat,s): P(f'{f}: {why} ({pat})')

# 5. Argumentos con nombre duplicados en una misma llamada (heurística por bloques)
for f in glob.glob('tablero_*/**/*.dart',recursive=True):
    lines=open(f, encoding='utf-8').read().split('\n')
    for i in range(len(lines)):
        m=re.match(r'\s*(\w+):\s',lines[i])
        if not m or m.group(1) in ('case','default'): continue
        ind=len(lines[i])-len(lines[i].lstrip())
        for j in range(i+1,min(i+12,len(lines))):
            l=lines[j]; ind2=len(l)-len(l.lstrip())
            if l.strip()=='' : continue
            if ind2<ind: break
            if ind2==ind and re.match(r'\s*'+m.group(1)+r':\s',l): P(f'{f}:{i+1}: argumento repetido {m.group(1)}'); break

# 6. Assets
pub=yaml.safe_load(open('tablero_app/pubspec.yaml', encoding='utf-8'))
assets=pub['flutter']['assets']
for f in glob.glob('tablero_app/lib/**/*.dart',recursive=True):
    for a in re.findall(r"'(assets/[^'$]+)'",open(f, encoding='utf-8').read()):
        if not any(a.startswith(x) if x.endswith('/') else a==x for x in assets): P(f'{f}: asset no declarado {a}')
        if not os.path.exists('tablero_app/'+a) and not a.endswith('/'): P(f'{f}: asset no existe {a}')
for x in assets:
    if not os.path.exists('tablero_app/'+x): P(f'pubspec: asset inexistente {x}')
for fam in pub['flutter']['fonts']:
    for ft in fam['fonts']:
        if not os.path.exists('tablero_app/'+ft['asset']): P('fuente inexistente '+ft['asset'])

# 7. Iconos del enum
src=open('tablero_app/lib/ui/app_icon.dart', encoding='utf-8').read()
enum=re.search(r'enum AppIcons \{(.*?);',src,re.S).group(1)
names=[n.strip() for n in enum.replace('\n',' ').split(',') if n.strip()]
for n in names:
    fn=re.sub('[A-Z]',lambda m:'_'+m.group(0).lower(),n)
    if not os.path.exists(f'tablero_app/assets/icons/{fn}.svg'): P(f'icono sin archivo: {n}')
used=set(re.findall(r'AppIcons\.(\w+)',' '.join(open(f, encoding='utf-8').read() for f in glob.glob('tablero_app/lib/**/*.dart',recursive=True))))
for u in used-set(names)-{'values'}: P(f'AppIcons.{u} no existe')

# 8. Rutas
router=open('tablero_app/lib/app/router.dart', encoding='utf-8').read()
paths=re.findall(r"path: '([^']+)'",router)
regs=[re.compile('^'+re.sub(r':\w+','[^/]+',p)+'$') for p in paths]
for f in glob.glob('tablero_app/lib/**/*.dart',recursive=True):
    for r in re.findall(r"context\.(?:go|push|pushReplacement)\('([^']+)'",open(f, encoding='utf-8').read()):
        r=r.split('?')[0]
        r=re.sub(r'\$\{[^}]+\}|\$\w+','X',r)
        if not any(rg.match(r) for rg in regs): P(f'{f}: ruta desconocida {r}')

# 9. JSON y YAML
for f in glob.glob('**/*.json',recursive=True)+glob.glob('.firebaserc.example')+glob.glob('tablero_app/config/*.example'):
    if 'node_modules' in f or '/dist/' in f or '.dart_tool' in f: continue
    try: json.load(open(f, encoding='utf-8'))
    except Exception as e: P(f'JSON inválido {f}: {e}')
for f in glob.glob('.github/workflows/*.yml')+glob.glob('**/pubspec.yaml',recursive=True)+glob.glob('**/cloudbuild.yaml',recursive=True):
    try: yaml.safe_load(open(f, encoding='utf-8'))
    except Exception as e: P(f'YAML inválido {f}: {e}')

# 10b. Textos sin traducir: ningún Text('…') con texto literal en la app
for f in glob.glob('tablero_app/lib/**/*.dart',recursive=True):
    if '/l10n/' in f: continue
    for i,l in enumerate(open(f, encoding='utf-8').read().split('\n'),1):
        m=re.search(r"\bText\(\s*'([^']*)'",l)
        plain=re.sub(r'\$\{[^}]*\}|\$\w+','',m.group(1)) if m else ''
        if m and re.search(r'[A-Za-záéíóúñ]{2,}',plain) and m.group(1) not in ('Escaque',):
            P(f'{f}:{i}: texto sin tr(): {m.group(1)[:50]}')



# 0. Sintaxis de todo el Dart (tree-sitter; sin SDK). Opcional si falta el paquete:
#    pip install tree-sitter-language-pack
try:
    from tree_sitter_language_pack import get_parser as _ts_parser  # type: ignore
except ImportError:
    _ts_parser = None
if _ts_parser:
    _dart = _ts_parser('dart')
    for f in glob.glob('**/*.dart', recursive=True):
        if '/build/' in f or '.dart_tool' in f: continue
        src = open(f, 'rb').read()
        tree = _dart.parse(src)
        if tree.root_node.has_error:
            stack = [tree.root_node]; line = None
            while stack:
                n = stack.pop()
                if n.type == 'ERROR' or n.is_missing: line = n.start_point[0] + 1; break
                stack.extend(reversed([c for c in n.children if c.has_error or c.is_missing or c.type == 'ERROR']))
            P(f'{f}:{line}: error de sintaxis de Dart')
else:
    print('aviso: sin tree-sitter-language-pack, no se comprueba la sintaxis de Dart')


# 0b. `library;` debe ser la primera directiva (antes de cualquier import)
for f in glob.glob('**/*.dart', recursive=True):
    if '/build/' in f or '.dart_tool' in f: continue
    src = open(f, encoding='utf-8').read()
    lib = re.search(r'^library\b', src, re.M)
    imp = re.search(r'^(import|export|part) ', src, re.M)
    if lib and imp and imp.start() < lib.start():
        P(f'{f}: `library;` debe ir antes de los import')

# 10c. Símbolos del proyecto usados sin importar el archivo que los define
SYMBOLS = [
    (r'\bAppIcons?\b|\bAppIconButton\(', 'ui/app_icon.dart'),
    (r'(?<![\w.])tr\(', 'l10n/l10n.dart'),
    (r'\bTType\.|\bTableroColors\b', 'app/theme.dart'),
    (r'\bContentWidth\(|\bpagePadding\(|\bWindowSize\.', 'ui/layout.dart'),
    (r'context\.(push|go|pop|pushReplacement|canPop)\(|\bGoRouter\b', 'package:go_router/go_router.dart'),
    (r'\bMetrics\.', 'app/metrics.dart'),
    (r'\bTelemetry\.', 'app/telemetry.dart'),
    (r'\bPlayGames\.', 'app/play_games.dart'),
    (r'\badFreeProvider\b', 'purchases/purchases.dart'),
    (r'\bAppEnv\.', 'app/env.dart'),
    (r'\bPieceIcon\(|\bPieceKind\.', 'ui/piece_art.dart'),
]
for f in glob.glob('tablero_app/lib/**/*.dart',recursive=True)+glob.glob('tablero_app/test/**/*.dart',recursive=True)+glob.glob('tablero_app/integration_test/*.dart'):
    src=open(f, encoding='utf-8').read()
    imports=set()
    for imp in re.findall(r"^import '([^']+)'",src,flags=re.M):
        if imp.startswith('package:tablero_app/'): imports.add(os.path.normpath('tablero_app/lib/'+imp[len('package:tablero_app/'):]))
        elif imp.startswith('package:'): imports.add(imp)
        else: imports.add(os.path.normpath(os.path.join(os.path.dirname(f),imp)))
    body=re.sub(r"^(import|export) .*$","",src,flags=re.M)
    body=re.sub(r"//.*","",body)
    for pat,target in SYMBOLS:
        wanted = target if target.startswith('package:') else os.path.normpath('tablero_app/lib/'+target)
        if os.path.normpath(f)==wanted: continue
        if re.search(pat,body) and wanted not in imports:
            # se acepta si llega por export de otro archivo del paquete
            P(f'{f}: usa {pat.split("|")[0]} sin importar {target}')

# 10. Problemas: archivo y test coherentes
pz=json.load(open('tablero_app/assets/puzzles_chess.json', encoding='utf-8'))+json.load(open('tablero_app/assets/puzzles_draughts.json', encoding='utf-8'))
if len(pz)<190 or len({p['id'] for p in pz})!=len(pz): P('problemas: número o ids')

print('\n'.join(problems) if problems else 'Sin problemas')
print(f'{len(problems)} problemas')
sys.exit(1 if problems else 0)
