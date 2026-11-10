import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'; MM=pcbnew.FromMM
b=pcbnew.LoadBoard(PCB)
for t in list(b.GetTracks()):
    if t.GetClass()=='PCB_VIA' and t.GetNetname()=='GND' and t.IsLocked(): b.Remove(t)   # previous stitching
zs={z.GetLayer():z for z in b.Zones()}
fF=zs[pcbnew.F_Cu].GetFilledPolysList(pcbnew.F_Cu); fB=zs[pcbnew.B_Cu].GetFilledPolysList(pcbnew.B_Cu)
bb=b.GetBoardEdgesBoundingBox(); W=pcbnew.ToMM(bb.GetWidth()); H=pcbnew.ToMM(bb.GetHeight())
need=MM(0.85/2+0.35)
# keep away from footprints' courtyards (no vias under parts) and mounting holes
crt=[]
for fp in b.GetFootprints():
    c=fp.GetCourtyard(pcbnew.F_CrtYd)
    if c.OutlineCount(): crt.append(c)
def inside_full(poly,p):
    # point inside filled copper with radius 'need' clear of the fill border
    return poly.Contains(p) and not poly.Collide(p,0) is False and poly.Contains(p) and _clear(poly,p)
def _clear(poly,p):
    for dx,dy in [(need,0),(-need,0),(0,need),(0,-need),(need*0.7,need*0.7),(-need*0.7,need*0.7),(need*0.7,-need*0.7),(-need*0.7,-need*0.7)]:
        if not poly.Contains(pcbnew.VECTOR2I(p.x+int(dx),p.y+int(dy))): return False
    return True
holes=[(pcbnew.ToMM(t.GetPosition().x),pcbnew.ToMM(t.GetPosition().y)) for t in b.GetTracks() if t.GetClass()=='PCB_VIA']
for fp in b.GetFootprints():
    for pd in fp.Pads():
        if pd.GetDrillSizeX()>0: holes.append((pcbnew.ToMM(pd.GetPosition().x),pcbnew.ToMM(pd.GetPosition().y)))
import math
n=0; step=4.0
y=4.0
while y<H-3:
    x=4.0
    while x<W-3:
        p=pcbnew.VECTOR2I(MM(x),MM(y))
        if all(math.dist((x,y),h)>1.5 for h in holes) and _clear(fF,p) and _clear(fB,p) and not any(c.Collide(p,MM(0.5)) for c in crt):
            v=pcbnew.PCB_VIA(b); v.SetPosition(p); v.SetWidth(MM(0.85)); v.SetDrill(MM(0.3)); v.SetNet(b.FindNet('GND')); v.SetLocked(True); b.Add(v); n+=1
        x+=step
    y+=step
for z in b.Zones(): z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)   # now drop islands that are still floating
f=pcbnew.ZONE_FILLER(b); f.Fill(b.Zones())
pcbnew.SaveBoard(PCB,b)
print('stitching vias',n)
