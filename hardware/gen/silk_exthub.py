import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/exthub/exthub.kicad_pcb'; MM=pcbnew.FromMM
b=pcbnew.LoadBoard(PCB)
obst=[]
for t in b.GetTracks():
    if t.GetClass()=='PCB_VIA': bb=t.GetBoundingBox(); bb.Inflate(MM(0.35)); obst.append(bb)
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.GetDrillSizeX()>0 or p.IsOnLayer(pcbnew.B_Cu): bb=p.GetBoundingBox(); bb.Inflate(MM(0.35)); obst.append(bb)
def T(txt,x,y,layer=pcbnew.F_SilkS,ang=0,just='center',h=1.0):
    t=pcbnew.PCB_TEXT(b); t.SetText(txt); t.SetLayer(layer); t.SetTextSize(pcbnew.VECTOR2I(MM(h),MM(h))); t.SetTextThickness(MM(0.15 if h<1.3 else 0.2))
    t.SetPosition(pcbnew.VECTOR2I(MM(x),MM(y))); t.SetTextAngleDegrees(ang)
    t.SetHorizJustify({'left':pcbnew.GR_TEXT_H_ALIGN_LEFT,'center':pcbnew.GR_TEXT_H_ALIGN_CENTER,'right':pcbnew.GR_TEXT_H_ALIGN_RIGHT}[just])
    if layer==pcbnew.B_SilkS: t.SetMirrored(True)
    b.Add(t); return t
# front: port names
for i,x in enumerate([48,57,66,75]): T(f'I2C{i+1}',x,8.2)
T('I2C5 5V',83.2,20.3,ang=90); T('I2C6 5V',83.2,38.3,ang=90)
T('GPS',16.5,49.0); T('PULSE-A D2',31.75,49.0); T('PULSE-B D3',47.75,49.0); T('AUX D10',63.75,49.0)
T('FROM PWR-CTRL J5',25.9,22.6); T('PU',52,8.2)
T('GPS 3V3|5V',12.6,46.4); T('PPS',19,46.4)
T('5V',36,22.8,just='center'); 
# bottom: legend placed where free
edge=b.GetBoardEdgesBoundingBox(); edge.Inflate(-MM(1.0))
lines=['OpenCruise EXT-HUB v1.0','J1 <- PWR-CTRL J5 (2x10 ribbon, red=pin1)','I2C1-4 Qwiic: GND 3V3 SDA SCL','I2C5-6 XH: GND 5V SDA SCL (3.3V logic)',
       'GPS XH5: GND VCC RX(D6) TX(D7) PPS','PULSE/AUX XH4: 12V 5V GND IO','JP1 cut = no I2C pull-up','JP2 GPS power 1-2:3V3 2-3:5V','JP3 = GPS PPS to D10 (AUX unused)',
       '5V 0.7A / 3V3 0.4A total']
placed=[]; ymin=4
for txt in lines:
    ok=False
    for yy in [x*0.5 for x in range(int(ymin*2),110)]:
        for xx in [x*0.5 for x in range(30,170)]:
            t=pcbnew.PCB_TEXT(b); t.SetText(txt); t.SetLayer(pcbnew.B_SilkS); t.SetTextSize(pcbnew.VECTOR2I(MM(1),MM(1))); t.SetTextThickness(MM(0.15)); t.SetMirrored(True)
            t.SetPosition(pcbnew.VECTOR2I(MM(xx),MM(yy))); bb=t.GetBoundingBox()
            if not edge.Contains(bb.GetOrigin()) or not edge.Contains(bb.GetEnd()): continue
            if any(bb.Intersects(o) for o in obst+placed): continue
            b.Add(t); g=t.GetBoundingBox(); g.Inflate(MM(0.3)); placed.append(g); ok=True; ymin=yy+1.6; break
        if ok: break
    print(txt,'placed' if ok else 'NOT PLACED')
pcbnew.SaveBoard(PCB,b)
