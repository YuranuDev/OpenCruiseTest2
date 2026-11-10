import sys,subprocess,os; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pulsein/pulsein.kicad_pcb'; WD='/home/claude/pcb/pulsein/route'; os.makedirs(WD,exist_ok=True)
JAVA='/usr/lib/jvm/java-25-openjdk-amd64/bin/java'; FR='/home/claude/tools/fr.jar'
MM=pcbnew.FromMM
b=pcbnew.LoadBoard(PCB)
ns=b.GetDesignSettings().m_NetSettings
def nc(name,tw,cl):
    c=pcbnew.NETCLASS(name); c.SetTrackWidth(MM(tw)); c.SetClearance(MM(cl)); c.SetViaDiameter(MM(0.85)); c.SetViaDrill(MM(0.3)); return c
d=ns.GetDefaultNetclass(); d.SetTrackWidth(MM(0.3)); d.SetClearance(MM(0.21)); d.SetViaDiameter(MM(0.85)); d.SetViaDrill(MM(0.3))
ns.ClearNetclassPatternAssignments()
for name,(tw,cl,nets) in {'PWR':(0.8,0.25,['+12V','GND']),'PWR5':(0.5,0.25,['+5V','+3V3'])}.items():
    ns.SetNetclass(name,nc(name,tw,cl))
    for n in nets: ns.SetNetclassPatternAssignment(n,name)
ns.RecomputeEffectiveNetclasses(); b.SynchronizeNetsAndNetClasses(True)
for t in list(b.GetTracks()): b.Remove(t)
for z in list(b.Zones()): b.Remove(z)
pcbnew.SaveBoard(PCB,b)
dsn=f'{WD}/pulsein.dsn'; ses=f'{WD}/pulsein.ses'
assert pcbnew.ExportSpecctraDSN(b,dsn)
r=subprocess.run([JAVA,'-jar',FR,'-de',dsn,'-do',ses,'-mp','200','--gui.enabled=false','-mt','4'],capture_output=True,text=True,timeout=900)
print(r.stdout[-400:])
b=pcbnew.LoadBoard(PCB)
assert pcbnew.ImportSpecctraSES(b,ses)
for t in b.GetTracks():
    if t.GetClass()=='PCB_TRACK' and t.GetWidth()<MM(0.25): t.SetWidth(MM(0.25))
# GND pour both sides
bb=b.GetBoardEdgesBoundingBox(); W=pcbnew.ToMM(bb.GetWidth()); H=pcbnew.ToMM(bb.GetHeight())
for layer in (pcbnew.F_Cu,pcbnew.B_Cu):
    z=pcbnew.ZONE(b); z.SetLayer(layer); z.SetNet(b.FindNet('GND'))
    o=z.Outline(); o.NewOutline()
    for x,y in [(0.3,0.3),(W-0.3,0.3),(W-0.3,H-0.3),(0.3,H-0.3)]: o.Append(MM(x),MM(y))
    z.SetLocalClearance(MM(0.3)); z.SetMinThickness(MM(0.25))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THT_THERMAL); z.SetThermalReliefGap(MM(0.3)); z.SetThermalReliefSpokeWidth(MM(0.6))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS); b.Add(z)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
# silkscreen text
MMv=lambda x,y: pcbnew.VECTOR2I(MM(x),MM(y))
def T(s,x,y,layer=pcbnew.F_SilkS,h=1.0,ang=0,just='center'):
    t=pcbnew.PCB_TEXT(b); t.SetText(s); t.SetLayer(layer); t.SetTextSize(MMv(h,h)); t.SetTextThickness(MM(0.15 if h<1.3 else 0.2))
    t.SetPosition(MMv(x,y)); t.SetTextAngleDegrees(ang)
    t.SetHorizJustify({'left':pcbnew.GR_TEXT_H_ALIGN_LEFT,'center':pcbnew.GR_TEXT_H_ALIGN_CENTER,'right':pcbnew.GR_TEXT_H_ALIGN_RIGHT}[just])
    if layer==pcbnew.B_SilkS: t.SetMirrored(True)
    b.Add(t)
B=pcbnew.B_SilkS
pcbnew.SaveBoard(PCB,b)
pcbnew.SaveBoard(PCB,b)
print('tracks',len(b.GetTracks()))
