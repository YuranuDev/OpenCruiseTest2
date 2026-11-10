import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'; MM=pcbnew.FromMM
B=pcbnew.B_SilkS
# bottom legend: auto-placed where there are no vias / THT pads
b=pcbnew.LoadBoard(PCB)
# port connectors are named by their function labels -> hide the J-number on silk
for fp in b.GetFootprints():
    if fp.GetReference() in ('J4','J6','J7','J8','J9','J12','J13','J14','J15','J16','J17','U3','U4','C42'): fp.Reference().SetVisible(False)   # ports: function labels instead; U3/U4/C42: no room for the number
obst=[]
for t in b.GetTracks():
    if t.GetClass()=='PCB_VIA' and not t.IsLocked(): bb=t.GetBoundingBox(); bb.Inflate(MM(0.35)); obst.append(bb)   # locked GND stitching vias under the legend are removed by silkclip.py
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.GetDrillSizeX()>0 or p.IsOnLayer(pcbnew.B_Cu): bb=p.GetBoundingBox(); bb.Inflate(MM(0.35)); obst.append(bb)
lines=['J5 EXT: 1 ACC 2 HOLD! 3 D2 4 D3 5 SDA','6 SCL 7 D6 8 D7 9 TX 10 RX 11 D10','12 3V3 13 5VS 14 12V 15-20 GND',
       'JP1 CAN-TX  JP4/5 CAN|KL  JP6 KL-TX','JP7 KL-DIR  JP2 PC-PWR  JP3 I2C-PU','JP8 GPS 1-2:3V3 2-3:5V  JP9 PPS->D10',
       'I2C1-4 GND 3V3 SDA SCL / I2C5-6 GND 5V SDA SCL','PULSE/AUX 12V 5V GND IO / GPS GND VCC RX TX PPS','HOLD low = PC OFF']
area=pcbnew.BOX2I(pcbnew.VECTOR2I(MM(60),MM(40)),pcbnew.VECTOR2I(MM(98),MM(48)))
placed=[]; ymin=40
for txt in lines:
    ok=False
    for yy in [x*0.5 for x in range(int(ymin*2),162)]:
        for xx in [x*0.5 for x in range(120,320)]:
            t=pcbnew.PCB_TEXT(b); t.SetText(txt); t.SetLayer(B); t.SetTextSize(pcbnew.VECTOR2I(MM(1),MM(1))); t.SetTextThickness(MM(0.15)); t.SetMirrored(True)
            t.SetPosition(pcbnew.VECTOR2I(MM(xx),MM(yy))); bb=t.GetBoundingBox()
            if not area.Contains(bb.GetOrigin()) or not area.Contains(bb.GetEnd()): continue
            if any(bb.Intersects(o) for o in obst+placed): continue
            b.Add(t); g=t.GetBoundingBox(); g.Inflate(MM(0.3)); placed.append(g); ok=True; ymin=yy+1.6; break
        if ok: break
    if not ok: print('NOT PLACED',txt)
pcbnew.SaveBoard(PCB,b)
print('silk ok')
import os; os._exit(0)
