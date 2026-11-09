# Keep silkscreen >= CLR from pads, vias and holes (JLC DFM: Good >= 0.18 mm).
import sys,math; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
from shapely.geometry import Polygon,Point,LineString,box,MultiLineString
from shapely.ops import unary_union
PCB=sys.argv[1] if len(sys.argv)>1 else '/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'
CLR=0.22; MM=pcbnew.FromMM; mm=pcbnew.ToMM
b=pcbnew.LoadBoard(PCB)
def poly_of(sps):
    out=[]
    for i in range(sps.OutlineCount()):
        o=sps.COutline(i); pts=[(mm(o.CPoint(k).x),mm(o.CPoint(k).y)) for k in range(o.PointCount())]
        if len(pts)>2: out.append(Polygon(pts))
    return out
obs={pcbnew.F_SilkS:[],pcbnew.B_SilkS:[]}
for fp in b.GetFootprints():
    for p in fp.Pads():
        for L,cu in ((pcbnew.F_SilkS,pcbnew.F_Cu),(pcbnew.B_SilkS,pcbnew.B_Cu)):
            if p.IsOnLayer(cu): obs[L]+=poly_of(p.GetEffectivePolygon(cu,pcbnew.ERROR_OUTSIDE))
            if p.GetDrillSizeX()>0:
                c=p.GetPosition(); obs[L].append(Point(mm(c.x),mm(c.y)).buffer(mm(max(p.GetDrillSizeX(),p.GetDrillSizeY()))/2))
vias=[t for t in b.GetTracks() if t.GetClass()=='PCB_VIA']
def via_geom(v): c=v.GetPosition(); return Point(mm(c.x),mm(c.y)).buffer(mm(v.GetWidth(pcbnew.F_Cu))/2)
# texts first: remove stitching vias under any visible silk text; record routing-via conflicts
removed=0; text_conf=[]
def texts():
    for d in b.GetDrawings():
        if d.GetClass()=='PCB_TEXT' and d.GetLayer() in obs: yield d,'board'
    for fp in b.GetFootprints():
        for f in [fp.Reference()]+[t for t in fp.GraphicalItems() if t.GetClass()=='PCB_TEXT']:
            if f.IsVisible() and f.GetLayer() in obs: yield f,fp.GetReference()
# --- nudge conflicting texts to the nearest free spot (pads/holes/routing vias/other texts) ---
bbB=b.GetBoardEdgesBoundingBox(); BW,BH=mm(bbB.GetWidth()),mm(bbB.GetHeight())
hard={L:list(v) for L,v in obs.items()}
for v in vias:
    if not (v.IsLocked() and v.GetNetname()=='GND'):
        g=via_geom(v); hard[pcbnew.F_SilkS].append(g); hard[pcbnew.B_SilkS].append(g)
HU={L:unary_union(v) for L,v in hard.items()}
allt=list(texts())
def tbox(t):
    bb=t.GetBoundingBox(); return box(mm(bb.GetX()),mm(bb.GetY()),mm(bb.GetRight()),mm(bb.GetBottom()))
boxes=[(t.GetLayer(),tbox(t)) for t,o in allt]
moved=[]
from shapely import affinity
# bottom legend block moves as one unit
GR={}
for i,(t,o) in enumerate(allt):
    if o=='board' and t.GetLayer()==pcbnew.B_SilkS: GR.setdefault(round(mm(t.GetPosition().x)),[]).append(i)
ingrp=set(i for v in GR.values() for i in v)
for grp in GR.values():
        G=unary_union([boxes[i][1] for i in grp]); L=pcbnew.B_SilkS
        def okg(gg):
            if gg.bounds[0]<0.5 or gg.bounds[1]<0.5 or gg.bounds[2]>BW-0.5 or gg.bounds[3]>BH-0.5: return False
            return not gg.buffer(CLR).intersects(HU[L])
        best=None
        if not okg(G):
            for r in [k*0.5 for k in range(1,80)]:
                for ang in range(0,360,10):
                    dx=r*math.cos(math.radians(ang)); dy=r*math.sin(math.radians(ang))
                    if okg(affinity.translate(G,dx,dy)): best=(dx,dy); break
                if best: break
        if best:
            for i in grp:
                t=allt[i][0]; p=t.GetPosition(); t.SetPosition(pcbnew.VECTOR2I(p.x+MM(best[0]),p.y+MM(best[1]))); boxes[i]=(L,tbox(t))
            moved.append(('legend block',round(best[0],2),round(best[1],2)))
for i,(t,owner) in enumerate(allt):
    L=t.GetLayer(); g=boxes[i][1]
    def ok(gg):
        if gg.bounds[0]<0.5 or gg.bounds[1]<0.5 or gg.bounds[2]>BW-0.5 or gg.bounds[3]>BH-0.5: return False
        if gg.buffer(CLR).intersects(HU[L]): return False
        return not any(gg.buffer(0.15).intersects(bx) for j,(LL,bx) in enumerate(boxes) if j!=i and LL==L)
    if i in ingrp or ok(g): continue
    best=None
    for r in [k*0.25 for k in range(1,41)]:
        for ang in range(0,360,15):
            dx=r*math.cos(math.radians(ang)); dy=r*math.sin(math.radians(ang))
            from shapely import affinity
            gg=affinity.translate(g,dx,dy)
            if ok(gg): best=(dx,dy); break
        if best: break
    if best:
        p=t.GetPosition(); t.SetPosition(pcbnew.VECTOR2I(p.x+MM(best[0]),p.y+MM(best[1])))
        boxes[i]=(L,tbox(t)); moved.append((owner,t.GetText()[:20],round(best[0],2),round(best[1],2)))
    else: moved.append((owner,t.GetText()[:20],'NO SPOT'))
print('moved texts',moved)
TX=[]
for t,owner in list(texts()):
    bb=t.GetBoundingBox(); TX.append((t.GetLayer(),box(mm(bb.GetX()),mm(bb.GetY()),mm(bb.GetRight()),mm(bb.GetBottom())).buffer(CLR),owner,t.GetText()))
VG=[(v,via_geom(v),v.IsLocked() and v.GetNetname()=='GND') for v in vias]
kill=set()
for L,g,owner,txt in TX:
    for i,(v,vg,st) in enumerate(VG):
        if vg.intersects(g):
            if st: kill.add(i)
            else: text_conf.append((owner,txt,'via'))
    if any(o.intersects(g) for o in obs[L]): text_conf.append((owner,txt,'pad/hole'))
VGEO=[vg for i,(v,vg,st) in enumerate(VG) if i not in kill]
for g in VGEO: obs[pcbnew.F_SilkS].append(g); obs[pcbnew.B_SilkS].append(g)
U={L:unary_union(v) for L,v in obs.items()}
def shape_lines(s):
    st=s.GetShape()
    if st==pcbnew.SHAPE_T_SEGMENT: return [[(mm(s.GetStart().x),mm(s.GetStart().y)),(mm(s.GetEnd().x),mm(s.GetEnd().y))]]
    if st==pcbnew.SHAPE_T_RECT:
        x0,y0,x1,y1=mm(s.GetStart().x),mm(s.GetStart().y),mm(s.GetEnd().x),mm(s.GetEnd().y)
        return [[(x0,y0),(x1,y0),(x1,y1),(x0,y1),(x0,y0)]]
    if st in (pcbnew.SHAPE_T_ARC,pcbnew.SHAPE_T_CIRCLE):
        c=s.GetCenter(); r=mm(s.GetRadius()); cx,cy=mm(c.x),mm(c.y)
        if st==pcbnew.SHAPE_T_CIRCLE: a0,a1=0,360
        else:
            a0=math.degrees(math.atan2(mm(s.GetStart().y)-cy,mm(s.GetStart().x)-cx)); sw=s.GetArcAngle().AsDegrees(); a1=a0+sw
        n=max(8,int(abs(a1-a0)/10))
        return [[(cx+r*math.cos(math.radians(a0+(a1-a0)*i/n)),cy+r*math.sin(math.radians(a0+(a1-a0)*i/n))) for i in range(n+1)]]
    return None
clipped=0; dropped=0
for fp in b.GetFootprints():
    for s in list(fp.GraphicalItems()):
        if s.GetClass()!='PCB_SHAPE' or s.GetLayer() not in obs: continue
        w=mm(s.GetWidth()); keep=U[s.GetLayer()].buffer(CLR+w/2)
        if s.GetShape()==pcbnew.SHAPE_T_POLY or (s.GetShape() in (pcbnew.SHAPE_T_RECT,pcbnew.SHAPE_T_CIRCLE) and s.IsFilled()):
            pts=poly_of(s.GetPolyShape()) if s.GetShape()==pcbnew.SHAPE_T_POLY else []
            bb_=s.GetBoundingBox(); g=unary_union(pts) if pts else box(mm(bb_.GetX()),mm(bb_.GetY()),mm(bb_.GetRight()),mm(bb_.GetBottom()))
            if g.buffer(w/2).intersects(keep): s.SetLayer(pcbnew.F_Fab if s.GetLayer()==pcbnew.F_SilkS else pcbnew.B_Fab); dropped+=1
            continue
        ls=shape_lines(s)
        if ls is None: continue
        geom=MultiLineString(ls); rest=geom.difference(keep)
        if rest.equals(geom): continue
        L=s.GetLayer(); s.SetLayer(pcbnew.F_Fab if L==pcbnew.F_SilkS else pcbnew.B_Fab); clipped+=1
        parts=[rest] if rest.geom_type=='LineString' else list(getattr(rest,'geoms',[]))
        for part in parts:
            if part.length<0.3: continue
            c=list(part.coords)
            for (x1,y1),(x2,y2) in zip(c,c[1:]):
                n=pcbnew.PCB_SHAPE(fp); n.SetShape(pcbnew.SHAPE_T_SEGMENT); n.SetLayer(L); n.SetWidth(MM(w))
                n.SetStart(pcbnew.VECTOR2I(MM(x1),MM(y1))); n.SetEnd(pcbnew.VECTOR2I(MM(x2),MM(y2))); fp.Add(n)

# ---- polarity / pin-1 dots (replace markers that were clipped away) ----
import re as _re
POL=_re.compile(r'^(D\d|LED|ZD|TVS|U\d|Q\d|C1$|C4$|C6$)')
UU=U[pcbnew.F_SilkS]
tb=unary_union([bx for LL,bx in boxes if LL==pcbnew.F_SilkS])
dots=0; nodot=[]
for fp in b.GetFootprints():
    r=fp.GetReference()
    if not POL.match(r) or r=='U2': continue
    p1=[p for p in fp.Pads() if p.GetNumber()=='1']
    if not p1: continue
    c=fp.GetPosition(); q=p1[0].GetPosition(); cx,cy,px,py=mm(c.x),mm(c.y),mm(q.x),mm(q.y)
    base=math.atan2(py-cy,px-cx); R=0.3; done=False
    for rr in [k*0.2 for k in range(3,30)]:
        for da in [0,30,-30,60,-60,90,-90,120,-120]:
            a=base+math.radians(da); x=px+rr*math.cos(a); y=py+rr*math.sin(a)
            pt=Point(x,y).buffer(R)
            if pt.distance(UU)>=CLR+0.03 and not pt.intersects(tb.buffer(0.1)):
                d=pcbnew.PCB_SHAPE(fp); d.SetShape(pcbnew.SHAPE_T_CIRCLE); d.SetLayer(pcbnew.F_SilkS); d.SetFilled(True); d.SetWidth(MM(0.15))
                d.SetCenter(pcbnew.VECTOR2I(MM(x),MM(y))); d.SetEnd(pcbnew.VECTOR2I(MM(x+R-0.075),MM(y))); fp.Add(d); dots+=1; done=True; break
        if done: break
    if not done: nodot.append(r)
print('pin1/polarity dots',dots,'failed',nodot)
for i in sorted(kill): b.Remove(VG[i][0]); removed+=1
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(PCB,b)
print(f'clipped {clipped} silk shapes, dropped {dropped} filled marks, removed {removed} stitching vias under text')
for c in text_conf: print('TEXT CONFLICT',c)
