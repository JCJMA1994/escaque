"""Amplía assets/puzzles_chess.json hasta N1 mates en 1 y N2 mates en 2 sin
cambiar los existentes (mismos ids). Más rápido que gen_puzzles.py:
  - evalúa todas las posiciones de cada partida simulada, no solo la última;
  - antes de demostrar un mate en 2 (caro), exige un candidato barato: un jaque
    tras el que todas las respuestas (pocas) reciben mate. La unicidad se
    demuestra después contra TODAS las jugadas, igual que antes.
    python3 tool/puzzles/gen_more.py 200 100
"""
import json, os, random, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from chess import fen_parse, legal, apply, attacked, king
from gen_puzzles import fen, uci, mates_in_1, material, in_check, mate2_first, rating

HERE = os.path.dirname(os.path.abspath(__file__))
ASSET = os.path.join(HERE, '..', '..', 'assets', 'puzzles_chess.json')
START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
N1, N2 = (int(sys.argv[1]), int(sys.argv[2])) if len(sys.argv) > 2 else (200, 100)

def cheap_mate2_candidate(p):
    for m in legal(p):
        q = apply(p, m)
        if not in_check(q): continue
        replies = legal(q)
        if 0 < len(replies) <= 4 and all(mates_in_1(apply(q, r)) for r in replies):
            return True
    return False

def main():
    existing = json.load(open(ASSET))
    m1 = [x for x in existing if x['type'] == 'mate1']
    m2 = [x for x in existing if x['type'] == 'mate2']
    seen = {x['fen'].split(' ')[0] for x in existing}
    rng = random.Random(int(time.time()))
    t0 = time.time(); games = 0
    while len(m1) < N1 or len(m2) < N2:
        games += 1
        p = fen_parse(START)
        for ply in range(70):
            ms = legal(p)
            if not ms: break
            if ply >= 14 and not in_check(p) and len(ms) >= 12 and material(p, 1) >= 12 and material(p, -1) >= 10:
                key = fen(p).split(' ')[0]
                if key not in seen:
                    seen.add(key)
                    mates = mates_in_1(p)
                    if len(mates) == 1 and len(m1) < N1:
                        m1.append(dict(fen=fen(p), type='mate1', solution=uci(mates[0]), rating=rating(p, 1)))
                    elif not mates and len(m2) < N2 and cheap_mate2_candidate(p):
                        s = mate2_first(p)
                        if s: m2.append(dict(fen=fen(p), type='mate2', solution=uci(s), rating=rating(p, 2)))
            caps = [m for m in ms if p['b'][m[1]] != 0]
            p = apply(p, rng.choice(caps) if caps and rng.random() < 0.7 else rng.choice(ms))
        if games % 50 == 0:
            print(f'{int(time.time()-t0)} s, partidas {games}: mate1 {len(m1)} mate2 {len(m2)}', file=sys.stderr, flush=True)
            write(existing, m1, m2)
    write(existing, m1, m2)

def write(existing, m1, m2):
    # Los existentes conservan su id y su posición; los nuevos van detrás, intercalados.
    old_ids = {x['fen'] for x in existing}
    new1 = [x for x in m1 if x['fen'] not in old_ids]; new2 = [x for x in m2 if x['fen'] not in old_ids]
    out = list(existing); nid = max(x['id'] for x in existing) + 1
    while new1 or new2:
        for _ in range(2):
            if new1:
                x = new1.pop(0); x['id'] = nid; x['kind'] = 'chess'; out.append(x); nid += 1
        if new2:
            x = new2.pop(0); x['id'] = nid; x['kind'] = 'chess'; out.append(x); nid += 1
    tmp = ASSET + '.tmp'
    json.dump(out, open(tmp, 'w'), separators=(',', ':'))
    os.replace(tmp, ASSET)

if __name__ == '__main__':
    main()
