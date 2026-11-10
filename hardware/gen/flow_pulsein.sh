set -e
cd /home/claude/pcb/gen
python3 place_pulsein.py 2>&1 | grep -v leak
python3 route_pulsein.py 2>&1 | grep -v "leak\|Debug" | tail -1
sed "s#/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb#/home/claude/pcb/pulsein/pulsein.kicad_pcb#; s/step=5.0/step=4.0/; s/^y=4.0/y=3.0/; s/    x=4.0/    x=3.0/" stitch.py > /tmp/stitch_p.py && python3 /tmp/stitch_p.py 2>&1 | grep -v leak | tail -1
python3 silk_pulsein.py 2>&1 | grep -v leak
python3 silkclip.py ../pulsein/pulsein.kicad_pcb 2>&1 | grep -v leak | tail -3
python3 silkcheck.py ../pulsein/pulsein.kicad_pcb 2>&1 | grep -v leak | tail -2
python3 check.py ../pulsein/pulsein.kicad_pcb J1,J2 2>&1 | grep -v "^ *$" | head
cd ../pulsein && kicad-cli pcb drc --severity-all --format json -o /tmp/d.json pulsein.kicad_pcb >/dev/null
python3 -c "import json;d=json.load(open('/tmp/d.json'));print('DRC viol',len(d['violations']),'unconn',len(d['unconnected_items']))"
