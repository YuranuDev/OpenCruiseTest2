"""Rebuild the user's KiCad-10 placement (positions parsed from the .kicad_pcb) on KiCad 9 for evaluation/rendering."""
import sys, json; sys.path.insert(0, '/home/claude/pcb/gen')
from pcbbuild import build
from render import render
fps = json.load(open(sys.argv[1])); out = sys.argv[2]
P = {r: (f['x'], f['y'], f['r'] % 360) for r, f in fps.items()}
W = float(sys.argv[3]) if len(sys.argv) > 3 else 165; H = float(sys.argv[4]) if len(sys.argv) > 4 else 91
build('/home/claude/pcb/pwrctrl/pwrctrl.net', out, W, H, P, hide_refs=('J10', 'J11'), silk_to_fab=('J10', 'J11'))
render(out, out.replace('.kicad_pcb', '.png'), title='user connector placement', dpi=110)
