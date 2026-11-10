"""place_v21.py : PWR-CTRL v2.1 placement candidate (placement only, no routing).
Writes pwrctrl/placement_v2.1/pwrctrl_place.kicad_pcb ; the routed v2.0 board is not touched.
Placement intent per block is documented in pwrctrl/placement_v2.1/PLACEMENT_REVIEW.md
"""
import sys; sys.path.insert(0, '/home/claude/pcb/gen')
from pcbbuild import build
from render import render
W, H = 165, 91
OUT = '/home/claude/pcb/pwrctrl/placement_v2.1/pwrctrl_place.kicad_pcb'

# ---- MCU 5V buck cell (U1) : anchor X,Y = U1 ------------------------------------------------
# Hot loop: Cin(C5 ceramic + C4 bulk) -> VIN pin -> SW pin -> D11 -> GND -> Cin.  C5 left of VIN, D11 left of SW,
# C5 GND next to D11 anode.  C4 bulk directly above U1 (+ above the VIN pin, - above the GND tab).
# L1 below D11 (SW pad on top), FB divider under the U1 body on the opposite side from L1, fed from pin 4 under the body.
def buck(X, Y, ic, cin, cbulk, d, l, rfb_lo, rfb_hi, cff, cout_cer, cout_bulk):
    return {
        ic: (X, Y, 0),
        cin: (X - 8.0, Y - 3.2, 180),
        d: (X - 8.5, Y + 0.3, 180),
        l: (X - 9.0, Y + 9.4, 270),
        rfb_lo: (X - 2.4, Y + 6.6, 270),
        rfb_hi: (X - 0.4, Y + 6.6, 90),
        cff: (X + 1.6, Y + 6.6, 90),
        cbulk: (X - 2.5, Y - 10.0, 0),
        cout_cer: (X - 9.0, Y + 16.5, 270),
    }

P = {}
# 1 power entry / 7 A path (left edge, top)
P.update({
    'J1': (14.9, 16, 90), 'J2': (14.9, 33, 90), 'K1': (51, 13, 270),
    'TVS1': (31, 33, 90), 'C2': (39.5, 35.5, 90), 'C3': (39.5, 40.5, 90),
    'C1': (17, 42.5, 270),                       # VSW bulk right below J2 (VSW pad toward J2 pin 1)
    'TVS2': (17.6, 5.5, 0),                      # ACC_IN clamp at the J1 ACC/GND pins (connector entrance)
    'TP3': (10.5, 5.5), 'TP1': (11, 23), 'TP2': (40.5, 29.0), 'TP9': (44.0, 29.0),
    'R40': (29.5, 47.0, 0), 'LED1': (29.5, 49.3, 0),
})
# 3 relay hold (next to the K1 coil pins)
P.update({
    'D5': (55, 16.75, 270),                      # flyback diode right at coil A1/A2
    'D1': (59.5, 11.5, 0), 'D2': (59.5, 14.5, 0),
    'Q1': (58.2, 21.2, 180), 'R11': (61.6, 21.2, 90),
    'U5': (60, 26, 0), 'C10': (64.2, 25.05, 0),
    'R1': (52, 31, 90), 'R3': (54.5, 31, 90), 'C11': (57, 31, 270), 'R2': (59.5, 31, 270), 'ZD1': (62, 31, 270),
    'D3': (54.5, 35.5, 270), 'TP6': (64.8, 29.5), 'TP7': (64.8, 21.2),
    'F4': (65, 6, 270),                          # VSW_EXT PTC at the VSW tap (whole VSW_EXT run is fused)
})
# 2 MCU 5 V buck
P.update(buck(84, 17, 'U1', 'C5', 'C4', 'D11', 'L1', 'R51', 'R50', 'C8', 'C7', 'C6'))
P.update({
    'D7': (70.8, 5.2, 180), 'D9': (70.8, 9.2, 180),     # VIN5 OR diodes, cathodes at C4+
    'C6': (84.0, 30.5, 270),                            # 100 uF out, + pad under the FB divider top
    'D8': (78.4, 37.2, 90), 'R41': (74.5, 37.5, 180), 'LED2': (74.5, 39.8, 180), 'TP4': (78.4, 42.5),
})
# 7 sensor supply (U8 buck + U9 LDO), centre-right: closest to the loads (I2C ports on the right edge, ports on the
#   bottom edge, J5) ; VSW_EXT arrives at the top-left of the block (C40 +), SW node / L2 on the left, LDO + 3V3S on the right
X8, Y8 = 132, 50
P.update(buck(X8, Y8, 'U8', 'C41', 'C40', 'D12', 'L2', 'R53', 'R52', 'C44', 'C43', 'C42'))
P.update({
    'C42': (X8 + 0.8, Y8 + 13.5, 180),                 # 100 uF +5VS, + pad next to U9 IN
    'U9': (X8 + 10.65, Y8 + 11.2, 0), 'C45': (X8 + 17.2, Y8 + 11.2, 270), 'C46': (X8 + 19.6, Y8 + 11.2, 270),
    'TP12': (X8 + 18.4, Y8 + 15.4),
    'TP11': (X8 + 3.0, Y8 + 20.6), 'R42': (X8 + 7.5, Y8 + 19.6, 0), 'LED3': (X8 + 7.5, Y8 + 21.9, 0),
    'R43': (X8 + 13.0, Y8 + 19.6, 0), 'LED4': (X8 + 13.0, Y8 + 21.9, 0),
})
# 4 XIAO + parts on its pins (USB-C at the bottom edge)
P.update({
    'U2': (56, 77, 180), 'J10': (63.62, 84.62, 180), 'J11': (48.38, 69.38, 0),
    # right column: one part per J10 pin row (2.54 mm), series R / I2C pull-ups / ACC sense
    'R84': (68.5, 64.30, 0), 'R83': (68.5, 66.84, 0), 'R82': (68.5, 69.38, 0),
    'R31': (68.5, 71.92, 180), 'R30': (68.5, 74.46, 180), 'R81': (68.5, 77.00, 0), 'R80': (68.5, 79.54, 0),
    'ZD2': (68.6, 82.1, 180), 'C12': (67.4, 85.8, 270), 'R6': (69.2, 85.8, 270), 'R5': (72.7, 82.1, 180),
    'JP3': (71.4, 73.2, 90),
    # left column: decoupling at the XIAO 3V3 / 5V pins
    'C13': (44, 79.46, 180), 'C9': (44, 84.54, 180), 'TP5': (40.0, 79.5),
})
# 5 vehicle bus (left bottom) : J3 -> ESD/TVS -> transceiver -> pull-ups/jumpers -> JP4/JP5 -> XIAO
P.update({
    'J3': (4, 70, 90),
    'U7': (10.5, 66.25, 0), 'R62': (14, 66.25, 90), 'U6': (20, 66.2, 180), 'C14': (25, 66.2, 270),
    'R61': (27.2, 66.2, 270), 'JP1': (30.6, 68.11, 180), 'R60': (17.6, 70.3, 0),
    'TVS3': (10, 72, 270), 'C17': (13.2, 70.8, 270), 'TP8': (7.5, 79),
    'U4': (20, 75, 180), 'C15': (13.8, 75.64, 180), 'C16': (19.3, 79.6, 0),
    'R72': (25.2, 72.0, 270), 'JP6': (28.0, 72.82, 180), 'R73': (31.0, 72.4, 270),
    'R71': (26.0, 75.64, 180), 'R70': (26.0, 77.9, 180),
    'R20': (31.0, 76.4, 270), 'Q8': (32.0, 80.0, 0), 'R21': (28.0, 79.6, 180), 'R22': (35.0, 79.2, 270), 'JP7': (34.5, 83.5, 270),
    'D10': (12.0, 81.6, 0), 'R14': (13.5, 85.5, 0), 'F3': (19.0, 84.5, 90), 'Q9': (22.6, 86.0, 180), 'R23': (27.0, 87.0, 0),
    'JP4': (41.5, 71.92, 270), 'JP5': (38.5, 74.46, 270),
})
# 6 expansion header / PC power button
P.update({
    'J5': (81, 81, 180),
    'U3': (89.4, 73.5, 270), 'R12': (89.4, 70.2, 270), 'R13': (87.3, 70.2, 270), 'JP2': (88.35, 66.8, 0),
    'TP10': (86.0, 62.5),
})
# 8 ports: right edge = I2C (sensors), bottom edge = signal ports
P.update({
    'J6': (160.5, 18, 90), 'J7': (160.5, 33.4, 90), 'J12': (160.5, 48.8, 90), 'J13': (160.5, 64.2, 90), 'J14': (160.5, 79.6, 90),
    'J17': (73, 86.5, 0), 'J4': (87.9, 86.5, 0), 'J9': (97.8, 86.5, 0), 'J8': (112.7, 86.5, 0), 'J16': (127.65, 86.5, 0), 'J15': (145.1, 86.5, 0),
    'JP8': (126, 79, 0), 'JP9': (132, 79, 0),
    'H1': (4, 4), 'H2': (107, 4), 'H3': (4, 87), 'H4': (161, 87), 'H5': (161, 4),
})
REFPOS = {'L2': (117.5, 59.4, 90), 'L1': (69.5, 26.4, 90), 'J1': (13, 7.0, 0), 'J2': (10, 27.6, 0), 'J3': (4, 74.8, 0),
          'TVS1': (31, 46.3, 0), 'U2': (56, 79, 0)}

G = [(0, 1, 46, 52, '1 POWER ENTRY / 7A', '#d62728'), (50, 9, 67, 39, '3 RELAY HOLD', '#9467bd'),
     (67, 1, 93, 44, '2 5V BUCK (MCU)', '#ff7f0e'), (116, 34, 154, 74, '7 SENSOR SUPPLY 5VS/3V3S', '#e377c2'),
     (0, 59, 43.5, 91, '5 VEHICLE BUS (CAN/K)', '#2ca02c'), (36, 62, 75, 91, '4 XIAO + PIN PARTS', '#1f77b4'),
     (75, 55, 97, 83, '6 J5 / PC BTN', '#8c564b'), (156, 7, 165, 84, '8a I2C PORTS', '#17becf'),
     (69, 83, 156, 91, '8b SIGNAL PORTS', '#bcbd22')]

if __name__ == '__main__':
    b, comps, miss = build('/home/claude/pcb/pwrctrl/pwrctrl.net', OUT, W, H, P,
                           ref_pos={k: (v[0] - P[k][0], v[1] - P[k][1], v[2]) for k, v in REFPOS.items()},
                           hide_refs=('J10', 'J11'), silk_to_fab=('J10', 'J11'))
    print('missing', miss)
    render(OUT, OUT.replace('pwrctrl_place.kicad_pcb', 'placement_v2.1.png'), groups=G,
           title='OpenCruise PWR-CTRL v2.1 placement candidate (165 x 91 mm, ratsnest, GND omitted) - FOR REVIEW, NOT ROUTED', dpi=110)
