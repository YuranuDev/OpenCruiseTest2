"""bomcpl.py <board> <outdir> : JLC BOM/CPL. Skips J*, H*, TP*, R62, U2 (hand-soldered / not assembled) and parts without LCSC#."""
import sys, csv, re, collections, pcbnew
b = pcbnew.LoadBoard(sys.argv[1]); out = sys.argv[2]
SKIP = re.compile(r'^(J|H|TP)\d+$|^(R62|U2)$')
def nat(r):
    m = re.match(r'([A-Z]+)(\d+)', r); return (m.group(1), int(m.group(2))) if m else (r, 0)
bom = collections.OrderedDict(); cpl = []
for fp in sorted(b.GetFootprints(), key=lambda f: nat(f.GetReference())):
    ref = fp.GetReference()
    if SKIP.match(ref) or (hasattr(fp, 'IsDNP') and fp.IsDNP()): continue
    lcsc = fp.GetFieldText('LCSC') if fp.HasFieldByName('LCSC') else ''
    if not lcsc: continue
    k = (fp.GetValue(), fp.GetFPID().GetLibItemName().wx_str(), lcsc)
    bom.setdefault(k, []).append(ref)
    p = fp.GetPosition()
    cpl.append([ref, f'{pcbnew.ToMM(p.x):.4f}mm', f'{-pcbnew.ToMM(p.y):.4f}mm',
                'Top' if fp.GetLayer() == pcbnew.F_Cu else 'Bottom', f'{fp.GetOrientationDegrees() % 360:.1f}'])
with open(f'{out}/pwrctrl_BOM_JLC.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['Comment', 'Designator', 'Footprint', 'LCSC Part #'])
    for (v, fpn, l), refs in bom.items(): w.writerow([v, ','.join(refs), fpn, l])
with open(f'{out}/pwrctrl_CPL_JLC.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['Designator', 'Mid X', 'Mid Y', 'Layer', 'Rotation']); w.writerows(cpl)
print(f'BOM {len(bom)} lines / {sum(len(r) for r in bom.values())} parts, CPL {len(cpl)}')
