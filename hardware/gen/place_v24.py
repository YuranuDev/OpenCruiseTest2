"""place_v23.py : PWR-CTRL v2.4 placement candidate (placement only, not routed).
Base = the user's latest edit (placement_v2.1/pwrctrl_place.kicad_pcb, KiCad 10, parsed into user_fps_v23.json).
 - J3 kept at the left edge (user); vehicle front end rebuilt behind it (connector -> TVS/ESD -> transceiver)
 - XIAO back to the bottom edge (USB-C at the edge), decoupling back at its pins
 - all solder jumpers + 2 test points gathered in one labelled CONFIG panel in the centre
 - user's pin legends kept, corrected (SCL, TXO/RXI, 5V/12V), sized to JLC minimum (1.0 mm / 0.15 mm)
 - board shrunk to 140 x 91 mm
Output: pwrctrl/placement_v2.4/pwrctrl_place.kicad_pcb (+ png)
"""
import sys, json; sys.path.insert(0, '/home/claude/pcb/gen')
import pcbnew
from pcbbuild import build
from render import render
W, H = 140, 91
OUT = '/home/claude/pcb/pwrctrl/placement_v2.4/pwrctrl_place.kicad_pcb'
U = json.load(open('/home/claude/pcb/gen/user_fps_v23.json'))
P = {r: (f['x'], f['y'], f['r'] % 360) for r, f in U.items()}

# ---------------- connectors (user) : only small shifts for the 140 mm outline ----------------
for r in ('J6', 'J7', 'J12', 'J13', 'J14', 'J15'):            # I2C row 3.5 mm left (fits the 140 mm outline + corner hole)
    x, y, a = P[r]; P[r] = (x - 3.5, y, a)
P['J5'] = (86.5, 84.0, 180)
P.update({'H1': (4, 4), 'H2': (107, 4), 'H3': (4, 87), 'H4': (136.0, 87.2), 'H5': (136.0, 4)})
P['F4'] = (65, 6, 90)                                          # VSW_EXT out on top -> runs along the top edge to C40 +

# ---------------- XIAO back to the bottom edge, parts on its pins ----------------
XU, YU = 62.6, 77.0
P['U2'] = (XU, YU, 180); P['J10'] = (XU + 7.62, YU + 7.62, 180); P['J11'] = (XU - 7.62, YU - 7.62, 0)
cx = XU + 7.62 + 4.88; y7 = YU - 7.62                          # right column x, J10 pin 7 row
for i, r in enumerate(['R84', 'R83', 'R82']):
    P[r] = (cx, y7 - 5.08 + 2.54 * i, 0)
P['R31'] = (cx, y7 + 2.54, 180); P['R30'] = (cx, y7 + 5.08, 180)
P['R81'] = (cx, y7 + 7.62, 0); P['R80'] = (cx, y7 + 10.16, 0)
P['ZD2'] = (cx + 0.1, y7 + 12.72, 180); P['C12'] = (cx - 1.1, y7 + 16.42, 270); P['R6'] = (cx + 0.7, y7 + 16.42, 270)
P['R5'] = (cx + 4.2, y7 + 12.72, 180)
P['C13'] = (XU - 11.6, YU + 2.54, 180); P['C9'] = (XU - 11.6, YU + 7.62, 180)

# ---------------- vehicle front end behind J3 (J3 at the user's position: pins x 5, GND 55.9 / CANL 58.4 / CANH 60.9 / K 63.4) ----
P.update({
    'U7': (16.0, 59.65, 0),       # CAN ESD: CANL/CANH pads in line with J3 pins 3/2, GND pad faces away (top GND pour -> J3 pin 4)
    'R62': (19.6, 59.65, 90),     # 120R (DNP) between the two lines, after the ESD diode
    'U6': (24.4, 59.0, 180),      # CAN transceiver, bus pins toward the ESD diode
    'C14': (29.4, 59.0, 270), 'R61': (31.6, 60.2, 270), 'R60': (24.4, 63.2, 0),
    'TVS3': (18.0, 63.6, 0),      # K-Line TVS: K pad straight in line with J3 pin 1, GND pad next to the U7 GND
    'C17': (16.0, 67.0, 270),     # 220 pF right after the TVS K pad (flow-through)
    'U4': (24.4, 68.6, 180),      # K-Line transceiver, LIN/VBAT toward the protection side
    'C15': (18.0, 69.8, 180), 'C16': (17.8, 72.8, 180),
    'R72': (30.4, 66.69, 180), 'R71': (30.4, 69.24, 180), 'R70': (33.7, 70.51, 180),
    # K-Line loads that hang on the protected K net (downstream of TVS3)
    'R14': (17.5, 77.0, 0), 'D10': (11.0, 77.0, 180), 'TP8': (24.5, 77.0),
    'F3': (21.0, 81.0, 0), 'Q9': (16.5, 81.0, 0), 'R23': (13.0, 80.6, 270),
    # K direct-drive logic (3.3 V side) next to the CONFIG panel
    'R20': (35.0, 62.55, 0), 'R21': (35.0, 64.8, 180), 'Q8': (39.5, 63.5, 0), 'R22': (43.0, 62.7, 270), 'R73': (35.0, 67.1, 0),
})

# ---------------- solder jumpers grouped by function, next to the circuit they configure ----------------
RA = 49.5
JPS = [  # ref, x, y, rot, label
    ('JP7', 38.5, RA, 0, 'K_DRV'), ('JP6', 46.0, RA, 0, 'K_TX'), ('JP1', 53.5, RA, 0, 'CAN_TX'),
    ('JP4', 62.0, RA, 0, 'VEH_TX'), ('JP5', 73.0, RA, 0, 'VEH_RX'),          # VEHICLE COMM box (between vehicle block and XIAO)
    ('JP8', 99.0, 46.0, 0, 'GPS_PWR'), ('JP9', 107.0, 46.0, 0, 'PPS>D10'),  # GPS group, above the GPS connector
    ('JP2', 126.5, 67.4, 0, None),                                          # PC button group, under the opto
    ('JP3', 78.6, 73.2, 90, None),                                          # I2C pull-up, next to R30/R31
]
for r, x, y, a_, _ in JPS:
    P[r] = (x, y, a_)
P['TP5'] = (40.0, 56.6, 0); P['TP10'] = (44.5, 56.6, 0)                  # TEST points under the VEHICLE box
P['C18'] = (21.0, 55.2, 180)                                              # TJA1042 VIO (3.3 V) decoupling at pin 5

# ---------------- PC button: opto 1 mm left so the +/- marks fit next to J4 ----------------
for r in ('U3', 'R12', 'R13'):
    x, y, a = P[r]; P[r] = (x - 1.0, y, a)

# ---------------- silkscreen texts (user legends, corrected) ----------------
T = []   # text, x, y, size, justify ('left'|'center'), thickness
def t(s, x, y, size=1.0, j='left', th=0.15, ang=0): T.append((s, x, y, size, j, th, ang))
# J3 (vehicle) pins
for s, y in (('GND', 56.4), ('CANL', 58.9), ('CANH', 61.4), ('KLINE', 63.9)): t(s, 9.3, y)
t('CAR', 5.5, 52.3, 1.5, 'center', 0.25)
# GPS J16 pins (TXO = board output -> GPS RX, RXI = board input <- GPS TX)
gx, gy = P['J16'][0] + 4.2, P['J16'][1]
for s, k in (('GND', 0), ('VCC', 1), ('TXO', 2), ('RXI', 3), ('PPS', 4)): t(s, gx, gy - 2.5 * k + 0.5)
t('GPS', P['J16'][0] + 0.4, P['J16'][1] - 13.4, 1.5, 'center', 0.25)
# PULSE A/B legend (right of J9) and AUX legend (right of J17), same pin order 1 12V / 2 5V / 3 GND / 4 SIG
px, py = P['J9'][0] + 5.55, P['J9'][1]
for s, k in (('12V', 0), ('5V', 1), ('GND', 2), ('SIG', 3)): t(s, px, py - 2.5 * k + 0.5, j='center')
ax, ay = P['J17'][0] + 4.2, P['J17'][1]
for s, k in (('12V', 0), ('5V', 1), ('GND', 2), ('D10', 3)): t(s, ax, ay - 2.5 * k + 0.5)
t('AUX', P['J17'][0] + 0.5, P['J17'][1] - 11.0, 1.5, 'center', 0.25)
t('Pulse', (P['J8'][0] + P['J9'][0]) / 2 + 0.5, P['J8'][1] - 10.85, 1.5, 'center', 0.25)
t('A', P['J8'][0] - 2.0, P['J8'][1] - 10.65, 1.5, 'center', 0.25); t('B', P['J9'][0] + 3.0, P['J9'][1] - 10.65, 1.5, 'center', 0.25)
# PC button J4 (pin 1 = SW+, pin 2 = SW-)
t('PC BUTTON', P['J4'][0] - 3.5, P['J4'][1] - 9.6, 1.5, 'center', 0.25)
t('+', P['J4'][0] - 4.0, P['J4'][1] + 0.5, j='center'); t('-', P['J4'][0] - 4.0, P['J4'][1] - 2.0, j='center')
# I2C row legend (right of J15) + supply notes
ix, iy = P['J15'][0] + 1.9 + 3.94, P['J15'][1]
for s, k in (('GND', 0), ('VCC', 1), ('SDA', 2), ('SCL', 3)): t(s, ix, iy - 2.5 * k + 0.5, j='center')
t('3.3V', (P['J6'][0] + P['J13'][0]) / 2, 89.1, 1.0, 'center', 0.2); t('5V', (P['J14'][0] + P['J15'][0]) / 2, 89.1, 1.0, 'center', 0.2)
t('I2C PORTS', (P['J6'][0] + P['J15'][0]) / 2, P['J6'][1] - 10.9, 1.5, 'center', 0.25)
# VEHICLE COMM box
t('VEHICLE COMM', 34.2, 46.7, 1.2, 'left', 0.2)
for r, x, y, a_, lab in JPS:
    if lab: t(lab, x, y - 1.5, 1.0, 'center')
for r, l, rr in (('JP4', 'CAN', 'K'), ('JP5', 'CAN', 'K'), ('JP8', '3V3', '5V')):
    x, y = P[r][0], P[r][1]; t(l, x - 2.6, y + 0.5, 1.0, 'right'); t(rr, x + 2.6, y + 0.5, 1.0, 'left')
t('D10>PC_BTN', 128.6, 67.9, 1.0, 'left')
t('I2C_PU', 80.6, 73.2, 1.0, 'center', 0.15, 90)
t('+3V3', 40.0, 55.0, 1.0, 'center'); t('GND', 44.5, 55.0, 1.0, 'center')
RECTS = [(33.8, 45.0, 80.0, 52.6)]

REFPOS = {'J1': (13, 7.0, 0), 'J2': (10, 27.6, 0), 'TVS1': (31, 46.3, 0), 'U2': (62.6, 79, 0)}
G = [(0, 1, 46, 52, '1 POWER ENTRY / 7A', '#d62728'), (50, 9, 67, 39, '3 RELAY HOLD', '#9467bd'),
     (61, 1, 93, 44, '2 5V BUCK (MCU)', '#ff7f0e'), (93, 8, 131, 48, '7 SENSOR SUPPLY', '#e377c2'),
     (0, 52, 33, 84, '5 VEHICLE BUS', '#2ca02c'), (33.8, 45, 80, 52.6, 'VEHICLE COMM CONFIG', '#7f7f7f'),
     (44, 60, 82, 91, '4 XIAO + PIN PARTS', '#1f77b4'), (82, 43, 140, 68, '8b SIGNAL PORTS', '#bcbd22'),
     (82, 68, 140, 91, '8a I2C + J5', '#17becf')]


def add_silk(path):
    b = pcbnew.LoadBoard(path)
    for s, x, y, size, j, th, ang in T:
        tx = pcbnew.PCB_TEXT(b); tx.SetText(s); tx.SetLayer(pcbnew.F_SilkS)
        tx.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size))); tx.SetTextThickness(pcbnew.FromMM(th))
        tx.SetHorizJustify({'left': pcbnew.GR_TEXT_H_ALIGN_LEFT, 'right': pcbnew.GR_TEXT_H_ALIGN_RIGHT}.get(j, pcbnew.GR_TEXT_H_ALIGN_CENTER))
        tx.SetVertJustify(pcbnew.GR_TEXT_V_ALIGN_BOTTOM if not ang else pcbnew.GR_TEXT_V_ALIGN_CENTER); tx.SetTextAngleDegrees(ang)
        tx.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(x), pcbnew.FromMM(y))); b.Add(tx)
    for x1, y1, x2, y2 in RECTS:
        r = pcbnew.PCB_SHAPE(b); r.SetShape(pcbnew.SHAPE_T_RECT); r.SetLayer(pcbnew.F_SilkS); r.SetWidth(pcbnew.FromMM(0.15))
        r.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(x1), pcbnew.FromMM(y1))); r.SetEnd(pcbnew.VECTOR2I(pcbnew.FromMM(x2), pcbnew.FromMM(y2))); b.Add(r)
    pcbnew.SaveBoard(path, b)


if __name__ == '__main__':
    build('/home/claude/pcb/pwrctrl/pwrctrl.net', OUT, W, H, P,
          ref_pos={k: (v[0] - P[k][0], v[1] - P[k][1], v[2]) for k, v in REFPOS.items()},
          hide_refs=('J10', 'J11'), silk_to_fab=('J10', 'J11'))
    add_silk(OUT)
    render(OUT, OUT.replace('pwrctrl_place.kicad_pcb', 'placement_v2.4.png'), groups=G,
           title='OpenCruise PWR-CTRL v2.4 placement candidate (140 x 91 mm) - NOT ROUTED', dpi=110)
    import os; os._exit(0)
