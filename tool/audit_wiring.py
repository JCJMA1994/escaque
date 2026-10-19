#!/usr/bin/env python3
"""Auditoría de conexiones del monorepo: que cada pieza tenga su pareja.

    python3 tool/audit_wiring.py          # informe; código de salida 1 si hay problemas

Comprueba, sin compilar:
  1. API: cada llamada de la app tiene ruta en el servidor y envía los campos
     que la ruta exige; cada ruta del servidor tiene quien la llame (app,
     Scheduler, Pub/Sub o pruebas de carga).
  2. Navegación: cada push/go apunta a una ruta de GoRouter y cada ruta tiene
     al menos una forma de llegar.
  3. Símbolos públicos (clases, funciones, providers) definidos y nunca usados.
  4. Métodos públicos de servicios y repositorios que nadie llama.
  5. Eventos de Metrics definidos y no usados.
  6. Colecciones de Firestore usadas por app o servidor sin regla (y al revés).
  7. Landing: enlaces internos rotos y páginas que la app o Play necesitan.
  8. Recursos de pubspec que no existen o que nadie usa.
  9. Workflows del CI que citan archivos inexistentes.
 10. Documentos: archivos, enlaces, rutas, variables y workflows que citan; que el README del
     servidor documente todas las rutas.
 11. Códigos de error sin documentar, eventos de analítica fuera del plan y traducciones sin uso.
 12. Campos completos: cada ajuste se carga, se guarda y se copia; cada campo de GameRecord se
     escribe, se lee y se copia (si no, se perdería en Firestore).
"""
import glob, json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
os.chdir(ROOT)
problems, notes = [], []


def P(msg):
    problems.append(msg)


def read(p):
    return open(p, encoding='utf-8').read()


def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    return re.sub(r'(?m)^\s*//.*$|(?<=[;{}),\s])//(?!/).*$', '', src)


def dart_files(*dirs):
    out = []
    for d in dirs:
        out += [f.replace('\\', '/') for f in glob.glob(f'{d}/**/*.dart', recursive=True) if '/build/' not in f.replace('\\', '/') and '.dart_tool' not in f.replace('\\', '/')]
    return sorted(out)


APP = dart_files('tablero_app/lib')
APP_ALL = dart_files('tablero_app/lib', 'tablero_app/test', 'tablero_app/integration_test', 'tablero_app/test_driver')
SERVER = dart_files('tablero_server/lib', 'tablero_server/bin')
SERVER_ALL = dart_files('tablero_server/lib', 'tablero_server/bin', 'tablero_server/test')
ENGINE = dart_files('tablero_engine/lib')
ALL = dart_files('tablero_app', 'tablero_server', 'tablero_engine')
SRC = {f: strip_comments(read(f)) for f in ALL}

# ---------------------------------------------------------------- 1. API
api = SRC['tablero_server/lib/src/api.dart']
route_re = re.compile(r"r\.(get|post|put|delete)\('([^']+)'")
routes = {}
positions = [(m.start(), m.group(1).upper(), m.group(2)) for m in route_re.finditer(api)]
for i, (pos, method, path) in enumerate(positions):
    block = api[pos:positions[i + 1][0] if i + 1 < len(positions) else len(api)]
    required = set(re.findall(r"_(?:str|int)\(body, '(\w+)'\)", block))
    optional = set(re.findall(r"body\['(\w+)'\]", block))
    routes[path] = dict(method=method, required=required, optional=optional)


def pattern(path):
    return re.compile('^' + re.sub(r'<\w+>', r'[^/]+', re.escape(path).replace(r'\<', '<').replace(r'\>', '>')) + '$')


route_patterns = [(p, re.compile('^' + re.sub(r'<\w+>', '[^/]+', p) + '$')) for p in routes]
call_re = re.compile(r"\.(post|get)\(\s*'(/v1/[^']*)'\s*(?:,\s*(\{[^;]*?\})\s*)?\)", re.S)
called = set()
for f in APP:
    for m in call_re.finditer(SRC[f]):
        method, path, body = m.group(1).upper(), m.group(2), m.group(3) or ''
        concrete = re.sub(r'\$\{?\w+\}?', 'X', path)
        hit = [p for p, rx in route_patterns if rx.match(concrete)]
        if not hit:
            P(f'API: {f} llama {method} {path} y el servidor no tiene esa ruta')
            continue
        r = hit[0]
        called.add(r)
        if routes[r]['method'] != method:
            P(f'API: {f} usa {method} {path} pero la ruta es {routes[r]["method"]}')
        sent = set(re.findall(r"'(\w+)'\s*:", body))
        missing = routes[r]['required'] - sent
        if missing:
            P(f'API: {f} → {r} no envía {sorted(missing)}')
        unknown = sent - routes[r]['required'] - routes[r]['optional']
        if unknown:
            P(f'API: {f} → {r} envía campos que el servidor ignora: {sorted(unknown)}')

docs = read('GUIA_CONFIGURACION.md') + read('CI_CD.md') + read('OPERACION.md')
load = read('tool/load/partidas.js') if os.path.exists('tool/load/partidas.js') else ''
for path in routes:
    if path in called or path == '/healthz':
        continue
    if path.startswith('/v1/tasks/'):
        if path not in docs:
            P(f'API: {path} no aparece en la guía (Scheduler/Pub/Sub no la llamaría)')
        continue
    if re.sub(r'<\w+>', '', path) in load:
        continue
    P(f'API: {path} no la llama nadie')

# ---------------------------------------------------------------- 2. Navegación
router = SRC['tablero_app/lib/app/router.dart']
go_paths = re.findall(r"path:\s*'([^']+)'", router)
go_rx = [(p, re.compile('^' + re.sub(r':\w+', '[^/?]+', p) + r'(\?.*)?$')) for p in go_paths]
nav_re = re.compile(r"(?:context|router|appRouter|GoRouter\.of\(context\))\s*\.\s*(?:push|go|pushReplacement|replace)(?:<[^>]*>)?\(\s*'([^']+)'")
reached = set()
for f in APP_ALL:
    for m in nav_re.finditer(SRC[f]):
        target = re.sub(r'\$\{[^}]*\}|\$\w+', 'X', m.group(1))
        hit = [p for p, rx in go_rx if rx.match(target)]
        if not hit:
            P(f'Navegación: {f} va a {m.group(1)} y no hay GoRoute para esa ruta')
        reached.update(hit)
redirects = re.findall(r"return\s+'(/[^']*)'", router)
# Rutas a las que se llega desde fuera: App Links de invitación (/j/CÓDIGO).
external = {'/j/:code'}
for p in go_paths:
    if p == '/' or p in reached or p in redirects or p in external:
        continue
    P(f'Navegación: la ruta {p} existe pero nada lleva a ella')

# ---------------------------------------------------------------- 3. Símbolos sin usar
def defined_symbols(files):
    out = {}
    for f in files:
        s = SRC[f]
        for m in re.finditer(r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+)*(?:class|enum|mixin|extension\s+type|typedef)\s+([A-Z]\w*)', s, re.M):
            out.setdefault(m.group(1), f)
        for m in re.finditer(r'^final\s+(\w+Provider)\s*=', s, re.M):
            out.setdefault(m.group(1), f)
        for m in re.finditer(r'^(?:Future<[^>]*>|[A-Z]\w*(?:<[^>]*>)?\??|void|String|int|bool|double)\s+([a-z]\w*)\s*\(', s, re.M):
            if m.group(1) != 'main':
                out.setdefault(m.group(1), f)
    return out


def usage_count(name, files):
    rx = re.compile(r'\b' + re.escape(name) + r'\b')
    return sum(len(rx.findall(SRC[f])) for f in files)


for label, defs_files, use_files in (
    ('app', APP, APP_ALL),
    ('servidor', SERVER, SERVER_ALL),
    ('motor', ENGINE, ALL),
):
    for name, f in defined_symbols(defs_files).items():
        if usage_count(name, use_files) <= 1:
            P(f'Símbolo sin usar ({label}): {name} en {f}')

# ---------------------------------------------------------------- 4. Métodos públicos de servicios
SERVICES = {
    'tablero_app/lib/online/online_repository.dart': 'OnlineRepository',
    'tablero_server/lib/src/game_service.dart': 'GameService',
    'tablero_server/lib/src/social.dart': 'SocialService',
    'tablero_server/lib/src/purchases.dart': 'PurchaseService',
    'tablero_app/lib/purchases/purchases.dart': 'AdFreeController',
    'tablero_app/lib/account/auth_service.dart': 'AuthService',
    'tablero_app/lib/app/play_games.dart': 'PlayGames',
    'tablero_app/lib/ads/ads_service.dart': 'AdsService',
}
for f, cls in SERVICES.items():
    if f not in SRC:
        continue
    s = SRC[f]
    start = s.find(f'class {cls}')
    if start < 0:
        continue
    body = s[start:]
    users = APP_ALL if f.startswith('tablero_app') else SERVER_ALL
    for m in re.finditer(r'^  (?:static\s+)?(?:Future<[^>]*>|Stream<[^>]*>|[A-Z]\w*(?:<[^>]*>)?\??|void|String|int|bool)\s+([a-z]\w*)\s*[({]', body, re.M):
        name = m.group(1)
        if name in ('build', 'toString', 'dispose'):
            continue
        n = usage_count(name, users)
        if n <= 1:
            P(f'Método sin uso: {cls}.{name} ({f})')

# ---------------------------------------------------------------- 5. Eventos de Metrics
metrics = SRC['tablero_app/lib/app/metrics.dart']
for name in re.findall(r'^  static (?:void|Future<void>) (\w+)\(', metrics, re.M):
    if name.startswith('_') or name in ('init', 'setEnabled', 'storedChoice'):
        continue
    if not any(re.search(r'Metrics\.' + name + r'\b', SRC[f]) for f in APP if f != 'tablero_app/lib/app/metrics.dart'):
        P(f'Evento de Metrics sin usar: {name}')

# ---------------------------------------------------------------- 6. Colecciones de Firestore
rules = read('firebase/firestore.rules')
ruled = set(re.findall(r'match /(\w+)/\{', rules))
used = {}
for f in APP:
    for c in re.findall(r"collection\('(\w+)'\)|doc\('(\w+)/", SRC[f]):
        for x in c:
            if x:
                used.setdefault(x, f)
for f in SERVER:
    for c in re.findall(r"\$_documents/(\w+)/|collectionId: '(\w+)'|_queryDocs\('(\w+)'", SRC[f]):
        for x in c:
            if x:
                used.setdefault(x, f)
for c, f in sorted(used.items()):
    if c not in ruled:
        P(f'Firestore: la colección {c} ({f}) no tiene regla')
for c in sorted(ruled - set(used) - {'devices', 'databases'}):
    P(f'Firestore: regla para {c}, que nadie usa')


# ---------------------------------------------------------------- 6b. Campos de Firestore
def fields_written(src, cls):
    i = src.find(f'class {cls}')
    j = src.find('toFields()', i)
    k = src.find('};', j)
    return set(re.findall(r"'(\w+)':", src[j:k]))


def fields_read(src, start_marker, end_marker='}'):
    i = src.find(start_marker)
    j = src.find('\n  }', i)
    return set(re.findall(r"d\['(\w+)'\]", src[i:j]))


model = SRC['tablero_server/lib/src/model.dart']
social_model = SRC['tablero_server/lib/src/social_model.dart']
repo = SRC['tablero_app/lib/online/online_repository.dart']
for doc, written, read_ in (
    ('games', fields_written(model, 'GameRecord'), fields_read(repo, 'factory OnlineGame.fromDoc')),
    ('friendships', fields_written(social_model, 'Friendship'), fields_read(repo, 'factory Friend.fromDoc')),
):
    for f in sorted(read_ - written):
        P(f'Firestore: la app lee {doc}.{f} y el servidor no lo escribe')

# ---------------------------------------------------------------- 9. Workflows del CI
for wf in glob.glob('.github/workflows/*.yml'):
    text = read(wf)
    outputs = set(re.findall(r'--summary-export=([\w.-]+)', text))  # los genera el propio workflow
    for ref in set(re.findall(r'(?<![\w/.-])((?:tablero_app/tool|tool|infra|firebase|landing/scripts)/[\w./-]+?\.(?:json|yaml|yml|mjs|py|sh|js))\b', text)):
        if os.path.basename(ref) in outputs:
            continue
        if not os.path.exists(ref):
            P(f'CI: {wf} usa {ref}, que no existe')

# ---------------------------------------------------------------- 7. Landing
pages = set()
for f in glob.glob('landing/src/pages/**/*.astro', recursive=True):
    f_norm = f.replace('\\', '/')
    rel = f_norm[len('landing/src/pages'):-len('.astro')]
    rel = re.sub(r'/index$', '', rel) or '/'
    pages.add(rel if rel.startswith('/') else '/' + rel)
public = {'/' + os.path.relpath(f, 'landing/public').replace('\\', '/') for f in glob.glob('landing/public/**/*', recursive=True) if os.path.isfile(f)}
generated = {'/puzzles/catalog.json'}  # scripts/catalog.mjs
rewrites = {r['source'].replace('/**', '') for r in json.load(open('firebase.json', encoding='utf-8'))['hosting'][0].get('rewrites', [])}
for f in glob.glob('landing/src/**/*.astro', recursive=True):
    for href in re.findall(r'href=["\'](/[^"\'#?]*)', read(f)):
        h = href.rstrip('/') or '/'
        if h in pages or h in public or h in generated or any(h.startswith(r) for r in rewrites):
            continue
        if h.startswith('/_') or h == '/favicon.svg':
            continue
        P(f'Landing: {f} enlaza a {href}, que no existe')
app_refs = set()
for f in APP:
    for m in re.findall(r"inviteBaseUrl\}?(/[\w\-/.]+)", SRC[f]):
        app_refs.add(m)
for ref in app_refs | {'/privacidad', '/eliminar-cuenta', '/en/privacy', '/en/delete-account'}:
    r = ref.rstrip('/')
    if r in pages or r in public or r in generated or any(r.startswith(x) for x in rewrites):
        continue
    P(f'Landing: la app o Play necesitan {ref} y la web no lo tiene')
for f in APP:
    for path in re.findall(r"'(/(?:privacidad|eliminar-cuenta|en/privacy|en/delete-account)[^']*)'", SRC[f]):
        if path.rstrip('/') not in pages:
            P(f'Landing: {f} enlaza a {path}, que no existe')

# ---------------------------------------------------------------- 8. Recursos
pub = read('tablero_app/pubspec.yaml')
for a in re.findall(r'^\s+- (assets/\S+)', pub, re.M):
    p = os.path.join('tablero_app', a)
    if not os.path.exists(p):
        P(f'Recursos: {a} está en pubspec pero no existe')
    elif os.path.isfile(p) and not any(a in SRC[f] or os.path.basename(a) in SRC[f] for f in APP_ALL):
        P(f'Recursos: {a} no lo usa nadie')


# ---------------------------------------------------------------- 10. Documentos
DOCS = [f.replace('\\', '/') for f in glob.glob('**/*.md', recursive=True) if 'node_modules' not in f and '.dart_tool' not in f]
path_re = re.compile(r'`((?:tablero_app|tablero_server|tablero_engine|landing|firebase|infra|tool|\.github)/[\w./*<>-]+)`')
for d in DOCS:
    text = read(d)
    base = os.path.dirname(d)
    for ref in set(path_re.findall(text)):
        if any(ch in ref for ch in '*<>') or ref.endswith('/'):
            continue
        pkg = d.split('/')[0] if '/' in d else ''  # p. ej. tablero_app: rutas relativas al paquete
        if not (os.path.exists(ref) or os.path.exists(os.path.join(base, ref)) or (pkg and os.path.exists(os.path.join(pkg, ref)))):
            P(f'Docs: {d} cita {ref}, que no existe')
    for link in re.findall(r'\]\(([^)#:]+\.md)(?:#[^)]*)?\)', text):
        if not os.path.exists(os.path.normpath(os.path.join(base, link))):
            P(f'Docs: {d} enlaza a {link}, que no existe')
    for wf in set(re.findall(r'`(\w+\.yml)`', text)):
        if wf.startswith(('cloudbuild', 'firebase', 'pubspec', 'analysis_options', 'docker')):
            continue
        if not os.path.exists(f'.github/workflows/{wf}') and not glob.glob(f'**/{wf}', recursive=True):
            P(f'Docs: {d} cita el workflow {wf}, que no existe')
    for path in set(re.findall(r'(?<![\w/])(/v1/[\w/<>{}:-]+)', text)):
        if path.endswith('/'):
            continue  # prefijo («las de /v1/tasks/»), no una ruta
        norm = re.sub(r'\{\w+\}|:\w+', lambda m: '<id>', path).rstrip('/')
        if not any(re.fullmatch(re.sub(r'<\w+>', '[^/]+', r), re.sub(r'<\w+>', 'X', norm)) for r in routes):
            P(f'Docs: {d} menciona {path}, que no es una ruta del servidor')

server_readme = read('tablero_server/README.md')
for r in routes:
    if r == '/healthz':
        continue
    shown = re.sub(r'<(\w+)>', r'{\1}', r)
    if r not in server_readme and shown not in server_readme and re.sub(r'<\w+>', ':id', r) not in server_readme:
        P(f'Docs: la ruta {r} no está documentada en tablero_server/README.md')

server_env = set(re.findall(r"(?:need|env\[)\(?'([A-Z_]+)'", SRC['tablero_server/bin/server.dart']))
for d in DOCS:
    for var in set(re.findall(r'`([A-Z][A-Z0-9_]{3,})=?`', read(d))):
        if var.startswith(('PG_', 'APP_ID', 'ANDROID', 'FIREBASE', 'GCP_', 'PUBLIC_', 'SITE_', 'PLAY_RELEASE', 'API_', 'ENV', 'INVITE')):
            continue
        if var in ('LOAD_TEST_SECRET', 'K_SERVICE', 'PORT') or var in server_env:
            continue
        if re.search(r'(SERVICE_URL|PROJECT_|SCHEDULER_SA|APP_CHECK|MOVE_TIME)', var) and var not in server_env:
            P(f'Docs: {d} cita la variable {var}, que el servidor no lee')


# ---------------------------------------------------------------- 11. Errores, eventos y traducciones
codes = set()
for f in SERVER:
    codes |= set(re.findall(r"ApiError\(\s*\d+,\s*'(\w+)'", SRC[f]))
codes |= set(re.findall(r"static const \w+ = ApiError\(\d+, '(\w+)'", SRC['tablero_server/lib/src/errors.dart']))
for c in sorted(codes - {'bad_request', 'internal'}):
    if f'`{c}`' not in server_readme:
        P(f'Docs: el código de error {c} no está en tablero_server/README.md')

events = set(re.findall(r"_log\('(\w+)'", SRC['tablero_app/lib/app/metrics.dart']))
plan_events = set(re.findall(r"`(\w+)`(?: / `(\w+)`)? \|", read('PLAN.md')))
documented = {e for pair in plan_events for e in pair if e}
for e in sorted(events - documented):
    P(f'Docs: el evento de analítica {e} no está en la tabla de PLAN.md (fase A, punto 0)')

en_src = SRC['tablero_app/lib/l10n/en.dart']
keys = [k.replace("\\'", "'") for k in re.findall(r"^  '((?:[^'\\]|\\.)*)': ", read('tablero_app/lib/l10n/en.dart'), re.M)]
used_text = ''.join(read(f) for f in APP if not f.endswith('l10n/en.dart')) + ''.join(read(f) for f in SERVER)
dead = [k for k in keys if k.replace("'", "\\'") not in used_text and k not in used_text]
for k in dead:
    P(f'Traducción sin uso: «{k[:70]}»')


# ---------------------------------------------------------------- 12. Campos completos
st = SRC['tablero_app/lib/app/settings.dart']
cls = st[st.index('class AppSettings'):st.index('class SettingsController')]
ctrl = st[st.index('class SettingsController'):]
for fld in re.findall(r'^  final \w+\??\s+(\w+);', cls, re.M):
    if not re.search(rf'\b{fld}:\s*', ctrl):
        P(f'Ajustes: {fld} no se carga de las preferencias')
    if not re.search(rf'next\.{fld}\b', ctrl):
        P(f'Ajustes: {fld} no se guarda')
    if not re.search(rf'{fld}:\s*{fld}\s*\?\?\s*this\.{fld}', cls):
        P(f'Ajustes: {fld} no se conserva en copyWith')

gm = SRC['tablero_server/lib/src/model.dart']
gcls = gm[gm.index('class GameRecord'):]
gcls = gcls[:gcls.index('\nclass ') if '\nclass ' in gcls else len(gcls)]
to_fields = gcls[gcls.index('toFields()'):gcls.index('factory GameRecord.fromFields')]
from_fields = gcls[gcls.index('factory GameRecord.fromFields'):]
copy = gcls[gcls.index('GameRecord copyWith('):gcls.index('toFields()')]
for fld in re.findall(r'^  final [\w<>?, ]+\s+(\w+);', gcls, re.M):
    if fld == 'id':
        continue  # es el nombre del documento
    if f"'{fld}'" not in to_fields:
        P(f'Servidor: GameRecord.{fld} no se escribe en Firestore')
    if f"'{fld}'" not in from_fields:  # f['x'], strings('x') o result?['x']
        P(f'Servidor: GameRecord.{fld} no se lee de Firestore')
    if not re.search(rf'\b{fld}:', copy):
        P(f'Servidor: GameRecord.{fld} se pierde en copyWith')

# ---------------------------------------------------------------- Informe
for p in problems:
    print('•', p)
print(f'\n{len(problems)} problemas')
sys.exit(1 if problems else 0)
