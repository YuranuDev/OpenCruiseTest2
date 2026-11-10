set -e
cd /home/claude/pcb/gen
python3 place_exthub.py 2>&1 | grep -v leak
python3 route_exthub.py 2>&1 | grep -v "leak\|Debug" | tail -1
sed "s#/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb#/home/claude/pcb/exthub/exthub.kicad_pcb#" stitch.py > /tmp/stitch_e.py && python3 /tmp/stitch_e.py 2>&1 | grep -v leak | tail -1
python3 silk_exthub.py 2>&1 | grep -v leak
python3 silkclip.py ../exthub/exthub.kicad_pcb 2>&1 | grep -v leak | tail -3
python3 silkcheck.py ../exthub/exthub.kicad_pcb 2>&1 | grep -v leak | tail -2
python3 check.py ../exthub/exthub.kicad_pcb J1,J2,J3,J4,J5,J6,J7,J8,J9,J10,J11 2>&1 | grep -v "^ *$" | head
cd ../exthub && kicad-cli pcb drc --severity-all --format json -o /tmp/d.json exthub.kicad_pcb >/dev/null
python3 -c "import json;d=json.load(open('/tmp/d.json'));print('DRC viol',len(d['violations']),'unconn',len(d['unconnected_items']));[print(v['type'],v['description'],[i['description'][:50] for i in v['items']]) for v in d['violations']]"
