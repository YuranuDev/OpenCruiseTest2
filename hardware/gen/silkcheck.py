import sys,math; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
from shapely.geometry import Polygon,Point,LineString,box
from shapely.ops import unary_union
PCB=sys.argv[1]; mm=pcbnew.ToMM
b=pcbnew.LoadBoard(PCB)
def poly_of(s):
    r=[]
    for i in range(s.OutlineCount()):
        o=s.COutline(i); pts=[(mm(o.CPoint(k).x),mm(o.CPoint(k).y)) for k in range(o.PointCount())]
        if len(pts)>2: r.append(Polygon(pts))
    return r
res={}
for L,cu in ((pcbnew.F_SilkS,pcbnew.F_Cu),(pcbnew.B_SilkS,pcbnew.B_Cu)):
    pads=[];holes=[]
    for fp in b.GetFootprints():
        for p in fp.Pads():
            if p.IsOnLayer(cu): pads+=poly_of(p.GetEffectivePolygon(cu,pcbnew.ERROR_OUTSIDE))
            if p.GetDrillSizeX()>0: c=p.GetPosition(); holes.append(Point(mm(c.x),mm(c.y)).buffer(mm(max(p.GetDrillSizeX(),p.GetDrillSizeY()))/2))
    for t in b.GetTracks():
        if t.GetClass()=='PCB_VIA':
            c=t.GetPosition(); pads.append(Point(mm(c.x),mm(c.y)).buffer(mm(t.GetWidth(pcbnew.F_Cu))/2)); holes.append(Point(mm(c.x),mm(c.y)).buffer(mm(t.GetDrillValue())/2))
    P=unary_union(pads); H=unary_union(holes)
    items=[]
    for fp in b.GetFootprints():
        for s in fp.GraphicalItems():
            if s.GetLayer()!=L: continue
            if s.GetClass()=='PCB_SHAPE' and s.GetShape()==pcbnew.SHAPE_T_SEGMENT:
                items.append((fp.GetReference(),LineString([(mm(s.GetStart().x),mm(s.GetStart().y)),(mm(s.GetEnd().x),mm(s.GetEnd().y))]).buffer(mm(s.GetWidth())/2)))
            elif s.GetClass()=='PCB_SHAPE':
                w=mm(s.GetWidth())/2
                if s.GetShape()==pcbnew.SHAPE_T_POLY:
                    ps=poly_of(s.GetPolyShape()); g=unary_union(ps)
                    g=g if s.IsFilled() else g.boundary
                elif s.GetShape()==pcbnew.SHAPE_T_RECT:
                    x0,y0,x1,y1=mm(s.GetStart().x),mm(s.GetStart().y),mm(s.GetEnd().x),mm(s.GetEnd().y); g=box(min(x0,x1),min(y0,y1),max(x0,x1),max(y0,y1))
                    g=g if s.IsFilled() else g.boundary
                elif s.GetShape() in (pcbnew.SHAPE_T_CIRCLE,pcbnew.SHAPE_T_ARC):
                    c=s.GetCenter(); g=Point(mm(c.x),mm(c.y)).buffer(mm(s.GetRadius()))
                    g=g if s.IsFilled() else g.boundary
                else:
                    bb=s.GetBoundingBox(); g=box(mm(bb.GetX()),mm(bb.GetY()),mm(bb.GetRight()),mm(bb.GetBottom()))
                items.append((fp.GetReference()+':'+str(s.GetShape()),g.buffer(w)))
            elif s.GetClass()=='PCB_TEXT' and s.IsVisible():
                bb=s.GetBoundingBox(); items.append((fp.GetReference()+':'+s.GetText(),box(mm(bb.GetX()),mm(bb.GetY()),mm(bb.GetRight()),mm(bb.GetBottom()))))
        r=fp.Reference()
        if r.IsVisible() and r.GetLayer()==L:
            bb=r.GetBoundingBox(); items.append((fp.GetReference()+':ref',box(mm(bb.GetX()),mm(bb.GetY()),mm(bb.GetRight()),mm(bb.GetBottom()))))
    for d in b.GetDrawings():
        if d.GetClass()=='PCB_TEXT' and d.GetLayer()==L:
            bb=d.GetBoundingBox(); items.append(('text:'+d.GetText()[:15],box(mm(bb.GetX()),mm(bb.GetY()),mm(bb.GetRight()),mm(bb.GetBottom()))))
    dp=min((g.distance(P),n) for n,g in items); dh=min((g.distance(H),n) for n,g in items)
    bad=[(n,round(g.distance(P),3)) for n,g in items if g.distance(P)<0.18]
    badh=[(n,round(g.distance(H),3)) for n,g in items if g.distance(H)<0.18]
    print(pcbnew.LayerName(L),'min silk-pad',round(dp[0],3),dp[1],'| min silk-hole',round(dh[0],3),dh[1],'| <0.18:',len(bad),len(badh))
    for x in (bad+badh)[:15]: print('   ',x)
