import sys; sys.path.insert(0,'/home/claude/pcb/gen')
from pcbbuild import build
from render import render
W,H=92,58
P={'J1':(14.5,10,90),
   'J2':(48,3.7,180),'J3':(57,3.7,180),'J4':(66,3.7,180),'J5':(75,3.7,180),
   'JP1':(52,10,0),'R10':(57,10,0),'R11':(62,10,0),
   'R1':(14.5,18,90),'R2':(18.5,18,90),'R3':(22.5,18,90),'R4':(26.5,18,90),'R5':(30.5,18,90),
   'C1':(46,24,0),'C2':(54,17,90),'U1':(60,25,0),'D1':(62,34,0),'L1':(73,29,0),'C3':(64,15,0),'C4':(80,22,90),
   'R6':(48,33,0),'R7':(48,36,0),'C5':(48,39,0),
   'U2':(70,43,0),'C6':(78,41,90),'C7':(81,41,90),
   'D2':(36,28,0),'R8':(36,25,0),'D3':(36,34,0),'R9':(36,31,0),
   'JP2':(12,44,0),'JP3':(19,44,0),
   'J8':(11.5,53.5,0),'J9':(28,53.5,0),'J10':(44,53.5,0),'J11':(60,53.5,0),
   'J6':(87.5,24,90),'J7':(87.5,42,90),
   'H1':(4,4),'H2':(88,4),'H3':(4,54),'H4':(88,54)}
REF={'L1':(73,35.2,0)}
b,comps,miss=build('/home/claude/pcb/exthub/exthub.net','/home/claude/pcb/exthub/exthub.kicad_pcb',W,H,P,ref_pos={k:(v[0]-P[k][0],v[1]-P[k][1],v[2]) for k,v in REF.items()},hide_refs=('C3',))
print('missing',miss)
render('/home/claude/pcb/exthub/exthub.kicad_pcb','/home/claude/pcb/exthub/placement.png',title='EXT-HUB v1.0 placement (92 x 58 mm)',dpi=110)
