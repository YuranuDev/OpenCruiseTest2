import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'; MM=pcbnew.FromMM
b=pcbnew.LoadBoard(PCB)
[fp.Reference().SetVisible(False) for fp in b.GetFootprints() if fp.GetReference() in ('J6','J7')]
for d in list(b.GetDrawings()):
    if d.GetClass()=='PCB_TEXT' and d.GetLayer() in (pcbnew.F_SilkS,pcbnew.B_SilkS): b.Remove(d)
def T(s,x,y,layer=pcbnew.F_SilkS,h=1.0,ang=0,just='left',bold=False):
    t=pcbnew.PCB_TEXT(b); t.SetText(s); t.SetLayer(layer); t.SetTextSize(pcbnew.VECTOR2I(MM(h),MM(h))); t.SetTextThickness(MM(0.15 if h<1.3 else 0.2))
    t.SetPosition(pcbnew.VECTOR2I(MM(x),MM(y))); t.SetTextAngleDegrees(ang)
    t.SetHorizJustify({'left':pcbnew.GR_TEXT_H_ALIGN_LEFT,'center':pcbnew.GR_TEXT_H_ALIGN_CENTER,'right':pcbnew.GR_TEXT_H_ALIGN_RIGHT}[just])
    if layer==pcbnew.B_SilkS: t.SetMirrored(True)
    b.Add(t)
F=pcbnew.F_SilkS; B=pcbnew.B_SilkS
T('OpenCruise PWR-CTRL v1.0',27,3.2,h=1.3)
T('1:+B 2:ACC 3,4:GND',1.5,20.4)
T('1:12V OUT 2:GND',1.5,37.7)
T('DIAG K/CH/CL/G',1.2,76.4)
T('EXT 2x10',102.4,56,ang=90,just='center')
T('J6 I2C',81,64.6,just='center'); T('J7 I2C',91,64.6,just='center')
T('VSW',27,46.4,just='center'); T('5V',77,22.5,just='center')
A=['J5 EXT: 1 ACC 2 HOLD! 3 D2 4 D3 5 SDA','6 SCL 7 D6 8 D7 9 TX 10 RX 11 D10','12 3V3 13 5V 14 12V 15-20 GND']
Bk=['JP1 CAN-TX JP4/5 CAN|KL JP6 KL-TX','JP7 KL-DIR JP2 PC-PWR JP3 I2C-PU','J8/9: 12V 5V GND D2/D3','HOLD low = PC OFF']
for i,s_ in enumerate(A): T(s_,99,24.5+1.8*i,layer=B,just='left')
for i,s_ in enumerate(Bk): T(s_,60,60+1.8*i,layer=B,just='left')
pcbnew.SaveBoard(PCB,b)
print('silk ok')
