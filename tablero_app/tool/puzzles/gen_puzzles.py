"""Genera assets/puzzles_chess.json: 60 problemas de mate en 1 y 30 de mate en 2,
todos con solución única, a partir de partidas semialeatorias (con preferencia
por las capturas). Usa el prototipo del motor en Python (chess.py, validado con
perft). La app vuelve a comprobarlos con el motor de Dart (test/puzzles_test.dart).

    python3 tool/puzzles/gen_puzzles.py
"""
import random, json, sys
sys.setrecursionlimit(10000)
from chess import fen_parse, legal, apply, attacked, king, P,N,B,R,Q,K
START="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
VAL={P:1,N:3,B:3,R:5,Q:9,K:0}
def in_check(p): return attacked(p['b'],king(p['b'],p['side']),-p['side'])
def is_mate(p): return in_check(p) and not legal(p)
def fen(p):
    rows=[]
    for r in range(7,-1,-1):
        row='';e=0
        for f in range(8):
            v=p['b'][r*8+f]
            if v==0: e+=1; continue
            if e: row+=str(e); e=0
            ch='pnbrqk'[abs(v)-1]; row+=ch.upper() if v>0 else ch
        if e: row+=str(e)
        rows.append(row)
    c=''.join(ch for bit,ch in ((1,'K'),(2,'Q'),(4,'k'),(8,'q')) if p['c']&bit) or '-'
    ep='-' if p['ep']<0 else 'abcdefgh'[p['ep']%8]+str(p['ep']//8+1)
    return f"{'/'.join(rows)} {'w' if p['side']==1 else 'b'} {c} {ep} {p['hm']} {p['fm']}"
def uci(m):
    s,to,pr,fl=m; u='abcdefgh'[s%8]+str(s//8+1)+'abcdefgh'[to%8]+str(to//8+1)
    return u+('nbrq'[pr-2] if pr else '')
def mates_in_1(p): return [m for m in legal(p) if is_mate(apply(p,m))]
def material(p,side): return sum(VAL[abs(v)] for v in p['b'] if v*side>0)
def rating(p, mate_in):
    """Dificultad 1-3: mate en 2 parte de 2; los jaques que no dan mate despistan."""
    checks=sum(1 for m in legal(p) if in_check(apply(p,m)))
    return min(3, mate_in + (1 if checks >= 3 else 0))

def playout(rng, plies):
    p=fen_parse(START)
    for _ in range(plies):
        ms=legal(p)
        if not ms: return None
        caps=[m for m in ms if p['b'][m[1]]!=0]
        m=rng.choice(caps) if caps and rng.random()<0.7 else rng.choice(ms)
        p=apply(p,m)
    return p
def mate2_first(p):
    """Primera jugada única que fuerza mate en 2 (sin mate en 1)."""
    if mates_in_1(p): return None
    sols=[]
    for m in legal(p):
        q=apply(p,m)
        replies=legal(q)
        if not replies: continue  # ahogado o mate (descartado)
        if all(mates_in_1(apply(q,r)) for r in replies):
            sols.append(m)
            if len(sols)>1: return None
    return sols[0] if len(sols)==1 else None
def main_gen():
    rng=random.Random(2026)
    m1,m2=[],[]
    seen=set()
    tries=0
    N1,N2=200,100
    while (len(m1)<N1 or len(m2)<N2) and tries<150000:
        tries+=1
        if tries % 2000 == 0:
            print('progreso', tries, len(m1), len(m2), file=sys.stderr, flush=True)
            json.dump({'m1': m1, 'm2': m2}, open('/tmp/gen_chess_partial.json', 'w'))
        p=playout(rng, rng.randint(14,60))
        if p is None or in_check(p): continue
        if material(p,1)<12 or material(p,-1)<10: continue
        key=fen(p).split(' ')[0]
        if key in seen: continue
        seen.add(key)
        ms=mates_in_1(p)
        if len(m1)<N1 and len(ms)==1 and len(legal(p))>=12:
            m1.append(dict(fen=fen(p),type='mate1',solution=uci(ms[0]),rating=rating(p,1))); continue
        if len(m2)<N2 and not ms and len(legal(p))>=12:
            s=mate2_first(p)
            if s: m2.append(dict(fen=fen(p),type='mate2',solution=uci(s),rating=rating(p,2)))
    print(len(m1),len(m2),tries, file=sys.stderr)
    out=[]
    for i,x in enumerate(m1+m2): x['id']=i+1; out.append(x)
    # Intercalar: cada 3 problemas, uno de mate en 2
    mix=[]; a=[x for x in out if x['type']=='mate1']; b=[x for x in out if x['type']=='mate2']
    while a or b:
        for _ in range(2):
            if a: mix.append(a.pop(0))
        if b: mix.append(b.pop(0))
    for i,x in enumerate(mix): x['id']=i+1; x['kind']='chess'
    import os
    out_path=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','assets','puzzles_chess.json')
    json.dump(mix,open(out_path,'w'),ensure_ascii=False,indent=0)


if __name__ == '__main__':
    main_gen()
