import sys,subprocess,os; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'; WD='/home/claude/pcb/pwrctrl/route'; os.makedirs(WD,exist_ok=True)
JAVA='/usr/lib/jvm/java-25-openjdk-amd64/bin/java'; FR='/home/claude/tools/fr.jar'
MM=pcbnew.FromMM
def P(x,y): return pcbnew.VECTOR2I(MM(x),MM(y))
b=pcbnew.LoadBoard(PCB)
# ---------- net classes ----------
ns=b.GetDesignSettings().m_NetSettings
def nc(name,tw,cl,vd=0.85,vh=0.3):
    c=pcbnew.NETCLASS(name); c.SetTrackWidth(MM(tw)); c.SetClearance(MM(cl)); c.SetViaDiameter(MM(vd)); c.SetViaDrill(MM(vh)); return c
d=ns.GetDefaultNetclass(); d.SetTrackWidth(MM(0.25)); d.SetClearance(MM(0.25)); d.SetViaDiameter(MM(0.85)); d.SetViaDrill(MM(0.3))
CLASSES={'PWR_1A':(0.8,0.25,['VBAT_IN','VIN5','SW5','V5REG','ACC_IN','VSW_EXT','SW6','+5VS']),
         'PWR_05A':(0.6,0.25,['VSW','+5V','+3V3S','GPS_VCC','GND']),
         'SIG_PORT':(0.25,0.21,['SDA','SCL','P_D2','P_D3','P_D6','P_D7','P_D10','GPS_PPS']),
         'PWR_LOW':(0.4,0.25,['+3V3','COIL_P','COIL_N','KPU','KLINE','KDRN'])}
ns.ClearNetclassPatternAssignments()
for name,(tw,cl,nets) in CLASSES.items():
    ns.SetNetclass(name,nc(name,tw,cl))
    for n in nets: ns.SetNetclassPatternAssignment(n,name)
ns.RecomputeEffectiveNetclasses()
b.SynchronizeNetsAndNetClasses(True)
# ---------- remove old copper ----------
for t in list(b.GetTracks()): b.Remove(t)
for z in list(b.Zones()): b.Remove(z)
net=lambda n: b.FindNet(n)
def trk(pts,width,layer,netname):
    for (x1,y1),(x2,y2) in zip(pts,pts[1:]):
        t=pcbnew.PCB_TRACK(b); t.SetStart(P(x1,y1)); t.SetEnd(P(x2,y2)); t.SetWidth(MM(width)); t.SetLayer(layer); t.SetNet(net(netname)); t.SetLocked(True); b.Add(t)
# ---------- 7 A path, hand-placed (3.0 mm @ 2 oz) ----------
B=pcbnew.B_Cu; F=pcbnew.F_Cu
trk([(14.9,16),(14.9,19),(16.7,20.8),(25.7,20.8),(26,20.5)],3.0,B,'VBAT_IN')      # J1.1 -> K1.14 (lower pad)
trk([(26,20.5),(26,13)],3.0,B,'VBAT_IN')                                           # both K1.14 pins
trk([(31,13),(31,28.2)],3.0,B,'VSW')                                               # K1.13 pins -> TVS1 K
trk([(31,28.2),(19,28.2),(14.9,32.3),(14.9,33)],3.0,B,'VSW')                        # -> J2.1 (to DFR0946)
trk([(20.4,11.8),(20.4,33)],3.0,F,'GND')                                           # J1.3/J1.4 <-> J2.2 return
pcbnew.SaveBoard(PCB,b)
# ---------- autoroute ----------
dsn=f'{WD}/pwrctrl.dsn'; ses=f'{WD}/pwrctrl.ses'
assert pcbnew.ExportSpecctraDSN(b,dsn)
# orthogonal (Manhattan) routing: top = horizontal, bottom = vertical; 90-degree corners are chamfered to 45 afterwards (chamfer.py)
_s=open(dsn).read(); _s=_s.replace('    (via "Via[0-1]_850:300_um")','    (snap_angle ninety_degree)\n    (via "Via[0-1]_850:300_um")',1); open(dsn,'w').write(_s)
r=subprocess.run([JAVA,'-jar',FR,'-de',dsn,'-do',ses,'-mp','300','--gui.enabled=false','-mt','4','--router.scoring.via_costs=30','--router.scoring.undesired_direction_trace_cost=2.5','--router.optimizer.enabled=true','--router.optimizer.improvement_threshold=0.0005','--router.optimizer.max_passes=60'],capture_output=True,text=True,timeout=1500)
print(r.stdout[-1500:]); print(r.stderr[-800:])
b=pcbnew.LoadBoard(PCB)
assert pcbnew.ImportSpecctraSES(b,ses)
for t in b.GetTracks():
    if t.GetClass()=='PCB_TRACK' and t.GetWidth()<MM(0.2): t.SetWidth(MM(0.2))
pcbnew.SaveBoard(PCB,b)
print('routed tracks',len(b.GetTracks()))
