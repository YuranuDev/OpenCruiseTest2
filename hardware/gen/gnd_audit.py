"""gnd_audit.py <board> : GND plane continuity / return-path / via audit (prints a report)"""
import sys, math, collections, os
import pcbnew
PCB = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'
b = pcbnew.LoadBoard(PCB); MM = pcbnew.ToMM
F, B = pcbnew.F_Cu, pcbnew.B_Cu
gnd = b.FindNet('GND').GetNetCode()
zones = {z.GetLayer(): z for z in b.Zones() if z.GetNetCode() == gnd}
vias = [t for t in b.GetTracks() if t.GetClass() == 'PCB_VIA']
gvias = [v for v in vias if v.GetNetCode() == gnd]
tht = [p for fp in b.GetFootprints() for p in fp.Pads() if p.GetNetCode() == gnd and p.GetDrillSizeX() > 0]
smd = {L: [p for fp in b.GetFootprints() for p in fp.Pads() if p.GetNetCode() == gnd and p.GetDrillSizeX() == 0 and p.IsOnLayer(L)] for L in (F, B)}
ties = [(v.GetPosition(), v.GetWidth(pcbnew.F_Cu) // 2) for v in gvias] + [(p.GetPosition(), max(p.GetSize().x, p.GetSize().y) // 2) for p in tht]
bb = b.GetBoardEdgesBoundingBox(); A = MM(bb.GetWidth()) * MM(bb.GetHeight())
print(f'board {MM(bb.GetWidth()):.0f} x {MM(bb.GetHeight()):.0f} mm = {A:.0f} mm2')
polys = {}
for L, name in ((F, 'F.Cu'), (B, 'B.Cu')):
    fill = zones[L].GetFilledPolysList(L)
    n = fill.OutlineCount(); area = fill.Area() / 1e12
    print(f'\n[{name}] GND fill: {n} separate copper areas, {area:.0f} mm2 ({area / A * 100:.0f}% of board)')
    rows = []
    for i in range(n):
        o = fill.Outline(i); ar = abs(o.Area()) / 1e12
        sub = pcbnew.SHAPE_POLY_SET(); sub.AddOutline(o)
        for h in range(fill.HoleCount(i)): sub.AddHole(fill.CHole(i, h))
        nt = sum(1 for p, r in ties if sub.Collide(p, r))
        ns = sum(1 for p in smd[L] if sub.Collide(p.GetPosition(), 0))
        c = o.BBox().Centre()
        rows.append((ar, nt, ns, MM(c.x), MM(c.y)))
    rows.sort(reverse=True)
    polys[name] = rows
    for ar, nt, ns, x, y in rows[:3]:
        print(f'   area {ar:7.0f} mm2  layer-ties {nt:3d}  SMD GND pads {ns}')
    small = [r for r in rows if r[0] < rows[0][0]]
    weak = [r for r in small if r[1] < 2]
    print(f'   other areas: {len(small)}  (all tied to the other layer: {all(r[1] >= 1 for r in small)}; with only one tie: {len(weak)})')
    for ar, nt, ns, x, y in weak:
        print(f'     single-tie area {ar:.1f} mm2 at ({x:.1f},{y:.1f}) ties={nt} smd={ns}')
# via breakdown
POWER = {'VSW', 'VBAT_IN', 'VIN5', 'SW5', 'V5REG', 'ACC_IN', 'VSW_EXT', 'SW6', '+5VS', '+5V', '+3V3', '+3V3S', 'GPS_VCC', 'COIL_P', 'KPU'}
cat = collections.Counter()
for v in vias:
    n = v.GetNetname()
    if v.GetNetCode() == gnd: cat['GND stitching (placed on a grid)' if v.IsLocked() else 'GND (placed by router / pad tie)'] += 1
    elif n in POWER: cat['power: ' + n] += 1
    else: cat['signal'] += 1
print('\n[vias] total', len(vias))
for k, c in sorted(cat.items(), key=lambda x: -x[1]): print(f'   {c:4d}  {k}')
# long bottom-layer tracks = slots in the bottom plane
print('\n[B.Cu tracks longer than 15 mm (they cut the bottom plane)]')
segs = collections.defaultdict(float)
for t in b.GetTracks():
    if t.GetClass() == 'PCB_TRACK' and t.GetLayer() == B and t.GetNetCode() != gnd:
        segs[t.GetNetname()] += MM(t.GetLength())
for t in sorted([t for t in b.GetTracks() if t.GetClass() == 'PCB_TRACK' and t.GetLayer() == B and t.GetNetCode() != gnd], key=lambda t: -t.GetLength())[:12]:
    if MM(t.GetLength()) < 15: break
    s, e = t.GetStart(), t.GetEnd()
    # GND ties within 4 mm of the segment on each side -> return current can hop to the top plane
    near = 0
    for p, _r in ties:
        # distance point-segment
        px, py = MM(p.x), MM(p.y); x1, y1, x2, y2 = MM(s.x), MM(s.y), MM(e.x), MM(e.y)
        dx, dy = x2 - x1, y2 - y1; L2 = dx * dx + dy * dy
        u = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / L2)) if L2 else 0
        if math.hypot(px - (x1 + u * dx), py - (y1 + u * dy)) < 4: near += 1
    print(f'   {t.GetNetname():10s} {MM(t.GetLength()):5.1f} mm ({x1:.0f},{y1:.0f})-({x2:.0f},{y2:.0f})  GND ties within 4 mm: {near}')
# DC-DC hot loops: GND pads of input caps / IC / catch diode -> same top copper area? vias nearby?
print('\n[DC-DC / power GND return]')
Ff = zones[F].GetFilledPolysList(F)
def area_id(pos):
    for i in range(Ff.OutlineCount()):
        sub = pcbnew.SHAPE_POLY_SET(); sub.AddOutline(Ff.Outline(i))
        for h in range(Ff.HoleCount(i)): sub.AddHole(Ff.CHole(i, h))
        if sub.Collide(pos, 0): return i
    return None
groups = {'U1 (5V for MCU)': ['C4', 'C5', 'U1', 'D11', 'C6', 'C7'], 'U8 (5VS sensors)': ['C40', 'C41', 'U8', 'D12', 'C42', 'C43'],
          'U9 (3V3S LDO)': ['U9', 'C45', 'C46'], '7A path (J1/J2/TVS1/C1-C3)': ['J1', 'J2', 'TVS1', 'C1', 'C2', 'C3']}
fps = {fp.GetReference(): fp for fp in b.GetFootprints()}
for gname, refs in groups.items():
    ids = set(); pads = []
    for r in refs:
        for p in fps[r].Pads():
            if p.GetNetCode() == gnd:
                pads.append((r, p)); ids.add(area_id(p.GetPosition()) if p.IsOnLayer(F) else 'THT')
    xs = [MM(p.GetPosition().x) for _, p in pads]; ys = [MM(p.GetPosition().y) for _, p in pads]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    nv = sum(1 for v in gvias if math.hypot(MM(v.GetPosition().x) - cx, MM(v.GetPosition().y) - cy) < 8)
    print(f'   {gname:28s} GND pads {len(pads):2d}, top copper areas {sorted(map(str, ids))}, GND vias within 8 mm: {nv}')
os._exit(0)
