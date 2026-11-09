import re
TOK=re.compile(r'\s*(\(|\)|"(?:\\.|[^"\\])*"|[^\s()"]+)')
def parse(s):
    pos=0; stack=[[]]
    for m in TOK.finditer(s):
        t=m.group(1)
        if t=='(': stack.append([])
        elif t==')':
            x=stack.pop(); stack[-1].append(x)
        else: stack[-1].append(t)
    return stack[0]
def dump(x,ind=0):
    if isinstance(x,list):
        if all(not isinstance(e,list) for e in x):
            return '('+' '.join(x)+')'
        out='('+' '.join(e for e in x if not isinstance(e,list) and x.index(e)<1 or False)
        head=[]; rest=[]
        for i,e in enumerate(x):
            if isinstance(e,list): rest.append(e)
            elif not rest: head.append(e)
            else: rest.append(e)
        s='('+' '.join(head)
        for e in rest:
            s+='\n'+'  '*(ind+1)+(dump(e,ind+1) if isinstance(e,list) else e)
        return s+')'
    return x
def find(x,key):
    return [e for e in x if isinstance(e,list) and e and e[0]==key]
def find1(x,key):
    r=find(x,key); return r[0] if r else None
def uq(s): return s[1:-1] if s.startswith('"') else s
def q(s):
    s=str(s).replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')
    return '"'+s+'"'

