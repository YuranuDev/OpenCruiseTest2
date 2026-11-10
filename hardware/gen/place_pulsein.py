import sys; sys.path.insert(0,'/home/claude/pcb/gen')
from pcbbuild import build
from render import render
import pcbnew
W,H=34,28
P={'J2':(3.6,19.5,90),'J1':(29.8,19.5,90),
   'JP1':(11,3.5,0),'R1':(11,6.5,0),
   'R2':(11,11,0),'DZ1':(14.5,15.5,90),'C1':(11,14,0),'R3':(17,15,90),'JP2':(17,19.5,90),
   'U1':(20.3,11,0),'C4':(20.3,7.5,0),'R4':(24.8,11,0),'R5':(24.8,14,0),'D1':(24.8,17,0),
   'U2':(21,3.5,90),'C2':(17,3.5,90),'C3':(25,3.5,90),'H1':(22.5,23.8)}
REF={'J2':(3.6,7.6,0),'J1':(29.8,7.6,0)}
b,comps,miss=build('/home/claude/pcb/pulsein/pulsein.net','/home/claude/pcb/pulsein/pulsein.kicad_pcb',W,H,P,ref_pos={k:(v[0]-P[k][0],v[1]-P[k][1],v[2]) for k,v in REF.items()})
print('missing',miss)
render('/home/claude/pcb/pulsein/pulsein.kicad_pcb','/home/claude/pcb/pulsein/placement.png',title='PULSE-IN v1.0 placement (34 x 28 mm)',dpi=150)
