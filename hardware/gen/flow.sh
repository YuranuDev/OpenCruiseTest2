set -e
cd /home/claude/pcb/gen
python3 place_main.py >/dev/null 2>&1
timeout 1700 python3 route_main.py 2>&1 | grep -E "final score|routed tracks" | tail -3
python3 pour.py 2>&1 | grep -v leak | tail -1
cd ../pwrctrl && kicad-cli pcb drc --severity-all --format json -o /tmp/claude-0/drc.json pwrctrl.kicad_pcb >/dev/null
python3 -c "
import json,collections
d=json.load(open('/tmp/claude-0/drc.json'))
print(collections.Counter(v['type'] for v in d['violations']))
for v in d['violations']: print(' ',v['type'],v['severity'],[ (i['description'][:60],i['pos']) for i in v['items']])
print('unconnected',len(d['unconnected_items']))
for v in d['unconnected_items']: print(' ',[ (i['description'][:60],i['pos']) for i in v['items']])
"
cd /home/claude/pcb/gen && python3 stitch.py 2>&1 | grep -v leak | tail -1 && python3 silk.py 2>&1 | grep -v leak | tail -1 && python3 silkclip.py 2>&1 | grep -v leak && python3 silkcheck.py ../pwrctrl/pwrctrl.kicad_pcb 2>&1 | grep -v leak
python3 check.py ../pwrctrl/pwrctrl.kicad_pcb J1,J2 2>&1 | grep -v "|  *$" | head -20
