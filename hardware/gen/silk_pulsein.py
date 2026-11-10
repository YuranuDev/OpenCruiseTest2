# place bottom-side legend texts where they do not touch vias / pads / holes (after stitching)
import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pulsein/pulsein.kicad_pcb'; MM=pcbnew.FromMM
b=pcbnew.LoadBoard(PCB)
obst=[]
for t in b.GetTracks():
    if t.GetClass()=='PCB_VIA': bb=t.GetBoundingBox(); bb.Inflate(MM(0.35)); obst.append(bb)
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.GetDrillSizeX()>0 or p.IsOnLayer(pcbnew.B_Cu): bb=p.GetBoundingBox(); bb.Inflate(MM(0.35)); obst.append(bb)
for d in list(b.GetDrawings()):
    if d.GetClass()=='PCB_TEXT' and d.GetLayer()==pcbnew.B_SilkS: d.SetLayer(pcbnew.B_Fab); d.SetVisible(False)
edge=b.GetBoardEdgesBoundingBox(); edge.Inflate(-MM(0.8))
lines=['PULSE-IN v1.0','IN: SIG GND 5V 12V','OUT: to J8 / J9','JP1: PU 5V|12V','JP2: 12V sig only']
placed=[]; ymin=2
for txt in lines:
    ok=False
    for yy in [x*0.5 for x in range(int(ymin*2),54)]:
        for xx in [x*0.5 for x in range(10,60)]:
            t=pcbnew.PCB_TEXT(b); t.SetText(txt); t.SetLayer(pcbnew.B_SilkS); t.SetTextSize(pcbnew.VECTOR2I(MM(1),MM(1))); t.SetTextThickness(MM(0.15))
            t.SetMirrored(True); t.SetPosition(pcbnew.VECTOR2I(MM(xx),MM(yy)))
            bb=t.GetBoundingBox()
            if not edge.Contains(bb.GetOrigin()) or not edge.Contains(bb.GetEnd()): continue
            if any(bb.Intersects(o) for o in obst+placed): continue
            b.Add(t); g=t.GetBoundingBox(); g.Inflate(MM(0.3)); placed.append(g); ok=True; ymin=yy+1.3; break
        if ok: break
    print(txt, 'placed' if ok else 'NOT PLACED', round(yy,1), round(xx,1))
for txt,x,y,just in [('5V',8.3,3.5,'right'),('12V',13.7,3.5,'left'),('12V TH',18.5,19.5,'left'),('IN',3.6,23.6,'center'),('OUT',29.8,23.6,'center')]:
    t=pcbnew.PCB_TEXT(b); t.SetText(txt); t.SetLayer(pcbnew.F_SilkS); t.SetTextSize(pcbnew.VECTOR2I(MM(1),MM(1))); t.SetTextThickness(MM(0.15))
    t.SetPosition(pcbnew.VECTOR2I(MM(x),MM(y)))
    t.SetHorizJustify({'left':pcbnew.GR_TEXT_H_ALIGN_LEFT,'center':pcbnew.GR_TEXT_H_ALIGN_CENTER,'right':pcbnew.GR_TEXT_H_ALIGN_RIGHT}[just]); b.Add(t)
pcbnew.SaveBoard(PCB,b)
