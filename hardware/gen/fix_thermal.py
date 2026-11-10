# Pads whose thermal-relief spokes are starved (DRC "starved_thermal") are connected solid to the GND pour.
import sys,json,subprocess,os
import pcbnew
PCB=sys.argv[1] if len(sys.argv)>1 else '/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb'
subprocess.run(['kicad-cli','pcb','drc','--severity-all','--format','json','-o','/tmp/claude-0/ft.json',PCB],capture_output=True)
d=json.load(open('/tmp/claude-0/ft.json'))
tg=[i['description'] for v in d['violations'] if v['type']=='starved_thermal' for i in v['items'] if 'pad' in i['description']]
b=pcbnew.LoadBoard(PCB); n=0
for fp in b.GetFootprints():
    for p in fp.Pads():
        if any(f"pad {p.GetNumber()} [{p.GetNetname()}] of {fp.GetReference()}" in t for t in tg):
            p.SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_FULL); n+=1
if n: pcbnew.ZONE_FILLER(b).Fill(b.Zones()); pcbnew.SaveBoard(PCB,b)
print('starved thermals fixed',n); os._exit(0)
