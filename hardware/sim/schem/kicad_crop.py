"""kicad_crop.py : crop the KiCad schematic (pwrctrl.kicad_sch) into the 7 block images b1.png ... b7.png
shown as "KiCad原本" in the report.  Boxes = S.box() coordinates in gen/main_sch.py (mm).
Needs kicad-cli and rsvg-convert.   Run:  python kicad_crop.py
"""
import os, re, subprocess, tempfile, glob
HERE = os.path.dirname(os.path.abspath(__file__))
SCH = os.path.join(HERE, '..', '..', 'pwrctrl', 'pwrctrl.kicad_sch')
BOXES = [(10, 10, 215, 150), (220, 10, 420, 150), (425, 10, 585, 150), (10, 155, 215, 290),
         (220, 155, 585, 290), (10, 295, 585, 412), (10, 420, 585, 580)]
PXMM = 7
tmp = tempfile.mkdtemp()
subprocess.run(['kicad-cli', 'sch', 'export', 'svg', '-o', tmp, SCH], check=True, capture_output=True)
src = open(glob.glob(os.path.join(tmp, '*.svg'))[0], encoding='utf-8').read()
for i, (x0, y0, x1, y1) in enumerate(BOXES, 1):
    w, h = x1 - x0 + 4, y1 - y0 + 4
    s = re.sub(r'viewBox="[^"]*"', f'viewBox="{x0 - 2} {y0 - 2} {w} {h}"', src, count=1)
    s = re.sub(r'(<svg[^>]*?)\swidth="[^"]*"', rf'\1 width="{w}mm"', s, count=1)
    s = re.sub(r'(<svg[^>]*?)\sheight="[^"]*"', rf'\1 height="{h}mm"', s, count=1)
    p = os.path.join(tmp, f'b{i}.svg'); open(p, 'w', encoding='utf-8').write(s)
    subprocess.run(['rsvg-convert', '-w', str(w * PXMM), '-b', 'white', p, '-o', os.path.join(HERE, f'b{i}.png')], check=True)
print('done')
