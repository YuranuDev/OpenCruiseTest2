import os,copy
from sexp import *
SYMDIR='/usr/share/kicad/symbols'
_cache={}
def libfile(lib):
    if lib not in _cache:
        p=os.path.join(SYMDIR,lib+'.kicad_sym')
        if not os.path.exists(p): p=os.path.join('/home/claude/pcb/lib',lib+'.kicad_sym')
        _cache[lib]=parse(open(p).read())[0]
    return _cache[lib]
def raw(lib,name):
    L=libfile(lib)
    for s in find(L,'symbol'):
        if uq(s[1])==name: return s
    raise KeyError(lib+':'+name)
def flat(lib,name):
    s=copy.deepcopy(raw(lib,name))
    ext=find1(s,'extends')
    if ext:
        p=flat(lib,uq(ext[1]))
        s=[e for e in s if not (isinstance(e,list) and e[0]=='extends')]
        # child props override; take parent's non-prop parts
        cp={uq(e[1]) for e in find(s,'property')}
        for e in p[2:]:
            if isinstance(e,list) and e[0]=='property':
                if uq(e[1]) not in cp: s.append(e)
            elif isinstance(e,list) and e[0]=='symbol':
                e=copy.deepcopy(e); pn=uq(ext[1]); sub=uq(e[1])
                e[1]=q(name+sub[len(pn):]); s.append(e)
            elif isinstance(e,list) and e[0] in ('property',): pass
            elif isinstance(e,list) and not find(s,e[0]): s.append(e)
    s[1]=q(lib+':'+name)
    return s
def pins(sym,unit=1):
    out={}
    for sub in find(sym,'symbol'):
        nm=uq(sub[1]); parts=nm.rsplit('_',2)
        u=int(parts[-2])
        if u not in (0,unit): continue
        for p in find(sub,'pin'):
            at=find1(p,'at'); num=uq(find1(p,'number')[1]); pname=uq(find1(p,'name')[1])
            out[num]=dict(x=float(at[1]),y=float(at[2]),a=float(at[3]) if len(at)>3 else 0,name=pname,type=p[1],len=float(find1(p,'length')[1]))
    return out
