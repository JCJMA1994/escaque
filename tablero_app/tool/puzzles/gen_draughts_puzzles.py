"""Golpes de damas: una única jugada que, tras la respuesta forzada del rival,
permite ganar al menos 2 de material (peón 1, dama 3). Verificado por minimax."""
import random, json, sys
from draughts import VAR, init, legal, apply

def material(p, side):
    return sum((1 if abs(x) == 1 else 3) * (1 if x * side > 0 else -1) for x in p['b'] if x)

def gain_after(v, p, m, side):
    """Peor caso para nosotros (respuesta del rival) del mejor seguimiento."""
    q = apply(v, p, m)
    replies = legal(v, q)
    if not replies:
        return 99  # el rival no puede mover: gana
    worst = 99
    for r in replies:
        q2 = apply(v, q, r)
        follow = legal(v, q2)
        best = max((material(apply(v, q2, f), side) for f in follow), default=material(q2, side))
        worst = min(worst, best)
        if worst <= material(p, side): break
    return worst - material(p, side)

def playout(v, rng, plies):
    p = init(v)
    for _ in range(plies):
        ms = legal(v, p)
        if not ms: return None
        p = apply(v, p, rng.choice(ms))
    return p

def generate(vname, count, seed, max_tries=60000):
    v = VAR[vname]; rng = random.Random(seed); out = []; seen = set()
    for _ in range(max_tries):
        if len(out) >= count: break
        p = playout(v, rng, rng.randint(12, 40))
        if p is None: continue
        ms = legal(v, p)
        if len(ms) < 4 or any(c for _, c in ms): continue          # posición tranquila
        key = (tuple(p['b']), p['side'])
        if key in seen: continue
        seen.add(key)
        side = p['side']
        gains = [(gain_after(v, p, m, side), m) for m in ms]
        good = [m for g, m in gains if g >= 2]
        if len(good) != 1: continue
        if any(g > 0 for g, m in gains if m is not good[0]): continue
        g = max(g for g, _ in gains)
        out.append(dict(kind='draughts', variant=vname, board=list(p['b']), side=side,
                        solution=list(good[0][0]), gain=min(g, 9)))
    return out

if __name__ == '__main__':
    allp = []
    for vname, n, seed in (('international', 40, 1), ('spanish', 30, 2), ('english', 30, 3)):
        got = generate(vname, n, seed)
        print(vname, len(got), file=sys.stderr)
        allp += got
    json.dump(allp, open(sys.argv[1] if len(sys.argv) > 1 else '/tmp/draughts_puzzles.json', 'w'))
