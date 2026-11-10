"""place_eval.py <board.kicad_pcb> [json_out]
Placement-quality metrics (routing not needed):
  - ratsnest length per net (minimum spanning tree over pads, GND excluded), total and per block
  - key placement distances (decoupling caps, dividers, protection parts, pull-ups, FB networks)
  - courtyard overlaps and parts per block (bounding box of each block)
"""
import sys, math, json, collections
import pcbnew
B = sys.argv[1]
b = pcbnew.LoadBoard(B)
mm = pcbnew.ToMM


def pads_by_net():
    d = collections.defaultdict(list)
    for fp in b.GetFootprints():
        for p in fp.Pads():
            n = p.GetNetname()
            if n and not n.startswith('unconnected'):
                d[n].append((fp.GetReference(), p.GetNumber(), mm(p.GetPosition().x), mm(p.GetPosition().y)))
    return d


def mst(pts):
    if len(pts) < 2: return 0.0, []
    n = len(pts); inT = [False] * n; dist = [1e18] * n; par = [-1] * n; dist[0] = 0; tot = 0; edges = []
    for _ in range(n):
        u = min((i for i in range(n) if not inT[i]), key=lambda i: dist[i]); inT[u] = True; tot += dist[u] if par[u] >= 0 else 0
        if par[u] >= 0: edges.append((par[u], u))
        for v in range(n):
            if not inT[v]:
                d = math.hypot(pts[u][2] - pts[v][2], pts[u][3] - pts[v][3])
                if d < dist[v]: dist[v] = d; par[v] = u
    return tot, edges


P = pads_by_net()
# merge pads of the same footprint+net at (almost) same place is fine; MST handles it
rat = {}
for n, pts in P.items():
    if n == 'GND': continue
    rat[n] = round(mst(pts)[0], 1)

# GND: nearest-GND-via is not known before routing; report each GND pad's distance to its nearest other GND pad instead (proxy)

def pad(ref, num):
    fp = b.FindFootprintByReference(ref)
    if num == 'tab':   # SOT-223 tab = the larger of the two pads numbered 2
        p = max([q for q in fp.Pads() if q.GetNumber() == '2'], key=lambda q: q.GetSize().x * q.GetSize().y)
        return mm(p.GetPosition().x), mm(p.GetPosition().y)
    for p in fp.Pads():
        if p.GetNumber() == num: return mm(p.GetPosition().x), mm(p.GetPosition().y)
    raise KeyError(ref + num)


def d(a, b_):
    return round(math.hypot(a[0] - b_[0], a[1] - b_[1]), 1)

KEY = [
    # (label, (ref,pad), (ref,pad))
    ('U1 VIN - C5 (Cin ceramic)', ('U1', '1'), ('C5', '1')),
    ('U1 VIN - C4 (Cin bulk)', ('U1', '1'), ('C4', '1')),
    ('U1 SW - D11 cathode', ('U1', '2'), ('D11', '1')),
    ('U1 SW - L1', ('U1', '2'), ('L1', '1')),
    ('U1 FB - R50/R51 node', ('U1', '4'), ('R50', '2')),
    ('L1 out - C7', ('L1', '2'), ('C7', '1')),
    ('U8 VIN - C41 (Cin ceramic)', ('U8', '1'), ('C41', '1')),
    ('U8 VIN - C40 (Cin bulk)', ('U8', '1'), ('C40', '1')),
    ('U8 SW - D12 cathode', ('U8', '2'), ('D12', '1')),
    ('U8 FB - R52/R53 node', ('U8', '4'), ('R52', '2')),
    ('L2 out - C43', ('L2', '2'), ('C43', '1')),
    ('U9 IN(+5VS) - C42 (+)', ('U9', '3'), ('C42', '1')),
    ('U9 OUT(tab) - C45', ('U9', 'tab'), ('C45', '1')),
    ('U5 VCC - C10', ('U5', '5'), ('C10', '1')),
    ('U6 VCC - C14', ('U6', '3'), ('C14', '1')),
    ('U4 VBAT - C15', ('U4', '7'), ('C15', '1')),
    ('U4 VBAT - C16', ('U4', '7'), ('C16', '1')),
    ('XIAO 3V3 - C13', ('J11', '5'), ('C13', '1')),
    ('XIAO D0 (ADC) - C12', ('J10', '1'), ('C12', '1')),
    ('XIAO D0 (ADC) - R6 (divider)', ('J10', '1'), ('R6', '1')),
    ('J1 ACC - TVS2', ('J1', '2'), ('TVS2', '1')),
    ('J2 VSW - TVS1', ('J2', '1'), ('TVS1', '1')),
    ('J3 CANH - U7 (ESD)', ('J3', '2'), ('U7', '2')),
    ('J3 K - TVS3', ('J3', '1'), ('TVS3', '1')),
    ('XIAO SDA - R30 (pull-up)', ('J10', '5'), ('R30', '2')),
    ('XIAO D2 - R80 (series)', ('J10', '3'), ('R80', '1')),
    ('XIAO D7 - R83 (series)', ('J11', '1'), ('R83', '1')),
    ('K1 VSW - F4 (VSW_EXT fuse)', ('K1', '13'), ('F4', '1')),
    ('J4 - U3 (opto)', ('J4', '1'), ('U3', '4')),
]
key = []
for lab, a, c in KEY:
    try: key.append((lab, d(pad(*a), pad(*c))))
    except Exception as e: key.append((lab, None))

# buck hot loop: polygon through pad centres Cin+ -> VIN -> SW -> D cathode -> D anode -> Cin GND (shoelace)
def loop(cin, ic, dd):
    pts = [pad(cin, '1'), pad(ic, '1'), pad(ic, '2'), pad(dd, '1'), pad(dd, '2'), pad(cin, '2')]
    a = 0
    for i in range(len(pts)):
        x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % len(pts)]; a += x1 * y2 - x2 * y1
    per = sum(math.hypot(pts[i][0] - pts[(i + 1) % 6][0], pts[i][1] - pts[(i + 1) % 6][1]) for i in range(6))
    return round(abs(a) / 2, 1), round(per, 1)
for lab, c_, i_, d_ in (('U1 hot loop (C5 ceramic)', 'C5', 'U1', 'D11'), ('U1 loop via bulk C4', 'C4', 'U1', 'D11'),
                         ('U8 hot loop (C41 ceramic)', 'C41', 'U8', 'D12'), ('U8 loop via bulk C40', 'C40', 'U8', 'D12')):
    ar, pe = loop(c_, i_, d_); key.append((lab + ' path [mm]', pe))

BLOCKS = {
    '1 power entry / 7A': 'J1 J2 K1 TVS1 TVS2 C1 C2 C3 LED1 R40 TP1 TP2 TP3 TP9',
    '3 relay hold': 'D1 D2 D5 Q1 R11 U5 C10 D3 R3 R1 C11 R2 ZD1 TP6 TP7',
    '2 MCU 5V buck': 'D7 D9 C4 C5 U1 D11 L1 C6 C7 R50 R51 C8 D8 LED2 R41 TP4',
    '4 XIAO + ACC sense': 'U2 J10 J11 C13 C9 TP5 R5 R6 ZD2 C12',
    '5 vehicle bus': 'J3 U7 R62 TVS3 R14 D10 C17 TP8 U6 C14 R60 R61 JP1 U4 C15 C16 R70 R71 R72 JP6 R73 JP4 JP5 Q8 R20 R21 R22 JP7 R23 Q9 F3',
    '6 I2C PU / GPIO R / PC button': 'JP3 R30 R31 R80 R81 R82 R83 R84 JP2 R12 R13 U3 J4',
    '7 sensor supply': 'C40 C41 U8 D12 L2 C42 C43 R52 R53 C44 U9 C45 C46 LED3 R42 LED4 R43 TP11 TP12',
}
blk = {}
for name, refs in BLOCKS.items():
    xs = []; ys = []
    for r in refs.split():
        fp = b.FindFootprintByReference(r)
        if not fp: continue
        bb = fp.GetBoundingBox(False)
        xs += [mm(bb.GetX()), mm(bb.GetRight())]; ys += [mm(bb.GetY()), mm(bb.GetBottom())]
    nets = set()
    for r in refs.split():
        fp = b.FindFootprintByReference(r)
        if fp:
            for p in fp.Pads(): nets.add(p.GetNetname())
    blk[name] = dict(bbox=[round(min(xs), 1), round(min(ys), 1), round(max(xs), 1), round(max(ys), 1)],
                     area=round((max(xs) - min(xs)) * (max(ys) - min(ys))))

# courtyard overlaps
cy = []
for fp in b.GetFootprints():
    c = fp.GetCourtyard(pcbnew.F_Cu and pcbnew.F_CrtYd)
    if c.OutlineCount(): cy.append((fp.GetReference(), c))
ov = []
for i in range(len(cy)):
    for j in range(i + 1, len(cy)):
        a = pcbnew.SHAPE_POLY_SET(cy[i][1]); a.BooleanIntersection(cy[j][1])
        if a.OutlineCount() and a.Area() > 1e4: ov.append((cy[i][0], cy[j][0], round(a.Area() / 1e12, 2)))

CLASS = {'power': 'VBAT_IN VSW VSW_EXT VIN5 SW5 SW6 V5REG +5V +5VS +3V3 +3V3S ACC_IN GPS_VCC COIL_P COIL_N KPU'.split()}
tot = round(sum(rat.values()), 1)
pw = round(sum(v for k, v in rat.items() if k in CLASS['power']), 1)
res = dict(total=tot, power=pw, signal=round(tot - pw, 1), nets=rat, key=key, blocks=blk, overlaps=ov)
if len(sys.argv) > 2: json.dump(res, open(sys.argv[2], 'w'), indent=1, ensure_ascii=False)
print(f'ratsnest (MST, GND excluded): total {tot} mm  power {pw}  signal {round(tot-pw,1)}')
for k, v in sorted(rat.items(), key=lambda x: -x[1])[:25]: print(f'   {k:12} {v:6.1f}')
print('key distances [mm]:')
for lab, v in key: print(f'   {lab:34} {v}')
print('courtyard overlaps:', ov)
