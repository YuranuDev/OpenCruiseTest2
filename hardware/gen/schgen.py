import sys,uuid,math,copy
sys.path.insert(0,'/home/claude/pcb/gen')
from sexp import *
from lib import flat,pins,parse,find,find1,uq,q
import lib as L
def U(): return str(uuid.uuid4())
G=1.27
def snap(v): return round(round(v/G)*G,4)
class Sheet:
    def __init__(s,project,title,paper='A2',rev='1.0'):
        s.project=project; s.title=title; s.paper=paper; s.rev=rev
        s.root=U(); s.libs={}; s.items=[]; s.parts=[]; s.labels=[]
    def libsym(s,lib,name):
        k=lib+':'+name
        if k not in s.libs: s.libs[k]=flat(lib,name)
        return s.libs[k]
    def part(s,ref,lib,name,x,y,nets,value=None,fp=None,lcsc=None,mpn=None,dnp=False,rot=0,props=None,inbom=True,onboard=True):
        sy=s.libsym(lib,name); P=pins(sy)
        x=snap(x); y=snap(y)
        defp={uq(p[1]):uq(p[2]) for p in find(sy,'property')}
        value=value or defp.get('Value',name); fp=fp if fp is not None else defp.get('Footprint','')
        out=[]
        th=math.radians(rot)
        for num,p in P.items():
            if p['type']=='no_connect': continue
            # symbol coords -> schematic (rotate then flip y)
            px=p['x']*math.cos(th)-p['y']*math.sin(th); py=p['x']*math.sin(th)+p['y']*math.cos(th)
            X=snap(x+px); Y=snap(y-py)
            a=math.radians(p['a']+rot)
            dx=-math.cos(a); dy=math.sin(a)
            net=nets.get(num,'__NC__')
            if net is None or net=='__NC__':
                if num in nets or True:
                    s.items.append(f'(no_connect (at {X} {Y}) (uuid "{U()}"))')
                continue
            X2=snap(X+dx*2.54); Y2=snap(Y+dy*2.54)
            s.items.append(f'(wire (pts (xy {X} {Y}) (xy {X2} {Y2})) (stroke (width 0) (type default)) (uuid "{U()}"))')
            if abs(dx)>0.5: ang=0 if dx>0 else 180
            else: ang=270 if dy>0 else 90
            just='left' if ang in (0,90) else 'right'
            s.items.append(f'(label {q(net)} (at {X2} {Y2} {ang}) (effects (font (size 1.27 1.27)) (justify {just} bottom)) (uuid "{U()}"))')
            s.labels.append(net)
        for k in nets:
            assert k in P, f'{ref}: pin {k} not in {name} {list(P)}'
        props=props or {}
        pl=[('Reference',ref,0,-1),('Value',value,0,1),('Footprint',fp,1,0),('Datasheet',defp.get('Datasheet',''),1,0)]
        if lcsc: pl.append(('LCSC',lcsc,1,0))
        if mpn: pl.append(('MPN',mpn,1,0))
        for k,v in props.items(): pl.append((k,v,1,0))
        # find bbox for ref/value placement
        ys=[snap(y-p['y']) for p in P.values()] or [y]; xs=[snap(x+p['x']) for p in P.values()] or [x]
        top=min(ys+[y-2.54]); bot=max(ys+[y+2.54])
        pr=''
        for k,v,hide,pos in pl:
            py_=top-1.27 if pos==-1 else (bot+1.27 if pos==1 else y)
            px_=x
            if pos!=0 and 0<len(P)<=2 and all(abs(p['x'])<0.1 for p in P.values()):  # vertical 2-pin: put text to right
                py_=y-1.27 if pos==-1 else y+1.27; px_=x+2.54
                just='(justify left)'
            else:
                just=''
                if len(P)>2 and pos!=0: px_=x+6.35; just='(justify left)'
            pr+=f'\n (property {q(k)} {q(v)} (at {snap(px_)} {snap(py_)} 0) (effects (font (size 1.27 1.27)) {just} {"(hide yes)" if hide else ""}))'
        pinl=' '.join(f'(pin {q(n)} (uuid "{U()}"))' for n in P)
        s.items.append(f'''(symbol (lib_id {q(lib+":"+name)}) (at {x} {y} {rot}) (unit 1) (exclude_from_sim no) (in_bom {"yes" if inbom else "no"}) (on_board {"yes" if onboard else "no"}) (dnp {"yes" if dnp else "no"}) (uuid "{U()}"){pr}
 {pinl}
 (instances (project {q(s.project)} (path "/{s.root}" (reference {q(ref)}) (unit 1)))))''')
        s.parts.append(dict(ref=ref,value=value,fp=fp,lcsc=lcsc,dnp=dnp,nets=nets))
    def flag(s,net,x,y):
        sy=s.libsym('power','PWR_FLAG'); n=len([1 for p in s.parts if p['ref'].startswith('#FLG')])+1
        x=snap(x);y=snap(y)
        s.items.append(f'(wire (pts (xy {x} {y}) (xy {x} {snap(y+2.54)})) (stroke (width 0) (type default)) (uuid "{U()}"))')
        s.items.append(f'(label {q(net)} (at {x} {snap(y+2.54)} 270) (effects (font (size 1.27 1.27)) (justify right bottom)) (uuid "{U()}"))')
        s.items.append(f'''(symbol (lib_id "power:PWR_FLAG") (at {x} {y} 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "{U()}")
 (property "Reference" "#FLG0{n:02d}" (at {x} {y-3} 0) (effects (font (size 1.27 1.27)) (hide yes)))
 (property "Value" "PWR_FLAG" (at {x} {snap(y-3.81)} 0) (effects (font (size 1.27 1.27))))
 (property "Footprint" "" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
 (property "Datasheet" "" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
 (pin "1" (uuid "{U()}"))
 (instances (project {q(s.project)} (path "/{s.root}" (reference "#FLG0{n:02d}") (unit 1)))))''')
        s.parts.append(dict(ref=f'#FLG0{n:02d}',nets={'1':net}))
    def text(s,t,x,y,size=2.0):
        s.items.append(f'(text {q(t)} (exclude_from_sim no) (at {snap(x)} {snap(y)} 0) (effects (font (size {size} {size}) (bold yes)) (justify left bottom)) (uuid "{U()}"))')
    def note(s,t,x,y,size=1.27):
        s.items.append(f'(text {q(t)} (exclude_from_sim no) (at {snap(x)} {snap(y)} 0) (effects (font (size {size} {size})) (justify left top)) (uuid "{U()}"))')
    def box(s,x1,y1,x2,y2,title):
        s.items.append(f'(rectangle (start {snap(x1)} {snap(y1)}) (end {snap(x2)} {snap(y2)}) (stroke (width 0.3) (type dash) (color 0 0 132 1)) (fill (type none)) (uuid "{U()}"))')
        s.text(title,x1+2,y1+5)
    def write(s,path,date='2026-11-09',company='OpenCruise'):
        ls='\n'.join(dump(v) for v in s.libs.values())
        body='\n'.join(s.items)
        out=f'''(kicad_sch (version 20250114) (generator "eeschema") (generator_version "9.0") (uuid "{s.root}") (paper {q(s.paper)})
 (title_block (title {q(s.title)}) (date {q(date)}) (rev {q(s.rev)}) (company {q(company)}))
 (lib_symbols
{ls}
 )
{body}
 (sheet_instances (path "/" (page "1")))
 (embedded_fonts no))
'''
        open(path,'w').write(out)
