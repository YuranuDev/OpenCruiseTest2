"""chamfer.py <board.kicad_pcb>
Turn the 90-degree corners left by orthogonal autorouting into 45-degree chamfers
("avoid right-angle corners"), then check with DRC and undo any chamfer that causes a violation.
Only unlocked tracks are touched; corners that sit on a pad or via are left alone.
"""
import sys, json, subprocess, math, collections
import pcbnew
PCB = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'
MM = pcbnew.FromMM
CMAX = 1.0      # max chamfer leg [mm]


def key(p):
    return (round(p.x / 1000), round(p.y / 1000))   # 1 um grid


def chamfer_pass(path, skip):
    b = pcbnew.LoadBoard(path)
    tracks = [t for t in b.GetTracks() if t.GetClass() == 'PCB_TRACK' and not t.IsLocked()]
    ends = collections.defaultdict(list)
    for t in b.GetTracks():
        if t.GetClass() == 'PCB_TRACK':
            ends[(t.GetNetCode(), t.GetLayer(), key(t.GetStart()))].append(t)
            ends[(t.GetNetCode(), t.GetLayer(), key(t.GetEnd()))].append(t)
    blocked = set()
    for v in b.GetTracks():
        if v.GetClass() == 'PCB_VIA':
            blocked.add((v.GetNetCode(), key(v.GetPosition())))
    pads = [p for fp in b.GetFootprints() for p in fp.Pads()]
    made = []
    done = set()
    for (net, layer, k), ts in list(ends.items()):
        if len(ts) != 2 or (net, k) in blocked or (net, layer, k) in skip:
            continue
        t1, t2 = ts
        if t1.IsLocked() or t2.IsLocked() or id(t1) in done or id(t2) in done:
            continue
        if t1.GetWidth() != t2.GetWidth():
            continue
        pt = pcbnew.VECTOR2I(k[0] * 1000, k[1] * 1000)
        if any(p.GetNetCode() == net and p.HitTest(pt) for p in pads):
            continue

        def far(t):
            return t.GetEnd() if key(t.GetStart()) == k else t.GetStart()
        a, c = far(t1), far(t2)
        v1 = (a.x - pt.x, a.y - pt.y); v2 = (c.x - pt.x, c.y - pt.y)
        l1 = math.hypot(*v1); l2 = math.hypot(*v2)
        if l1 < 1 or l2 < 1:
            continue
        dot = (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)
        if abs(dot) > 0.02:                      # only right angles
            continue
        w = t1.GetWidth()
        cl = min(MM(CMAX) + w / 2, 0.45 * l1, 0.45 * l2)
        if cl < w * 0.6:
            continue
        p1 = pcbnew.VECTOR2I(int(pt.x + v1[0] / l1 * cl), int(pt.y + v1[1] / l1 * cl))
        p2 = pcbnew.VECTOR2I(int(pt.x + v2[0] / l2 * cl), int(pt.y + v2[1] / l2 * cl))
        for t, p in ((t1, p1), (t2, p2)):
            if key(t.GetStart()) == k: t.SetStart(p)
            else: t.SetEnd(p)
        d = pcbnew.PCB_TRACK(b); d.SetStart(p1); d.SetEnd(p2); d.SetWidth(w); d.SetLayer(layer); d.SetNetCode(net); b.Add(d)
        done.add(id(t1)); done.add(id(t2))
        made.append(((net, layer, k), (p1.x, p1.y, p2.x, p2.y)))
    pcbnew.SaveBoard(path, b)
    return made


def drc_bad(path):
    subprocess.run(['kicad-cli', 'pcb', 'drc', '--severity-error', '--format', 'json', '-o', '/tmp/claude-0/ch.json', path], capture_output=True)
    d = json.load(open('/tmp/claude-0/ch.json'))
    pos = []
    for v in d['violations']:
        if v['type'] in ('clearance', 'tracks_crossing', 'shorting_items', 'hole_clearance', 'copper_edge_clearance', 'solder_mask_bridge'):
            for i in v['items']:
                pos.append((i['pos']['x'], i['pos']['y']))
    return pos, len(d['unconnected_items'])


import shutil, os
os.makedirs('/tmp/claude-0', exist_ok=True)
shutil.copy(PCB, '/tmp/claude-0/chamfer_orig.kicad_pcb')
base_pos, base_unc = drc_bad(PCB)
skip = set()
for it in range(6):
    shutil.copy('/tmp/claude-0/chamfer_orig.kicad_pcb', PCB)
    made = chamfer_pass(PCB, skip)
    pos, unc = drc_bad(PCB)
    new = [p for p in pos if p not in base_pos]
    bad = set()
    for nk, (x1, y1, x2, y2) in made:
        for (px, py) in new:
            # violation reported near this chamfer (within 1.5 mm of its diagonal)
            mx, my = (x1 + x2) / 2e6, (y1 + y2) / 2e6
            if math.hypot(px - mx, py - my) < 1.5:
                bad.add(nk)
    print(f'pass {it}: chamfers {len(made)}, new violations {len(new)}, unconnected {unc}, reverting {len(bad)}')
    if not new and unc <= base_unc:
        break
    if not bad:          # cannot attribute -> drop all chamfers near any violation by layer-agnostic radius
        bad = {nk for nk, _ in made}
    skip |= bad
print('done')
