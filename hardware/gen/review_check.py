import sys, math, collections, os
import pcbnew
b = pcbnew.LoadBoard('/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'); MM = pcbnew.ToMM; MMf = pcbnew.FromMM
F, B = pcbnew.F_Cu, pcbnew.B_Cu
gnd = b.FindNet('GND').GetNetCode()
trk = [t for t in b.GetTracks() if t.GetClass() == 'PCB_TRACK']
POWER = {'VSW','VBAT_IN','VIN5','SW5','V5REG','ACC_IN','VSW_EXT','SW6','+5VS','+5V','+3V3','+3V3S','GPS_VCC','COIL_P','KPU','GND'}
# ---- A: long parallel runs ----
def seg(t): s, e = t.GetStart(), t.GetEnd(); return MM(s.x), MM(s.y), MM(e.x), MM(e.y)
par = collections.defaultdict(float); minpitch = {}
longs = [t for t in trk if MM(t.GetLength()) > 8]
for i, a in enumerate(longs):
    ax1, ay1, ax2, ay2 = seg(a)
    for c in longs[i + 1:]:
        if c.GetLayer() != a.GetLayer() or c.GetNetCode() == a.GetNetCode(): continue
        cx1, cy1, cx2, cy2 = seg(c)
        if abs(ay1 - ay2) < 1e-3 and abs(cy1 - cy2) < 1e-3:     # both horizontal
            d = abs(ay1 - cy1); lo = max(min(ax1, ax2), min(cx1, cx2)); hi = min(max(ax1, ax2), max(cx1, cx2))
        elif abs(ax1 - ax2) < 1e-3 and abs(cx1 - cx2) < 1e-3:
            d = abs(ax1 - cx1); lo = max(min(ay1, ay2), min(cy1, cy2)); hi = min(max(ay1, ay2), max(cy1, cy2))
        else: continue
        if d < 1.6 and hi - lo > 5:
            k = tuple(sorted((a.GetNetname(), c.GetNetname()))) + (a.GetLayerName(),)
            par[k] += hi - lo
            pitch = d
            minpitch[k] = min(minpitch.get(k, 99), pitch)
print('[A] parallel runs (same layer, centre distance < 1.6 mm, > 5 mm overlap)')
for k, L in sorted(par.items(), key=lambda x: -x[1])[:25]:
    kind = '+'.join('P' if n in POWER else 'S' for n in k[:2])
    print(f'   {k[0]:>10s} | {k[1]:<10s} {k[2]}  {L:5.1f} mm  pitch {minpitch[k]:.2f} mm  [{kind}]')
# GND under the central bundle: sample bottom fill under every long top-layer signal segment
zB = [z for z in b.Zones() if z.GetLayer() == B][0].GetFilledPolysList(B)
cov = []
for t in trk:
    if t.GetLayer() != F or MM(t.GetLength()) < 15 or t.GetNetname() in ('GND',): continue
    x1, y1, x2, y2 = seg(t); n = int(MM(t.GetLength()) / 1.0); ok = 0
    for i in range(n + 1):
        x = x1 + (x2 - x1) * i / n; y = y1 + (y2 - y1) * i / n
        if zB.Contains(pcbnew.VECTOR2I(MMf(x), MMf(y))): ok += 1
    cov.append((t.GetNetname(), MM(t.GetLength()), ok / (n + 1) * 100, (x1, y1, x2, y2)))
print('\n[A2] bottom GND directly under long top-layer tracks (>=15 mm): % of length with GND underneath')
for n, L, c, xy in sorted(cov, key=lambda x: x[2])[:15]:
    print(f'   {n:10s} {L:5.1f} mm  {c:5.1f} %   ({xy[0]:.0f},{xy[1]:.0f})-({xy[2]:.0f},{xy[3]:.0f})')
print(f'   all {len(cov)} long top tracks: mean {sum(c for _,_,c,_ in cov)/len(cov):.0f} %, min {min(c for _,_,c,_ in cov):.0f} %')
# ---- B: power widths vs current ----
CUR = {'VBAT_IN': 7, 'VSW': 7, 'VSW_EXT': 1.1, '+5VS': 0.7, 'SW6': 0.8, 'SW5': 0.8, 'V5REG': 0.8, 'VIN5': 0.5, '+5V': 0.7, '+3V3S': 0.4, '+3V3': 0.25, 'ACC_IN': 0.5, 'GPS_VCC': 0.1, 'COIL_P': 0.05, 'KPU': 0.03, 'GND': 7}
def ipc(w_mm, oz=2, dT=10):   # IPC-2221 external
    A = w_mm / 0.0254 * 1.378 * oz      # mil^2
    return 0.048 * dT ** 0.44 * A ** 0.725
print('\n[B] power nets: narrowest track vs current (IPC-2221 external, 2 oz, +10 C)')
for n, I in CUR.items():
    ws = sorted(set(round(MM(t.GetWidth()), 2) for t in trk if t.GetNetname() == n))
    if not ws: continue
    wmin = ws[0]; Lmin = sum(MM(t.GetLength()) for t in trk if t.GetNetname() == n and round(MM(t.GetWidth()), 2) == wmin)
    print(f'   {n:8s} I={I:4.2f} A  widths {ws}  narrowest {wmin} mm ({Lmin:.1f} mm long) -> {ipc(wmin):.2f} A capacity')
# 7A path detail
print('   7A path tracks (hand placed):', sorted(set((t.GetNetname(), round(MM(t.GetWidth()),1)) for t in trk if t.IsLocked())))
# ---- C: DC-DC geometry ----
fps = {fp.GetReference(): fp for fp in b.GetFootprints()}
def pad(ref, num): return [p for p in fps[ref].Pads() if p.GetNumber() == num][0]
def dist(p, q): return MM(math.hypot(p.GetPosition().x - q.GetPosition().x, p.GetPosition().y - q.GetPosition().y))
print('\n[C] DC-DC layout (XL7015: pin1 VIN, pin2 SW, pin3/5/6(tab) GND, pin4 FB)')
for name, U, Cb, Ce, D, Lr, Rfb, sw in [('U1 5V MCU', 'U1', 'C5', 'C4', 'D11', 'L1', 'R50', 'SW5'), ('U8 5VS', 'U8', 'C41', 'C40', 'D12', 'L2', 'R52', 'SW6')]:
    vin = pad(U, '1'); swp = pad(U, '2'); g = pad(U, '6'); fb = pad(U, '4')
    cin_v = [p for p in fps[Cb].Pads() if p.GetNetCode() != gnd][0]; cin_g = [p for p in fps[Cb].Pads() if p.GetNetCode() == gnd][0]
    ce_v = [p for p in fps[Ce].Pads() if p.GetNetCode() != gnd][0]; ce_g = [p for p in fps[Ce].Pads() if p.GetNetCode() == gnd][0]
    dk = [p for p in fps[D].Pads() if p.GetNetname() == sw][0]; da = [p for p in fps[D].Pads() if p.GetNetCode() == gnd][0]
    l1 = [p for p in fps[Lr].Pads() if p.GetNetname() == sw][0]
    swarea = sum(MM(t.GetLength()) * MM(t.GetWidth()) for t in trk if t.GetNetname() == sw)
    swlen = sum(MM(t.GetLength()) for t in trk if t.GetNetname() == sw)
    # hot loop polygon: Cin+ -> VIN -> SW -> D cathode -> D anode -> Cin-
    pts = [cin_v, vin, swp, dk, da, cin_g]
    xy = [(MM(p.GetPosition().x), MM(p.GetPosition().y)) for p in pts]
    area = abs(sum(xy[i][0] * xy[(i + 1) % 6][1] - xy[(i + 1) % 6][0] * xy[i][1] for i in range(6))) / 2
    fbd = min(dist(fb, q) for q in fps[Rfb].Pads())
    fb_to_L = min(MM(math.hypot(t.GetStart().x - l1.GetPosition().x, t.GetStart().y - l1.GetPosition().y)) for t in trk if t.GetNetname() in ('FB6' if U == 'U8' else 'FB5',)) if any(t.GetNetname() in ('FB6','FB5') for t in trk) else -1
    print(f'   {name}: Cin(ceramic {Cb}) VIN-pad {dist(cin_v, vin):.1f} mm, GND-pad to IC GND tab {dist(cin_g, g):.1f} mm; bulk {Ce} VIN {dist(ce_v, vin):.1f} mm')
    print(f'      catch diode {D}: cathode to SW pin {dist(dk, swp):.1f} mm, anode to Cin GND {dist(da, cin_g):.1f} mm; inductor SW pad to SW pin {dist(l1, swp):.1f} mm')
    print(f'      hot-loop polygon (Cin->VIN->SW->D->Cin) approx {area:.0f} mm2; SW copper tracks {swlen:.1f} mm long, {swarea:.1f} mm2')
    print(f'      FB divider {Rfb} to FB pin {fbd:.1f} mm; nearest FB track point to inductor SW pad {fb_to_L:.1f} mm')
# ---- D: clearance distribution in dense areas ----
print('\n[D] copper clearance actually used (pairs closer than 0.25 mm), by region')
items = []
for t in b.GetTracks():
    items.append(t)
pads = [p for fp in b.GetFootprints() for p in fp.Pads()]
def shp(o, L): return o.GetEffectiveShape(L)
regions = {'vehicle bus (left bottom)': (0, 52, 45, 91), 'XIAO U2 (bottom centre)': (45, 55, 70, 91), 'J5 / centre bundle': (68, 44, 114, 82), 'whole board': (0, 0, 165, 91)}
objs = [(o, L) for o in trk if True for L in [o.GetLayer()]] + [(p, L) for p in pads for L in (F, B) if p.IsOnLayer(L)]
import itertools
close = collections.Counter(); mins = {}
grid = collections.defaultdict(list)
for o, L in objs:
    bb = o.GetBoundingBox(); cx, cy = MM(bb.Centre().x), MM(bb.Centre().y)
    grid[(L, int(cx // 5), int(cy // 5))].append((o, L, cx, cy))
seen = set()
for (L, gx, gy), lst in grid.items():
    cand = []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1): cand += grid.get((L, gx + dx, gy + dy), [])
    for o, _, cx, cy in lst:
        so = shp(o, L)
        for q, _, qx, qy in cand:
            if q is o or q.GetNetCode() == o.GetNetCode(): continue
            key = (min(id(o), id(q)), max(id(o), id(q)), L)
            if key in seen: continue
            seen.add(key)
            ob, qb = o.GetBoundingBox(), q.GetBoundingBox(); ob.Inflate(MMf(0.4))
            if not ob.Intersects(qb): continue
            d = so.GetClearance(shp(q, L)) if hasattr(so, 'GetClearance') else None
            if d is None: continue
            d = MM(d)
            for rn, (x0, y0, x1, y1) in regions.items():
                if x0 <= cx < x1 and y0 <= cy < y1:
                    mins[rn] = min(mins.get(rn, 9), d)
                    if d < 0.25: close[rn] += 1
for rn in regions: print(f'   {rn:28s} minimum {mins.get(rn, 0):.3f} mm, pairs below 0.25 mm: {close[rn]}')
# ---- E: vias / thermal ----
v = [t for t in b.GetTracks() if t.GetClass() == 'PCB_VIA']
print(f'\n[E] vias: {len(v)}, sizes {sorted(set((round(MM(x.GetWidth(F)),2), round(MM(x.GetDrillValue()),2)) for x in v))}')
th = collections.Counter()
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.GetNetCode() == gnd:
            c = p.GetLocalZoneConnection()
            th[('THT' if p.GetDrillSizeX() else 'SMD', {0: 'inherit', 1: 'none', 2: 'thermal', 3: 'full', 4: 'THT thermal'}.get(int(c), str(c)))] += 1
print('   GND pad zone connection:', dict(th))
os._exit(0)
