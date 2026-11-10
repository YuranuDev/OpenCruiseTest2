# PWR-CTRL v2.0 full layout flow (priority: GND plane continuity and current return paths): place -> 7A hand tracks + orthogonal autoroute -> 45-degree chamfers -> GND pours
# (islands kept, stitched, then removed) -> thermal fix -> silk -> silk clip -> checks
set -e
cd /home/claude/pcb/gen
python3 place_main.py >/dev/null 2>&1
timeout 1700 python3 route_main.py 2>&1 | grep -E "routed tracks" | tail -1
python3 chamfer.py ../pwrctrl/pwrctrl.kicad_pcb 2>&1 | grep -E "^pass|done"
python3 pour.py 2>&1 | grep -v leak | tail -1
python3 stitch.py 2>&1 | grep -v leak | tail -1
python3 fix_thermal.py ../pwrctrl/pwrctrl.kicad_pcb 2>&1 | grep starved
python3 gnd_reinforce.py ../pwrctrl/pwrctrl.kicad_pcb 2>&1 | grep added   # fence vias along long bottom tracks, vias at power GND pads, ties for weak islands
python3 silk.py 2>&1 | grep "silk front"; python3 silk_legend.py 2>&1 | grep -E "silk ok|NOT PLACED"
python3 silkclip.py ../pwrctrl/pwrctrl.kicad_pcb 2>&1 | grep -v leak | tail -1
python3 silkcheck.py ../pwrctrl/pwrctrl.kicad_pcb 2>&1 | grep -v leak | tail -2
python3 check.py ../pwrctrl/pwrctrl.kicad_pcb J1,J2,J3,J4,J6,J7,J8,J9,J12,J13,J14,J15,J16,J17 2>&1 | grep -v "^ *$" | head
cd ../pwrctrl && kicad-cli pcb drc --severity-all --format json -o /tmp/claude-0/drc.json pwrctrl.kicad_pcb >/dev/null
python3 -c "import json,collections;d=json.load(open('/tmp/claude-0/drc.json'));print('DRC',dict(collections.Counter(v['type'] for v in d['violations'])),'unconnected',len(d['unconnected_items']))"
python3 /home/claude/pcb/gen/gnd_audit.py /home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb 2>&1 | grep -v 'Debug\|leak' > /home/claude/pcb/pwrctrl/gnd_audit.txt
