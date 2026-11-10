import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'; MM=pcbnew.FromMM
b=pcbnew.LoadBoard(PCB)
for d in list(b.GetDrawings()):
    if d.GetClass()=='PCB_TEXT' and d.GetLayer() in (pcbnew.F_SilkS,pcbnew.B_SilkS): b.Remove(d)
def T(s,x,y,layer=pcbnew.F_SilkS,h=1.0,ang=0,just='left',bold=False):
    t=pcbnew.PCB_TEXT(b); t.SetText(s); t.SetLayer(layer); t.SetTextSize(pcbnew.VECTOR2I(MM(h),MM(h))); t.SetTextThickness(MM(0.15 if h<1.3 else 0.2))
    t.SetPosition(pcbnew.VECTOR2I(MM(x),MM(y))); t.SetTextAngleDegrees(ang)
    t.SetHorizJustify({'left':pcbnew.GR_TEXT_H_ALIGN_LEFT,'center':pcbnew.GR_TEXT_H_ALIGN_CENTER,'right':pcbnew.GR_TEXT_H_ALIGN_RIGHT}[just])
    if layer==pcbnew.B_SilkS: t.SetMirrored(True)
    b.Add(t)
F=pcbnew.F_SilkS; B=pcbnew.B_SilkS
T('OpenCruise PWR-CTRL v2.0',27,3.2,h=1.3)
T('1:+B 2:ACC 3,4:GND',1.5,20.4)
T('1:12V OUT 2:GND',1.5,37.7)
T('DIAG K/CH/CL/G',1.2,76.4)
T('EXT 2x10',102.4,56,ang=90,just='center')
T('VSW',25.6,46.6,just='center'); T('5V',77,22.5,just='center')
T('5VS',117.6,30.9,just='right'); T('3V3S',117.6,35.9,just='right')
# ports: right edge = I2C (sensors)
for i,(ref,y) in enumerate([('J6',18),('J7',33.4),('J12',48.8),('J13',64.2),('J14',79.6)]):
    T(f'I2C{i+1} '+('5V' if i==4 else '3V3'),155.6,y-3.75,ang=90,just='center')
# bottom edge = signal ports
T('AUX',86.65,81.2,just='center')
for txt,x in [('PC BTN',74.25),('PULSE-B D3',101.55),('PULSE-A D2',116.45),('GPS',132.65),('I2C6 5V',148.85)]:
    T(txt,x,82.6,just='center')
T('GPS 3V3|5V',126,77.2,just='center'); T('PPS',132,77.2,just='center')
pcbnew.SaveBoard(PCB,b)
print('silk front ok')
import os; os._exit(0)
