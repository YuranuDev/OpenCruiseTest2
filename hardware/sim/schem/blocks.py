"""blocks.py : easy-to-read functional schematics of the PWR-CTRL v2.4 blocks (schemdraw -> SVG).
Wires are drawn (signal flow left -> right, GND at the bottom) instead of the net-label style of the
KiCad sheet.  Part references and values match pwrctrl.kicad_sch (v2.4).
Run:  python blocks.py   -> b1.svg ... b7.svg (+ *_prev.png previews)
"""
import os, subprocess
import schemdraw
import schemdraw.elements as elm

HERE = os.path.dirname(os.path.abspath(__file__))
schemdraw.config(fontsize=11, unit=2.6, lw=1.3)
FS = 10   # small label font


def save(d, name):
    p = os.path.join(HERE, name + '.svg')
    d.save(p)
    s = open(p, encoding='utf-8').read()
    s = s.replace('stroke="black"', 'stroke="currentColor"').replace('fill="black"', 'fill="currentColor"')
    s = s.replace('stroke:black', 'stroke:currentColor').replace('fill:black', 'fill:currentColor')
    open(p, 'w', encoding='utf-8').write(s)
    subprocess.run(['rsvg-convert', '-w', '1500', '-b', 'white', p, '-o', os.path.join(HERE, name + '_prev.png')])


def W(d, a, b, how='-'):
    """wire a -> b ('-' straight, '-|' or '|-' L-shaped)"""
    d.add(elm.Wire(how).at(a).to(b))


def two(d, cls, a, b, lab=None, loc=None, **kw):
    e = cls(**kw).at(a).to(b)
    vert = abs(a[0] - b[0]) < 1e-6
    if lab and not vert:
        e = e.label(lab, loc, fontsize=FS) if loc else e.label(lab, fontsize=FS)
    r = d.add(e)
    if lab and vert:   # vertical part: put the label beside it, upright
        ym = (a[1] + b[1]) / 2
        if loc == 'left':
            d.add(elm.Label().at((a[0] - 0.55, ym)).label(lab, 'left', fontsize=FS, halign='right'))
        else:
            d.add(elm.Label().at((a[0] + 0.55, ym)).label(lab, 'right', fontsize=FS, halign='left'))
    return r


def G(d, p):
    d.add(elm.Ground().at(p))


def dot(d, p, lab=None, loc='top'):
    e = elm.Dot().at(p)
    if lab:
        e = e.label(lab, loc, fontsize=FS)
    d.add(e)


def tag(d, p, lab, direction='right', loc='right'):
    e = elm.Tag().at(p)
    e = getattr(e, direction)()
    d.add(e.label(lab, loc, fontsize=FS))


def text(d, p, s, fs=FS):
    d.add(elm.Label().at(p).label(s, 'right', fontsize=fs, halign='left'))


def IC(**kw):
    return elm.Ic(**kw).right()


def P(x, y):
    return (x, y)


# ------------------------------------------------------------------ B1 power input / 7 A path
def b1():
    with schemdraw.Drawing(show=False) as d:
        d.add(elm.Dot(open=True).at(P(0, 0)).label('J1-1  +B（常時12V）', 'left', fontsize=FS))
        W(d, P(0, 0), P(1.5, 0))
        d.add(elm.Switch().at(P(1.5, 0)).to(P(4.5, 0)).label('K1 接点（G2RL 16A）', 'top', fontsize=FS))
        dot(d, P(5.5, 0), 'VSW', 'bottom'); W(d, P(4.5, 0), P(5.5, 0))
        W(d, P(5.5, 0), P(8, 0)); dot(d, P(8, 0))
        two(d, elm.DiodeTVS, P(8, -2.6), P(8, 0), 'TVS1\nSM8S20A', 'right'); G(d, P(8, -2.6))
        W(d, P(8, 0), P(11, 0)); dot(d, P(11, 0))
        two(d, elm.Capacitor, P(11, 0), P(11, -2.6), 'C1 100µF\nC2,C3 10µF', 'right', polar=True); G(d, P(11, -2.6))
        W(d, P(11, 0), P(14, 0))
        d.add(elm.Dot(open=True).at(P(14, 0)).label('J2-1 → PC電源 DFR0946（最大7A）', 'right', fontsize=FS))
        # branches
        W(d, P(5.5, 0), P(5.5, 3.2)); dot(d, P(5.5, 1.6))
        W(d, P(5.5, 1.6), P(7, 1.6))
        two(d, elm.Fuse, P(7, 1.6), P(10, 1.6), 'F4 1.1A PTC', 'top')
        W(d, P(10, 1.6), P(11, 1.6)); tag(d, P(11, 1.6), 'VSW_EXT（センサー用電源・ポートの12V）')
        W(d, P(5.5, 3.2), P(7, 3.2))
        two(d, elm.Schottky, P(7, 3.2), P(10, 3.2), 'D7 SS34', 'top')
        W(d, P(10, 3.2), P(11, 3.2)); tag(d, P(11, 3.2), 'VIN5（U1 マイコン用5Vへ）')
        # ACC
        y = -5
        d.add(elm.Dot(open=True).at(P(0, y)).label('J1-2  ACC', 'left', fontsize=FS))
        W(d, P(0, y), P(3, y)); dot(d, P(3, y))
        two(d, elm.DiodeTVS, P(3, y - 2.6), P(3, y), 'TVS2\nSMAJ20A', 'right'); G(d, P(3, y - 2.6))
        W(d, P(3, y), P(7, y)); tag(d, P(7, y), 'ACC_IN（D9・D1・D3・R5へ）')
        d.add(elm.Dot(open=True).at(P(0, y - 4)).label('J1-3,4 / J2-2  GND', 'left', fontsize=FS))
        W(d, P(0, y - 4), P(1.5, y - 4)); G(d, P(1.5, y - 4))
        text(d, P(5, y - 4), '7Aの帰り道：J2-2 → J1-3/4（3mmの配線＋GNDベタ）')
    save(d, 'b1')


# ------------------------------------------------------------------ buck cell (U1 / U8)
def buck(d, ref, cin, cbulk, dname, lname, rh, rl, cff, cout, ccer, vin):
    ic = IC(pins=[elm.IcPin(name='VIN', pin='1', side='left', slot='2/2'),
                      elm.IcPin(name='EN', pin='5', side='left', slot='1/2'),
                      elm.IcPin(name='SW', pin='2', side='right', slot='2/2'),
                      elm.IcPin(name='FB', pin='4', side='right', slot='1/2'),
                      elm.IcPin(name='GND', pin='3,6', side='bottom')],
                w=3.0, pinspacing=1.4, edgepadH=0.6).label(f'{ref} XL7015', 'top', fontsize=11)
    d.add(ic.at(P(0, 0)))
    vin_p, en, sw, fb, gp = ic.VIN, ic.EN, ic.SW, ic.FB, ic.GND
    x0, y0 = vin_p
    # input
    W(d, vin_p, P(x0 - 1.4, y0)); dot(d, P(x0 - 1.4, y0))
    two(d, elm.Capacitor, P(x0 - 1.4, y0), P(x0 - 1.4, y0 - 2.4), cin, 'left'); G(d, P(x0 - 1.4, y0 - 2.4))
    W(d, P(x0 - 1.4, y0), P(x0 - 3.6, y0)); dot(d, P(x0 - 3.6, y0))
    two(d, elm.Capacitor, P(x0 - 3.6, y0), P(x0 - 3.6, y0 - 2.4), cbulk, 'left', polar=True); G(d, P(x0 - 3.6, y0 - 2.4))
    W(d, P(x0 - 3.6, y0), P(x0 - 4.6, y0)); tag(d, P(x0 - 4.6, y0), vin, 'left', 'left')
    W(d, en, P(en[0] - 0.8, en[1])); W(d, P(en[0] - 0.8, en[1]), P(en[0] - 0.8, en[1] - 0.3)); G(d, P(en[0] - 0.8, en[1] - 0.3))
    W(d, gp, P(gp[0], gp[1] - 0.6)); G(d, P(gp[0], gp[1] - 0.6))
    # SW node, diode, inductor
    xs, ys = sw
    W(d, sw, P(xs + 2.2, ys)); dot(d, P(xs + 2.2, ys), 'SW', 'top')
    two(d, elm.Schottky, P(xs + 2.2, ys - 2.4), P(xs + 2.2, ys), dname, 'right'); G(d, P(xs + 2.2, ys - 2.4))
    two(d, elm.Inductor2, P(xs + 2.2, ys), P(xs + 5.4, ys), lname, 'top', loops=3)
    vo = P(xs + 6.4, ys); W(d, P(xs + 5.4, ys), vo); dot(d, vo)
    two(d, elm.Capacitor, vo, P(vo[0], ys - 2.4), cout, 'right', polar=True); G(d, P(vo[0], ys - 2.4))
    vo2 = P(vo[0] + 2.4, ys); W(d, vo, vo2); dot(d, vo2)
    two(d, elm.Capacitor, vo2, P(vo2[0], ys - 2.4), ccer, 'right'); G(d, P(vo2[0], ys - 2.4))
    # FB: short net label at the pin, divider column hanging from the output
    W(d, fb, P(fb[0] + 0.6, fb[1])); text(d, P(fb[0] + 0.65, fb[1]), 'FB')
    vd = P(vo2[0] + 2.4, ys); W(d, vo2, vd); dot(d, vd)
    fbn = P(vd[0], ys - 2.6)
    two(d, elm.Resistor, vd, fbn, rh, 'left')
    dot(d, fbn); W(d, fbn, P(fbn[0] - 0.6, fbn[1])); text(d, P(fbn[0] - 1.6, fbn[1] + 0.35), 'FB')
    two(d, elm.Resistor, fbn, P(fbn[0], fbn[1] - 2.4), rl, 'left'); G(d, P(fbn[0], fbn[1] - 2.4))
    W(d, vd, P(vd[0] + 1.6, ys)); W(d, fbn, P(fbn[0] + 1.6, fbn[1]))
    two(d, elm.Capacitor, P(vd[0] + 1.6, ys), P(fbn[0] + 1.6, fbn[1]), cff, 'right')
    text(d, P(x0 - 4.6, ys + 3.0), 'Vout = 1.25 V × (1 + 10.7k / 3.3k) = 5.30 V、150 kHz。EN（5番）はGNDで常時動作')
    return P(vd[0] + 1.6, ys)


def b2():
    with schemdraw.Drawing(show=False) as d:
        out = buck(d, 'U1', 'C5\n1µF', 'C4\n470µF', 'D11\nSS34', 'L1 100µH', 'R50\n10.7k', 'R51\n3.3k', 'C8\n33nF',
                   'C6\n100µF', 'C7\n10µF', 'VIN5（D7:VSW / D9:ACC_IN）')
        a = P(out[0] + 0.0, out[1])
        W(d, a, P(a[0] + 1.0, a[1]))
        two(d, elm.Schottky, P(a[0] + 1.0, a[1]), P(a[0] + 4.0, a[1]), 'D8 SS34（逆流防止）', 'top')
        dot(d, P(a[0] + 4.6, a[1])); W(d, P(a[0] + 4.0, a[1]), P(a[0] + 4.6, a[1]))
        two(d, elm.Capacitor, P(a[0] + 4.6, a[1]), P(a[0] + 4.6, a[1] - 2.4), 'C9\n10µF', 'right'); G(d, P(a[0] + 4.6, a[1] - 2.4))
        W(d, P(a[0] + 4.6, a[1]), P(a[0] + 5.6, a[1])); tag(d, P(a[0] + 5.6, a[1]), '+5V → XIAO 5V・TJA1042 VCC')
    save(d, 'b2')


def b7():
    with schemdraw.Drawing(show=False) as d:
        out = buck(d, 'U8', 'C41\n10µF', 'C40\n100µF', 'D12\nSS34', 'L2 100µH', 'R52\n10.7k', 'R53\n3.3k', 'C44\n33nF',
                   'C42\n100µF', 'C43\n10µF', 'VSW_EXT（F4の後）')
        a = out
        W(d, a, P(a[0] + 1.2, a[1])); v = P(a[0] + 1.2, a[1]); dot(d, v, '+5VS', 'top')
        ldo = IC(pins=[elm.IcPin(name='IN', pin='3', side='left'), elm.IcPin(name='OUT', pin='2', side='right'),
                           elm.IcPin(name='GND', pin='1', side='bottom')], w=2.4, pinspacing=1).label('U9 AMS1117-3.3', 'top', fontsize=10)
        d.add(ldo.at(P(v[0] + 1.0, v[1])).anchor('IN'))
        W(d, v, ldo.IN)
        W(d, ldo.GND, P(ldo.GND[0], ldo.GND[1] - 0.5)); G(d, P(ldo.GND[0], ldo.GND[1] - 0.5))
        o = P(ldo.OUT[0] + 1.2, ldo.OUT[1]); W(d, ldo.OUT, o); dot(d, o, '+3V3S', 'top')
        two(d, elm.Capacitor, o, P(o[0], o[1] - 2.4), 'C45,C46\n10µF×2', 'right'); G(d, P(o[0], o[1] - 2.4))
        W(d, o, P(o[0] + 2.6, o[1])); tag(d, P(o[0] + 2.6, o[1]), 'I2C1〜4（2番）・GPS（JP8=3V3）')
        W(d, v, P(v[0], v[1] + 2.2)); W(d, P(v[0], v[1] + 2.2), P(o[0] + 2.6, v[1] + 2.2))
        tag(d, P(o[0] + 2.6, v[1] + 2.2), 'I2C5・6、PULSE-A/B・AUX（2番）、GPS（JP8=5V）、J5-13')
    save(d, 'b7')


# ------------------------------------------------------------------ B3 relay hold
def b3():
    with schemdraw.Drawing(show=False) as d:
        # coil, flyback, low-side switch
        cp, cn = P(20, 4), P(20, 1)
        two(d, elm.Inductor2, cp, cn, 'K1 コイル\n360Ω', 'left', loops=3)
        dot(d, cp, 'COIL_P', 'top'); dot(d, cn)
        W(d, cp, P(22.2, 4)); W(d, cn, P(22.2, 1))
        two(d, elm.Diode, P(22.2, 1), P(22.2, 4), 'D5', 'right')
        q = elm.NFet().right().reverse().at(cn).anchor('drain').label('Q1\nBSS138', 'right', fontsize=FS)
        d.add(q)
        G(d, q.source)
        hg = P(17, q.gate[1]); W(d, q.gate, hg); dot(d, hg, 'HOLD_G', 'top')
        two(d, elm.Resistor, hg, P(17, hg[1] - 2.4), 'R11\n100k', 'left'); G(d, P(17, hg[1] - 2.4))
        # OR into COIL_P
        two(d, elm.Diode, P(14.6, 4), P(17.2, 4), 'D1', 'top'); W(d, P(17.2, 4), cp)
        tag(d, P(14.6, 4), 'ACC_IN', 'left', 'left')
        two(d, elm.Diode, P(14.6, 5.8), P(17.2, 5.8), 'D2', 'top'); W(d, P(17.2, 5.8), P(18.2, 5.8)); W(d, P(18.2, 5.8), P(18.2, 4)); dot(d, P(18.2, 4))
        tag(d, P(14.6, 5.8), 'VSW', 'left', 'left')
        # Schmitt buffer
        u = IC(pins=[elm.IcPin(name='A', side='left'), elm.IcPin(name='Y', side='right')], w=2.2, h=1.4).label('U5 74LVC1G17\n(シュミット)', 'bottom', fontsize=9)
        d.add(u.at(P(15.0, hg[1])).anchor('Y'))
        W(d, u.Y, hg)
        hn = P(u.A[0] - 1.2, u.A[1]); W(d, u.A, hn); dot(d, hn, 'HOLD_N', 'top')
        xs = [hn[0] - 1.8, hn[0] - 3.6, hn[0] - 5.4]
        W(d, hn, P(xs[2] - 1.6, hn[1]))
        for x, (cls, lab, kw) in zip(xs, [(elm.Capacitor, 'C11\n10µF', {'polar': True}), (elm.Resistor, 'R2\n1M', {}), (elm.Zener, 'ZD1\n3.6V', {})]):
            dot(d, P(x, hn[1]))
            if cls is elm.Zener:
                two(d, cls, P(x, hn[1] - 2.4), P(x, hn[1]), lab, 'right')
            else:
                two(d, cls, P(x, hn[1]), P(x, hn[1] - 2.4), lab, 'right', **kw)
            G(d, P(x, hn[1] - 2.4))
        n4 = P(xs[2] - 1.6, hn[1]); dot(d, n4)
        two(d, elm.Resistor, P(n4[0] - 2.6, n4[1]), n4, 'R1 1k', 'top')
        tag(d, P(n4[0] - 2.6, n4[1]), 'HOLD（XIAO D1）', 'left', 'left')
        W(d, n4, P(n4[0], n4[1] + 1.8))
        two(d, elm.Resistor, P(n4[0] - 2.6, n4[1] + 1.8), P(n4[0], n4[1] + 1.8), 'R3 470k', 'top')
        two(d, elm.Diode, P(n4[0] - 5.0, n4[1] + 1.8), P(n4[0] - 2.6, n4[1] + 1.8), 'D3', 'top')
        tag(d, P(n4[0] - 5.0, n4[1] + 1.8), 'ACC_IN', 'left', 'left')
        text(d, P(n4[0] - 6, hn[1] - 4.2), 'ACCだけでも（D3・R3）、マイコンのHOLD=Hでも、HOLD_Nが上がってリレーが入る。\n'
                                          'マイコンが止まる（Hi-Z）と、C11がR2・ZD1で放電し、約8秒後にリレーが切れる（暗電流ゼロ）。')
    save(d, 'b3')


# ------------------------------------------------------------------ B4 XIAO pin map
def b4():
    with schemdraw.Drawing(show=False) as d:
        left = ['5V', 'GND', '3V3', 'D10', 'D9', 'D8', 'D7']
        right = ['D0', 'D1', 'D2', 'D3', 'D4', 'D5', 'D6']
        pins = [elm.IcPin(name=n, side='left') for n in left] + [elm.IcPin(name=n, side='right') for n in right]
        ic = IC(pins=pins, w=3.6, pinspacing=1.3, edgepadH=0.6).label('XIAO ESP32-S3（ソケット）', 'top', fontsize=11)
        d.add(ic.at(P(0, 0)))

        def rser(n, ref, net):
            a = getattr(ic, n)
            W(d, a, P(a[0] + 0.6, a[1]))
            two(d, elm.Resistor, P(a[0] + 0.6, a[1]), P(a[0] + 3.0, a[1]), ref, 'top', **{})
            tag(d, P(a[0] + 3.0, a[1]), net)

        def plain(n, net):
            a = getattr(ic, n)
            W(d, a, P(a[0] + 3.0, a[1])); tag(d, P(a[0] + 3.0, a[1]), net)
        rser('D6', 'R82 1kΩ', 'P_D6（TX）→ GPSのRX（J16）・J5')
        plain('D5', 'SCL → I2C1〜6・J5（R31 1.2kでプルアップ、JP3）')
        plain('D4', 'SDA → I2C1〜6・J5（R30 1.2kでプルアップ、JP3）')
        rser('D3', 'R81 1kΩ', 'P_D3 → PULSE-B（J9）・J5')
        rser('D2', 'R80 1kΩ', 'P_D2 → PULSE-A（J8）・J5')
        plain('D1', 'HOLD → リレー保持回路（R1）')
        a = ic.D0
        W(d, a, P(a[0] + 1.0, a[1])); dot(d, P(a[0] + 1.0, a[1]), 'ACC_SENSE', 'bottom')
        for i, (cls, lab) in enumerate([(elm.Capacitor, 'C12\n100nF'), (elm.Resistor, 'R6\n6.8k'), (elm.Zener, 'ZD2\n3.6V')]):
            x = a[0] + 1.0 + 1.7 * i
            if i:
                W(d, P(x - 1.7, a[1]), P(x, a[1])); dot(d, P(x, a[1]))
            if cls is elm.Zener:
                two(d, cls, P(x, a[1] - 2.2), P(x, a[1]), lab, 'right')
            else:
                two(d, cls, P(x, a[1]), P(x, a[1] - 2.2), lab, 'right')
            G(d, P(x, a[1] - 2.2))
        x = a[0] + 1.0 + 3.4
        two(d, elm.Resistor, P(x, a[1]), P(x + 2.6, a[1]), 'R5 47k', 'top'); tag(d, P(x + 2.6, a[1]), 'ACC_IN（分圧 1/7.91）')

        def lser(n, ref, net):
            a = getattr(ic, n)
            W(d, a, P(a[0] - 0.6, a[1]))
            if ref:
                two(d, elm.Resistor, P(a[0] - 3.0, a[1]), P(a[0] - 0.6, a[1]), ref, 'top')
            else:
                W(d, P(a[0] - 0.6, a[1]), P(a[0] - 3.0, a[1]))
            tag(d, P(a[0] - 3.0, a[1]), net, 'left', 'left')
        lser('D7', 'R83 1kΩ', 'GPSのTX → P_D7（RX）')
        lser('D8', None, 'VEH_TX → JP4（CAN｜K）')
        lser('D9', None, 'VEH_RX ← JP5（CAN｜K）')
        lser('D10', 'R84 1kΩ', 'P_D10 → AUX・PPS（JP9）')
        a = ic.D10; dot(d, P(a[0] - 0.35, a[1])); d.add(elm.Label().at(P(a[0] - 0.3, a[1] - 0.5)).label('JP2→PC_BTN（R84の前）', 'left', fontsize=FS, halign='right'))
        for n, cap, net in (('3V3', 'C13\n10µF', '+3V3（XIAO内蔵LDO）'), ('5V', 'C9\n10µF', '+5V（U1 → D8）')):
            a = getattr(ic, n)
            W(d, a, P(a[0] - 1.2, a[1])); dot(d, P(a[0] - 1.2, a[1]))
            two(d, elm.Capacitor, P(a[0] - 1.2, a[1]), P(a[0] - 1.2, a[1] - 1.1), cap, 'right'); G(d, P(a[0] - 1.2, a[1] - 1.1))
            W(d, P(a[0] - 1.2, a[1]), P(a[0] - 3.0, a[1])); tag(d, P(a[0] - 3.0, a[1]), net, 'left', 'left')
        a = getattr(ic, 'GND'); W(d, a, P(a[0] - 0.6, a[1])); G(d, P(a[0] - 0.6, a[1]))
        text(d, P(-9, -6.6), '・R80〜R84（直列抵抗1kΩ、v2.4.1）はピンの直近。12Vの誤配線でも8mAで3.3Vは上がらない（tb11）\n・JP2（PCボタン）はR84の前（IO_D10）につながる。1-Wireのプルアップは4.7k以上、GPSは460800bps以下\n・USB-Cは基板の下端に出す')
    save(d, 'b4')


# ------------------------------------------------------------------ B5 vehicle bus
def b5():
    with schemdraw.Drawing(show=False) as d:
        # ---- CAN ----
        d.add(elm.Dot(open=True).at(P(0, 0)).label('J3-2 CANH', 'left', fontsize=FS))
        d.add(elm.Dot(open=True).at(P(0, -2.4)).label('J3-3 CANL', 'left', fontsize=FS))
        u7 = IC(pins=[elm.IcPin(name='H', pin='2', side='top'), elm.IcPin(name='L', pin='1', side='bottom'),
                          elm.IcPin(name='GND', pin='3', side='right')], w=1.6, h=1.4, leadlen=0.5).label('U7\nPESD1CAN', 'left', fontsize=9, ofst=(-0.2, 0))
        d.add(u7.at(P(3.2, 0)).anchor('H'))
        W(d, P(0, 0), u7.H); W(d, P(0, -2.4), u7.L); dot(d, u7.H); dot(d, u7.L)
        W(d, u7.GND, P(u7.GND[0] + 0.6, u7.GND[1])); W(d, P(u7.GND[0] + 0.6, u7.GND[1]), P(u7.GND[0] + 0.6, u7.GND[1] - 0.2)); G(d, P(u7.GND[0] + 0.6, u7.GND[1] - 0.2))
        W(d, u7.H, P(8, 0)); W(d, u7.L, P(8, -2.4)); dot(d, P(8, 0)); dot(d, P(8, -2.4))
        two(d, elm.Resistor, P(8, 0), P(8, -2.4), 'R62 120Ω\n（未実装）', 'right')
        can = IC(pins=[elm.IcPin(name='CANH', pin='7', side='left', slot='2/2'), elm.IcPin(name='CANL', pin='6', side='left', slot='1/2'),
                           elm.IcPin(name='TXD', pin='1', side='right', slot='3/3'), elm.IcPin(name='RXD', pin='4', side='right', slot='2/3'),
                           elm.IcPin(name='STB', pin='8', side='right', slot='1/3'),
                           elm.IcPin(name='VCC', pin='3', side='top', slot='1/3'), elm.IcPin(name='VIO', pin='5', side='top', slot='2/3'),
                           elm.IcPin(name='GND', pin='2', side='bottom')], w=3.6, pinspacing=2.4, edgepadH=1.0)
        d.add(can.at(P(11.5, 0)).anchor('CANH'))
        W(d, P(8, 0), can.CANH, '-|'); W(d, P(8, -2.4), can.CANL, '-|')
        W(d, can.GND, P(can.GND[0], can.GND[1] - 0.4)); G(d, P(can.GND[0], can.GND[1] - 0.4))
        text(d, P(can.CANL[0] - 3.2, can.GND[1] - 0.2), 'U6 TJA1042T/3（バス ±58V）', 11)
        W(d, can.VCC, P(can.VCC[0], can.VCC[1] + 0.6)); text(d, P(can.VCC[0] - 1.4, can.VCC[1] + 1.0), '+5V（C14）')
        W(d, can.VIO, P(can.VIO[0], can.VIO[1] + 0.6)); text(d, P(can.VIO[0] - 0.2, can.VIO[1] + 1.0), '+3V3（C18）')
        for n, s in (('TXD', 'CAN_TXD ─ R61 10k↑ ─ JP1 CAN_TX ─ JP4 → D8'), ('RXD', 'CAN_RXD ─ JP5 → D9'), ('STB', 'R60 10k → GND（STB=L：通常動作）')):
            a = getattr(can, n); W(d, a, P(a[0] + 0.8, a[1])); text(d, P(a[0] + 0.9, a[1]), s)
        # ---- K-Line ----
        y = -9.6
        d.add(elm.Dot(open=True).at(P(0, y)).label('J3-1 K-LINE', 'left', fontsize=FS))
        W(d, P(0, y), P(3.2, y)); dot(d, P(3.2, y))
        two(d, elm.DiodeTVS, P(3.2, y - 2.6), P(3.2, y), 'TVS3\nSMAJ24A', 'right'); G(d, P(3.2, y - 2.6))
        W(d, P(3.2, y), P(6.0, y)); dot(d, P(6.0, y))
        two(d, elm.Capacitor, P(6.0, y), P(6.0, y - 2.6), 'C17\n220pF', 'right'); G(d, P(6.0, y - 2.6))
        W(d, P(6.0, y), P(8.6, y)); dot(d, P(8.6, y))
        two(d, elm.Resistor, P(8.6, y), P(8.6, y - 2.6), 'R14\n510Ω 1W', 'right')
        two(d, elm.Diode, P(8.6, y - 5.0), P(8.6, y - 2.6), 'D10', 'left'); tag(d, P(8.6, y - 5.0), 'VSW', 'down', 'right')
        W(d, P(8.6, y), P(12.4, y)); dot(d, P(12.4, y))
        two(d, elm.Fuse, P(12.4, y), P(12.4, y - 2.6), 'F3\n0.1A PTC', 'right')
        q = elm.NFet().right().reverse().at(P(12.4, y - 2.6)).anchor('drain').label('Q9\n2N7002K', 'right', fontsize=9)
        d.add(q); G(d, q.source)
        g0 = P(q.gate[0] - 0.5, q.gate[1]); g1 = P(g0[0], y - 6.8); W(d, q.gate, g0); W(d, g0, g1); W(d, g1, P(g1[0] + 3.2, g1[1])); tag(d, P(g1[0] + 3.2, g1[1]), 'KGATE（JP7 K_DRV ← Q8）')
        lin = IC(pins=[elm.IcPin(name='LIN', pin='6', side='left'),
                           elm.IcPin(name='TXD', pin='4', side='right', slot='3/3'), elm.IcPin(name='RXD', pin='1', side='right', slot='2/3'),
                           elm.IcPin(name='SLP', pin='2', side='right', slot='1/3'),
                           elm.IcPin(name='VBAT', pin='7', side='top', slot='1/2'), elm.IcPin(name='GND', pin='5', side='bottom', slot='1/2')], w=3.2, pinspacing=1.2, edgepadH=0.9)
        d.add(lin.at(P(16.5, y)).anchor('LIN'))
        W(d, P(12.4, y), lin.LIN)
        W(d, lin.GND, P(lin.GND[0], lin.GND[1] - 0.4)); G(d, P(lin.GND[0], lin.GND[1] - 0.4))
        text(d, P(lin.GND[0] + 0.8, lin.GND[1] - 0.7), 'U4 TJA1021（K-Line）', 11)
        W(d, lin.VBAT, P(lin.VBAT[0], lin.VBAT[1] + 0.6)); text(d, P(lin.VBAT[0] + 0.2, lin.VBAT[1] + 0.45), 'VSW（C15・C16）')
        for n, s in (('TXD', 'KL_TXD ─ R72 10k↑ ─ JP6 K_TX ─ JP4 → D8'), ('RXD', 'KL_RXD ─ R70 4.7k↑ ─ JP5 → D9'), ('SLP', 'R71 10k↑3V3（常時動作）')):
            a = getattr(lin, n); W(d, a, P(a[0] + 0.8, a[1])); text(d, P(a[0] + 0.9, a[1]), s)
        text(d, P(-2.5, y - 9.0), '・保護素子（U7・TVS3）がJ3の次にあり、ICや負荷はすべてその後ろ（線は保護素子を経由してからICへ）\n'
                                  '・K直接駆動（5ボー初期化用）：KL_TXS → R20 → Q8 → JP7 K_DRV → Q9 → F3 → K-LINE')
    save(d, 'b5')


# ------------------------------------------------------------------ B6 I2C pull-up / PC button / J5
def b6():
    with schemdraw.Drawing(show=False) as d:
        tag(d, P(0, 0), '+3V3', 'left', 'left')
        two(d, elm.Line, P(0, 0), P(1.6, 0), 'JP3 I2C_PU', 'top')
        dot(d, P(1.6, 0)); W(d, P(1.6, 0), P(3.4, 0)); tag(d, P(3.4, 0), 'I2C_PU')
        two(d, elm.Resistor, P(1.6, 0), P(1.6, -2.4), 'R30\n1.2k', 'left'); dot(d, P(1.6, -2.4))
        two(d, elm.Resistor, P(3.4, -3.8), P(3.4, -6.2), 'R31\n1.2k', 'right'); dot(d, P(3.4, -3.8))
        tag(d, P(3.4, -6.2), 'I2C_PU（JP3の後）', 'down', 'bottom')
        W(d, P(-1, -2.4), P(8, -2.4)); tag(d, P(-1, -2.4), 'SDA（XIAO D4）', 'left', 'left'); tag(d, P(8, -2.4), 'I2C1〜6 の3番・J5-5')
        W(d, P(-1, -3.8), P(8, -3.8)); tag(d, P(-1, -3.8), 'SCL（XIAO D5）', 'left', 'left'); tag(d, P(8, -3.8), 'I2C1〜6 の4番・J5-6')
        y = -10.5
        tag(d, P(0, y), 'D10（XIAO）', 'left', 'left')
        two(d, elm.Line, P(0, y), P(1.8, y), 'JP2 PC_BTN', 'top')
        dot(d, P(1.8, y), 'PWRB', 'bottom')
        two(d, elm.Resistor, P(1.8, y), P(4.6, y), 'R12 330Ω', 'top')
        o = elm.Optocoupler().at(P(4.6, y)).anchor('anode').label('U3 PC817', 'top', fontsize=FS)
        d.add(o)
        two(d, elm.Resistor, P(1.8, y), P(1.8, y - 2.4), 'R13\n100k', 'left'); G(d, P(1.8, y - 2.4))
        W(d, o.cathode, P(o.cathode[0], o.cathode[1] - 0.6)); G(d, P(o.cathode[0], o.cathode[1] - 0.6))
        W(d, o.collector, P(o.collector[0] + 1.6, o.collector[1])); tag(d, P(o.collector[0] + 1.6, o.collector[1]), 'J4-1 SW+（PCの電源ボタン）')
        W(d, o.emitter, P(o.emitter[0] + 1.6, o.emitter[1])); tag(d, P(o.emitter[0] + 1.6, o.emitter[1]), 'J4-2 SW−')
        text(d, P(-3, y - 4.6), 'J5（2×10、デバッグ・拡張）\n  1 ACC_SENSE  2 HOLD  3 P_D2  4 P_D3  5 SDA  6 SCL  7 P_D6  8 P_D7\n  9 VEH_TX  10 VEH_RX  11 P_D10  12 +3V3  13 +5VS  14 VSW_EXT  15〜20 GND')
    save(d, 'b6')


if __name__ == '__main__':
    for f in (b1, b2, b3, b4, b5, b6, b7):
        f()
    print('done')
