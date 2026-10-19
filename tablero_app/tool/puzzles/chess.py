P,N,B,R,Q,K=1,2,3,4,5,6
KN=[(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)]
KG=[(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1)]
DI=[(1,1),(1,-1),(-1,1),(-1,-1)]
OR=[(1,0),(-1,0),(0,1),(0,-1)]
def sq(f,r): return r*8+f
def fen_parse(fen):
    parts=fen.split()
    b=[0]*64
    rows=parts[0].split('/')
    m={'p':P,'n':N,'b':B,'r':R,'q':Q,'k':K}
    for i,row in enumerate(rows):
        r=7-i;f=0
        for ch in row:
            if ch.isdigit(): f+=int(ch)
            else:
                v=m[ch.lower()]; b[sq(f,r)]= v if ch.isupper() else -v; f+=1
    side=1 if parts[1]=='w' else -1
    c=0
    for ch in parts[2]:
        c|={'K':1,'Q':2,'k':4,'q':8}.get(ch,0)
    ep=-1
    if parts[3]!='-': ep=sq(ord(parts[3][0])-97,int(parts[3][1])-1)
    return dict(b=b,side=side,c=c,ep=ep,hm=int(parts[4]) if len(parts)>4 else 0,fm=int(parts[5]) if len(parts)>5 else 1)
def attacked(b,s,by):
    f,r=s%8,s//8
    # pawns
    pr = r-1 if by==1 else r+1
    for df in (-1,1):
        ff=f+df
        if 0<=ff<8 and 0<=pr<8 and b[sq(ff,pr)]==by*P: return True
    for df,dr in KN:
        ff,rr=f+df,r+dr
        if 0<=ff<8 and 0<=rr<8 and b[sq(ff,rr)]==by*N: return True
    for df,dr in KG:
        ff,rr=f+df,r+dr
        if 0<=ff<8 and 0<=rr<8 and b[sq(ff,rr)]==by*K: return True
    for dirs,pcs in ((DI,(B,Q)),(OR,(R,Q))):
        for df,dr in dirs:
            ff,rr=f+df,r+dr
            while 0<=ff<8 and 0<=rr<8:
                v=b[sq(ff,rr)]
                if v!=0:
                    if v*by>0 and abs(v) in pcs: return True
                    break
                ff+=df;rr+=dr
    return False
def king(b,color):
    return b.index(color*K)
def pseudo(p):
    b,side=p['b'],p['side'];mv=[]
    for s in range(64):
        v=b[s]
        if v*side<=0: continue
        t=abs(v);f,r=s%8,s//8
        if t==P:
            d=side;start=1 if side==1 else 6;last=7 if side==1 else 0
            r1=r+d
            if 0<=r1<8 and b[sq(f,r1)]==0:
                to=sq(f,r1)
                if r1==last:
                    for pr in (Q,R,B,N): mv.append((s,to,pr,0))
                else:
                    mv.append((s,to,0,0))
                    if r==start and b[sq(f,r+2*d)]==0: mv.append((s,sq(f,r+2*d),0,1))
            for df in (-1,1):
                ff=f+df
                if not(0<=ff<8 and 0<=r1<8): continue
                to=sq(ff,r1)
                if b[to]*side<0:
                    if r1==last:
                        for pr in (Q,R,B,N): mv.append((s,to,pr,0))
                    else: mv.append((s,to,0,0))
                elif to==p['ep']: mv.append((s,to,0,2))
        elif t in (N,K):
            for df,dr in (KN if t==N else KG):
                ff,rr=f+df,r+dr
                if 0<=ff<8 and 0<=rr<8 and b[sq(ff,rr)]*side<=0: mv.append((s,sq(ff,rr),0,0))
            if t==K:
                c=p['c'];opp=-side
                if side==1 and s==4:
                    if c&1 and b[5]==0 and b[6]==0 and b[7]==R and not attacked(b,4,opp) and not attacked(b,5,opp) and not attacked(b,6,opp): mv.append((4,6,0,3))
                    if c&2 and b[3]==0 and b[2]==0 and b[1]==0 and b[0]==R and not attacked(b,4,opp) and not attacked(b,3,opp) and not attacked(b,2,opp): mv.append((4,2,0,3))
                if side==-1 and s==60:
                    if c&4 and b[61]==0 and b[62]==0 and b[63]==-R and not attacked(b,60,opp) and not attacked(b,61,opp) and not attacked(b,62,opp): mv.append((60,62,0,3))
                    if c&8 and b[59]==0 and b[58]==0 and b[57]==0 and b[56]==-R and not attacked(b,60,opp) and not attacked(b,59,opp) and not attacked(b,58,opp): mv.append((60,58,0,3))
        else:
            dirs = DI if t==B else OR if t==R else DI+OR
            for df,dr in dirs:
                ff,rr=f+df,r+dr
                while 0<=ff<8 and 0<=rr<8:
                    to=sq(ff,rr)
                    if b[to]*side>0: break
                    mv.append((s,to,0,0))
                    if b[to]!=0: break
                    ff+=df;rr+=dr
    return mv
RIGHT={0:2,7:1,56:8,63:4,4:3,60:12}
def apply(p,m):
    s,to,pr,fl=m
    b=p['b'][:];side=p['side'];v=b[s];cap=b[to]
    b[to]= side*pr if pr else v; b[s]=0
    if fl==2: b[to-8*side]=0
    if fl==3:
        if to==6: b[5]=b[7];b[7]=0
        elif to==2: b[3]=b[0];b[0]=0
        elif to==62: b[61]=b[63];b[63]=0
        elif to==58: b[59]=b[56];b[56]=0
    c=p['c'] & ~RIGHT.get(s,0) & ~RIGHT.get(to,0)
    ep= s+8*side if fl==1 else -1
    hm=0 if abs(v)==P or cap!=0 or fl==2 else p['hm']+1
    return dict(b=b,side=-side,c=c,ep=ep,hm=hm,fm=p['fm']+(1 if side==-1 else 0))
def legal(p):
    out=[]
    for m in pseudo(p):
        q=apply(p,m)
        if not attacked(q['b'],king(q['b'],p['side']),-p['side']): out.append(m)
    return out
def perft(p,d):
    if d==0: return 1
    ms=legal(p)
    if d==1: return len(ms)
    return sum(perft(apply(p,m),d-1) for m in ms)
if __name__ == '__main__':
    tests=[("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",[20,400,8902,197281]),
    ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",[48,2039,97862]),
    ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",[14,191,2812,43238]),
    ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",[44,1486,62379]),
    ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",[6,264,9467])]
    for fen,exp in tests:
        p=fen_parse(fen)
        got=[perft(p,i+1) for i in range(len(exp))]
        print(got==exp,got,exp)
    