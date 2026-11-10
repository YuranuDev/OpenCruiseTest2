"""place_v22.py : PWR-CTRL v2.2 placement candidate (placement only, not routed).
Base = the user's connector arrangement (edited in KiCad 10, parsed into user_fps_v22.json).
Connectors keep the user's positions; the other parts are re-placed around them and the board is shrunk.
Output: pwrctrl/placement_v2.2/pwrctrl_place.kicad_pcb (+ png)
"""
import sys, json; sys.path.insert(0, '/home/claude/pcb/gen')
from pcbbuild import build
from render import render
W, H = 133, 91
OUT = '/home/claude/pcb/pwrctrl/placement_v2.2/pwrctrl_place.kicad_pcb'
U = json.load(open('/home/claude/pcb/gen/user_fps_v22.json'))
P = {r: (f['x'], f['y'], f['r'] % 360) for r, f in U.items()}

# I2C port row moved up 1 mm (user layout otherwise kept) so that the bottom-right hole fits
for r in ('J6', 'J7', 'J12', 'J13', 'J14', 'J15'):
    x, y, a = P[r]; P[r] = (x, y - 1.0, a)
# shrink: both port rows (except J17 / J5 next to the XIAO) slide 8 mm left as groups, sensor supply 3 mm left
for r in ('J6', 'J7', 'J12', 'J13', 'J14', 'J15', 'J16', 'J8', 'J9', 'J4', 'JP8', 'JP9'):
    x, y, a = P[r]; P[r] = (x - 8.0, y, a)
for r in 'U8 C41 C40 D12 L2 R53 R52 C44 C43 C42 U9 C45 C46 TP12 TP11 R42 LED3 R43 LED4'.split():
    x, y, a = P[r]; P[r] = (x - 3.0, y, a)
P.update({
    # holes: 4 corners + 1 bottom-middle... top-middle (H2) kept off the VSW_EXT run along the top edge
    'H1': (4, 4), 'H5': (129, 4), 'H3': (4, 87), 'H4': (129, 87), 'H2': (95.5, 4),
    # VSW_EXT PTC: VSW in from below (tap), VSW_EXT out on top -> runs along the top edge to the sensor supply (C40 +)
    'F4': (65, 6, 90),
    # ---- vehicle bus under J3 (J3 at the user's position, pins at y 57.5: K / CANH / CANL / GND) ----
    'U7': (16.75, 63.6, 270),          # CAN ESD right under J3 CANH/CANL
    'R62': (16.75, 67.2, 0),           # 120R CANH-CANL
    'TVS3': (11.5, 65.3, 270),         # K-Line TVS under J3 pin 1
    'C17': (14.15, 64.0, 270),
    'U6': (24.5, 66.0, 180),           # CAN transceiver, bus pins facing the protection
    'C14': (29.4, 66.0, 270), 'R60': (21.8, 70.2, 0), 'R61': (31.5, 66.0, 270), 'JP1': (30.3, 68.9, 180),
    'U4': (24.5, 74.5, 180),           # K-Line transceiver, LIN pin facing the protection
    'C15': (17.9, 75.14, 180), 'C16': (17.6, 78.3, 180),
    'R72': (29.7, 72.0, 270), 'JP6': (32.5, 72.82, 180), 'R73': (35.5, 72.4, 270),
    'R71': (30.5, 75.64, 180), 'R70': (30.5, 77.9, 180),
    'JP4': (41.5, 71.92, 270), 'JP5': (38.5, 74.46, 270),
    # K-Line pull-up and direct driver: left column next to the K-Line node (J3 pin 1)
    'R14': (6.8, 58.5, 90), 'D10': (6.8, 65.0, 270),
    'F3': (2.8, 58.5, 90), 'Q9': (2.8, 63.2, 90), 'R23': (2.8, 67.3, 270),
    'JP7': (2.8, 71.0, 90), 'Q8': (2.8, 75.0, 90), 'R22': (6.8, 73.4, 180), 'R20': (6.3, 77.4, 180), 'R21': (2.4, 79.0, 270),
    'TP8': (6.8, 81.0), 'TP5': (41.8, 87.8),
    # ---- PC power button: opto right beside J4 (user's J4 position) ----
    'U3': (113.5, 56.2, 0), 'R12': (113.5, 62.0, 90), 'R13': (115.6, 62.0, 90), 'JP2': (114.5, 65.0, 0),
})
REFPOS = {'J1': (13, 7.0, 0), 'J2': (10, 27.6, 0), 'TVS1': (31, 46.3, 0), 'U2': (56, 79, 0)}

G = [(0, 1, 46, 52, '1 POWER ENTRY / 7A', '#d62728'), (50, 9, 67, 39, '3 RELAY HOLD', '#9467bd'),
     (61, 1, 93, 44, '2 5V BUCK (MCU)', '#ff7f0e'), (93, 8, 128, 48, '7 SENSOR SUPPLY 5VS/3V3S', '#e377c2'),
     (0, 53, 45, 90, '5 VEHICLE BUS (CAN/K)', '#2ca02c'), (36, 62, 75, 91, '4 XIAO + PIN PARTS', '#1f77b4'),
     (75, 46, 131, 69, '8b SIGNAL PORTS + J5 / PC BTN', '#bcbd22'), (83, 69, 129, 84, '8a I2C PORTS', '#17becf')]

if __name__ == '__main__':
    b, comps, miss = build('/home/claude/pcb/pwrctrl/pwrctrl.net', OUT, W, H, P,
                           ref_pos={k: (v[0] - P[k][0], v[1] - P[k][1], v[2]) for k, v in REFPOS.items()},
                           hide_refs=('J10', 'J11'), silk_to_fab=('J10', 'J11'))
    print('missing', miss)
    render(OUT, OUT.replace('pwrctrl_place.kicad_pcb', 'placement_v2.2.png'), groups=G,
           title='OpenCruise PWR-CTRL v2.2 placement candidate (133 x 91 mm) - user connector layout, NOT ROUTED', dpi=110)
