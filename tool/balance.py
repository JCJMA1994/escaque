import sys, re, glob
def strip(s):
    out=[];i=0;n=len(s)
    while i<n:
        c=s[i]
        if s.startswith('//',i):
            j=s.find('\n',i); i=n if j<0 else j; continue
        if s.startswith('/*',i):
            j=s.find('*/',i); i=n if j<0 else j+2; continue
        if c in '\'"':
            raw = i>0 and s[i-1]=='r'
            q=s[i:i+3] if s[i:i+3] in ("'''",'"""') else c
            i+=len(q)
            while i<n and not s.startswith(q,i):
                if s[i]=='\\' and not raw: i+=2; continue
                if s.startswith('${',i) and not raw:
                    depth=1;i+=2
                    while i<n and depth:
                        if s[i]=='{': depth+=1
                        elif s[i]=='}': depth-=1
                        i+=1
                    continue
                i+=1
            i+=len(q); out.append('""'); continue
        out.append(c); i+=1
    return ''.join(out)
bad=0
for f in sys.argv[1:]:
    s=strip(open(f, encoding='utf-8').read())
    st=[]
    pairs={')':'(',']':'[','}':'{'}
    line=1; ok=True
    for ch in s:
        if ch=='\n': line+=1
        if ch in '([{': st.append((ch,line))
        elif ch in ')]}':
            if not st or st[-1][0]!=pairs[ch]:
                print(f'{f}:{line}: cierre {ch} inesperado (abierto {st[-1] if st else None})'); ok=False; break
            st.pop()
    if ok and st: print(f'{f}: sin cerrar {st[-3:]}'); ok=False
    bad+= not ok
print('archivos con problemas:', bad)
