"""gnd_reinforce.py <board> : add GND vias where the plane continuity / return path needs them
 (a) a 'fence' along both sides of long bottom-layer tracks (bridges the slot they cut in the bottom plane)
 (b) around DC-DC / LDO / 7A-path GND pads (ties the top hot-loop GND to the bottom plane)
 (c) into GND copper areas that are tied to the other layer at only one point
Vias are placed only where both GND pours cover the via with full clearance, never in pads or under parts."""
import sys, math, os
import pcbnew
PCB = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'
b = pcbnew.LoadBoard(PCB); MMf = pcbnew.FromMM; MM = pcbnew.ToMM
F, B = pcbnew.F_Cu, pcbnew.B_Cu
gnd = b.FindNet('GND')
zones = {z.GetLayer(): z for z in b.Zones() if z.GetNetCode() == gnd.GetNetCode()}
for z in zones.values(): z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_NEVER)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
fF = zones[F].GetFilledPolysList(F); fB = zones[B].GetFilledPolysList(B)
need = MMf(0.85 / 2 + 0.35)
def clear(poly, x, y):
    p = pcbnew.VECTOR2I(MMf(x), MMf(y))
    if not poly.Contains(p): return False
    for a in range(0, 360, 30):
        if not poly.Contains(pcbnew.VECTOR2I(int(p.x + need * math.cos(math.radians(a))), int(p.y + need * math.sin(math.radians(a))))): return False
    return True
holes = [(MM(t.GetPosition().x), MM(t.GetPosition().y)) for t in b.GetTracks() if t.GetClass() == 'PCB_VIA']
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.GetDrillSizeX() > 0: holes.append((MM(p.GetPosition().x), MM(p.GetPosition().y)))
crt = [fp.GetCourtyard(pcbnew.F_CrtYd) for fp in b.GetFootprints() if fp.GetCourtyard(pcbnew.F_CrtYd).OutlineCount()]
padbb = []
for fp in b.GetFootprints():
    for p in fp.Pads():
        r = p.GetBoundingBox(); r.Inflate(MMf(0.4)); padbb.append(r)
added = []
def try_add(x, y, allow_courtyard=False, mind=1.6):
    if any(math.hypot(x - hx, y - hy) < mind for hx, hy in holes + added): return False
    p = pcbnew.VECTOR2I(MMf(x), MMf(y))
    if any(r.Contains(p) for r in padbb): return False
    if not allow_courtyard and any(c.Collide(p, MMf(0.3)) for c in crt): return False
    if not (clear(fF, x, y) and clear(fB, x, y)): return False
    added.append((x, y)); return True
cnt = {'fence': 0, 'dcdc': 0, 'island': 0}
# (a) fence along long bottom tracks
for t in b.GetTracks():
    if t.GetClass() != 'PCB_TRACK' or t.GetLayer() != B or t.GetNetCode() == gnd.GetNetCode(): continue
    L = MM(t.GetLength())
    if L < 10: continue
    s, e = t.GetStart(), t.GetEnd(); x1, y1, x2, y2 = MM(s.x), MM(s.y), MM(e.x), MM(e.y)
    ux, uy = (x2 - x1) / L, (y2 - y1) / L; nx, ny = -uy, ux
    off = MM(t.GetWidth()) / 2 + 0.95
    k = 2.0
    while k < L - 1.0:
        for sgn in (1, -1):
            for extra in (0, 0.5, 1.0):
                if try_add(x1 + ux * k + nx * sgn * (off + extra), y1 + uy * k + ny * sgn * (off + extra)):
                    cnt['fence'] += 1; break
        k += 5.0
# (b) power GND pads
fps = {fp.GetReference(): fp for fp in b.GetFootprints()}
for ref in ['C4', 'C5', 'U1', 'D11', 'C6', 'C7', 'C40', 'C41', 'U8', 'D12', 'C42', 'C43', 'U9', 'C45', 'C46', 'TVS1', 'C1', 'C2', 'C3', 'C9', 'C13']:
    for p in fps[ref].Pads():
        if p.GetNetCode() != gnd.GetNetCode(): continue
        px, py = MM(p.GetPosition().x), MM(p.GetPosition().y)
        r0 = max(MM(p.GetSize().x), MM(p.GetSize().y)) / 2 + 0.9
        got = 0
        for r in (r0, r0 + 0.8, r0 + 1.6):
            for a in range(0, 360, 30):
                if got >= 2: break
                if try_add(px + r * math.cos(math.radians(a)), py + r * math.sin(math.radians(a)), allow_courtyard=True):
                    got += 1; cnt['dcdc'] += 1
# (c) weakly tied islands (both layers)
ties = [pcbnew.VECTOR2I(MMf(x), MMf(y)) for x, y in holes + added]  # via/THT centres
for poly in (fF, fB):
    for i in range(poly.OutlineCount()):
        sub = pcbnew.SHAPE_POLY_SET(); sub.AddOutline(poly.Outline(i))
        for h in range(poly.HoleCount(i)): sub.AddHole(poly.CHole(i, h))
        if abs(poly.Outline(i).Area()) / 1e12 > 2000: continue
        n = sum(1 for p in ties if sub.Collide(p, MMf(0.8)))
        if n >= 2: continue
        bb = poly.Outline(i).BBox()
        y = MM(bb.GetTop()) + 0.5
        while y < MM(bb.GetBottom()) and n < 2:
            x = MM(bb.GetLeft()) + 0.5
            while x < MM(bb.GetRight()) and n < 2:
                if sub.Contains(pcbnew.VECTOR2I(MMf(x), MMf(y))) and try_add(x, y, allow_courtyard=True, mind=1.0):
                    ties.append(pcbnew.VECTOR2I(MMf(x), MMf(y)))
                    n += 1; cnt['island'] += 1
                x += 0.25
            y += 0.25
for x, y in added:
    v = pcbnew.PCB_VIA(b); v.SetPosition(pcbnew.VECTOR2I(MMf(x), MMf(y))); v.SetWidth(MMf(0.85)); v.SetDrill(MMf(0.3)); v.SetNet(gnd); v.SetLocked(True); b.Add(v)
for z in zones.values(): z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(PCB, b)
print('added GND vias', cnt)
os._exit(0)
