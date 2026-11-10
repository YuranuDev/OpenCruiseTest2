import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
PCB='/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'
MM=pcbnew.FromMM
b=pcbnew.LoadBoard(PCB)
for z in list(b.Zones()): b.Remove(z)
bb=b.GetBoardEdgesBoundingBox(); W=pcbnew.ToMM(bb.GetWidth()); H=pcbnew.ToMM(bb.GetHeight())
def zone(layer,net,prio=0):
    z=pcbnew.ZONE(b); z.SetLayer(layer); z.SetNet(b.FindNet(net)); z.SetAssignedPriority(prio)
    o=z.Outline(); o.NewOutline()
    for x,y in [(0.3,0.3),(W-0.3,0.3),(W-0.3,H-0.3),(0.3,H-0.3)]: o.Append(MM(x),MM(y))
    z.SetLocalClearance(MM(0.3)); z.SetMinThickness(MM(0.25))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THT_THERMAL); z.SetThermalReliefGap(MM(0.3)); z.SetThermalReliefSpokeWidth(MM(0.6))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_NEVER)   # keep islands so stitch.py can tie them to the other layer
    b.Add(z); return z
zone(pcbnew.F_Cu,'GND'); zone(pcbnew.B_Cu,'GND')
# 7 A return: the GND pins of J1 (3,4) and J2 (2) are tied solid to both pours (no thermal relief)
FULL_PADS=[('J1','3'),('J1','4'),('J2','2')]
for fp in b.GetFootprints():
    for p_ in fp.Pads():
        if (fp.GetReference(),p_.GetNumber()) in FULL_PADS: p_.SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_FULL)
f=pcbnew.ZONE_FILLER(b); f.Fill(b.Zones())
pcbnew.SaveBoard(PCB,b)
print('zones filled')
