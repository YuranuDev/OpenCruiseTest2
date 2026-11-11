#!/usr/bin/env python3
"""PHU 回路図（書き起こし v0.1）を schemdraw で描く → b1〜b3 の SVG/PNG
部品番号と定数は sim/phu_hold.inc・phu_5v.inc と同じ。座標は手で決めている"""
import schemdraw
import schemdraw.elements as elm
import matplotlib
matplotlib.rcParams["font.family"] = ["Noto Sans CJK JP", "DejaVu Sans"]
schemdraw.config(fontsize=10, font="Noto Sans CJK JP")

def W(d, *pts):
    """折れ線の配線"""
    for a, b in zip(pts, pts[1:]):
        d += elm.Line().at(a).to(b)

def E(d, el, a, b, lab=None, loc=None, **kw):
    """2端子部品を a→b に置く"""
    e = el.at(a).to(b)
    if lab:
        e = e.label(lab, loc=loc, **kw) if loc else e.label(lab, **kw)
    d += e
    return e

def dot(d, p, open=False, lab=None, loc=None):
    e = elm.Dot(open=open).at(p)
    if lab: e = e.label(lab, loc=loc) if loc else e.label(lab)
    d += e

def gnd(d, p):
    d += elm.Ground().at(p)

def txt(d, p, s, fs=10, loc="left"):
    d += elm.Label().at(p).label(s, loc=loc, fontsize=fs)

def save(d, name):
    d.save(f"{name}.svg"); d.save(f"{name}.png", dpi=110)

# ------------------------------------------------------------------
# 図1：電源入力・メインリレー・自己保持・比較器の電源
# ------------------------------------------------------------------
with schemdraw.Drawing(show=False) as d:
    txt(d, (0, 2.0), "図1　電源入力・メインリレー・自己保持・比較器の電源（VCMP）", 13)
    # +B → F1 → K1 接点 → VSW
    dot(d, (0, 0), True, "+B（J1-1）", "left")
    E(d, elm.Fuse(), (0, 0), (3, 0), "F1 15A（ハーネス）", "top")
    E(d, elm.Switch(), (3.5, 0), (6, 0), "K1 接点", "top")
    W(d, (3, 0), (3.5, 0))
    W(d, (6, 0), (21, 0))
    txt(d, (6.6, 0.35), "VSW", 10)
    dot(d, (8, 0)); dot(d, (10.5, 0)); dot(d, (13, 0)); dot(d, (16.5, 0)); dot(d, (19.5, 0))
    E(d, elm.Zener().reverse(), (16.5, 0), (16.5, -2.4), "TVS1 SMCJ33A", "bottom")
    gnd(d, (16.5, -2.4))
    E(d, elm.Capacitor(), (19.5, 0), (19.5, -2.4), "C4 1µF/50V", "bottom")
    gnd(d, (19.5, -2.4))
    dot(d, (21, 0), True, "VSW → PC用DC-DC（F4 10A）\n→ 図3（F3 4A）\n→ 各ノード（ヒューズ）", "right")

    # 自己保持：VSW → Q2 → D8 → COILP
    W(d, (8, 0), (8, -1.0))
    q2 = elm.PFet(bulk=False).right().anchor("source").at((8, -1.0)).label("Q2 Si2309CDS", "left", ofst=(-0.2, 0))
    d += q2
    E(d, elm.Diode(), q2.drain, (8, -4.6), "D8 SS14", "left")
    # ゲート回路（右側）
    W(d, q2.gate, (10.5, q2.gate[1]))
    dot(d, (10.5, q2.gate[1]))
    E(d, elm.Resistor(), (10.5, q2.gate[1]), (10.5, 0), "R11 100k", "bottom")
    W(d, (10.5, q2.gate[1]), (13, q2.gate[1]))
    E(d, elm.Zener(), (13, q2.gate[1]), (13, 0), "ZD2 BZT52C12", "bottom")
    E(d, elm.Resistor(), (10.5, q2.gate[1]), (10.5, -4.4), "R12 10k", "bottom")
    q3 = elm.NFet(bulk=False).right().anchor("drain").at((10.5, -4.4)).label("Q3 2N7002", "left", ofst=(-0.2, 0))
    d += q3
    gnd(d, q3.source)
    W(d, q3.gate, (13.5, q3.gate[1]))
    dot(d, (13.5, q3.gate[1]), True, "OUTB（図2）\nR13 100kでGNDへ", "right")

    # ACC → F2 → D1 → COILP → コイル
    dot(d, (0, -6), True, "ACC（J1-2）", "left")
    E(d, elm.Fuse(), (0, -6), (2.5, -6), "F2 1A", "top")
    dot(d, (2.5, -6))
    E(d, elm.Diode(), (2.5, -6), (5, -6), "D1 SS14", "top")
    W(d, (5, -6), (8, -6), (8, -4.6))
    dot(d, (5, -6)); txt(d, (5.1, -5.6), "COILP", 9)
    E(d, elm.Inductor2(loops=3), (5, -6), (5, -9), "K1 コイル 360Ω", "left")
    gnd(d, (5, -9))
    W(d, (5, -6.0), (6.6, -6.0))
    dot(d, (6.6, -6))
    E(d, elm.Diode().reverse(), (6.6, -6), (6.6, -9), "D2 1N4148WS", "bottom")
    W(d, (6.6, -9), (5, -9))
    d += elm.Line().at((4.75, -0.35)).to((5, -5.6)).linestyle(":").color("gray")

    # VCMP：ACC/VSW → D3/D4 → R5 → ZD1・C3
    W(d, (2.5, -6), (2.5, -11))
    E(d, elm.Diode(), (2.5, -11), (5, -11), "D3 1N4148WS", "top")
    dot(d, (5.6, -11)); W(d, (5, -11), (5.6, -11))
    dot(d, (2.5, -13), True, "VSW", "left")
    E(d, elm.Diode(), (2.5, -13), (5, -13), "D4 1N4148WS", "bottom")
    W(d, (5, -13), (5.6, -13), (5.6, -11))
    E(d, elm.Resistor(), (5.6, -11), (8.6, -11), "R5 1k（1206）", "top")
    dot(d, (9.2, -11)); W(d, (8.6, -11), (9.2, -11))
    E(d, elm.Zener().reverse(), (9.2, -11), (9.2, -13.4), "ZD1 BZT52C15", "bottom")
    gnd(d, (9.2, -13.4))
    W(d, (9.2, -11), (12, -11)); dot(d, (12, -11))
    E(d, elm.Capacitor(), (12, -11), (12, -13.4), "C3 1µF/25V", "bottom")
    gnd(d, (12, -13.4))
    W(d, (12, -11), (14, -11))
    dot(d, (14, -11), True, "VCMP（図2へ）", "right")

    txt(d, (0, -15.2),
        "電圧監視（XIAOのADC）：ACC → R30 68k → AM → R31 6.8k → GND、AM → R32 10k → D0、C30 100nF（AM–GND）\n"
        "VSW → R33 68k → VM → R34 6.8k → GND、VM → R35 10k → D1、C31 100nF（比 11.0：35Vで3.18V）\n"
        "点線：K1のコイルと接点の連動。駐車中に電気が来るのは F1 と K1 接点の手前だけ（暗電流ゼロ）。", 10)
    save(d, "b1_relay")

# ------------------------------------------------------------------
# 図2：保持タイマー
# ------------------------------------------------------------------
with schemdraw.Drawing(show=False) as d:
    txt(d, (0, 3.0), "図2　保持タイマー（HNの電圧で保持を決める。ポンプが止まると約13〜40秒でOFF）", 13)
    # 基準電圧とヒステリシス
    dot(d, (0, 1.0), True, "VCMP", "left")
    E(d, elm.Resistor(), (0, 1.0), (3, 1.0), "R6 2.2k", "top")
    dot(d, (3.5, 1.0)); W(d, (3, 1.0), (3.5, 1.0)); txt(d, (3.6, 1.35), "VREF 2.495V", 9)
    E(d, elm.Zener().reverse(), (3.5, 1.0), (3.5, -1.6), "U2 TL431（K=REF）", "bottom")
    gnd(d, (3.5, -1.6))
    E(d, elm.Resistor(), (3.5, 1.0), (7, 1.0), "R7 100k", "top")
    dot(d, (7.5, 1.0)); W(d, (7, 1.0), (7.5, 1.0)); txt(d, (7.1, 1.35), "TH", 9)
    E(d, elm.Resistor(), (7.5, 1.0), (7.5, -1.6), "R8 100k", "bottom")
    gnd(d, (7.5, -1.6))
    # U1A：in1(−)=HN, in2(+)=TH
    u1a = elm.Opamp(leads=True).right().anchor("in2").at((9.5, 1.0)).label("U1A\nLM2903", "center")
    d += u1a
    W(d, (7.5, 1.0), u1a.in2)
    W(d, u1a.in1, (9.0, u1a.in1[1]), (9.0, 4.0))
    dot(d, (9.0, 4.0), True, "HN（下段）", "top")
    W(d, u1a.out, (14.2, u1a.out[1]))
    dot(d, (14.2, u1a.out[1])); txt(d, (14.3, u1a.out[1] - 0.45), "OUTA", 9)
    E(d, elm.Resistor(), (14.2, u1a.out[1]), (14.2, 4.0), "R10 10k", "bottom")
    dot(d, (14.2, 4.0), True, "VCMP", "top")
    W(d, (14.2, u1a.out[1]), (14.2, -1.0))
    E(d, elm.Resistor(), (14.2, -1.0), (8.4, -1.0), "R9 1M", "bottom")
    W(d, (8.4, -1.0), (8.4, 1.0)); dot(d, (8.4, 1.0))
    # U1B：in1(−)=OUTA, in2(+)=VREF
    u1b = elm.Opamp(leads=True).right().anchor("in1").at((15.6, u1a.out[1])).label("U1B\nLM2903", "center")
    d += u1b
    W(d, (14.2, u1a.out[1]), u1b.in1)
    W(d, u1b.in2, (15.0, u1b.in2[1]))
    dot(d, (15.0, u1b.in2[1]), True, "VREF", "left")
    W(d, u1b.out, (20.2, u1b.out[1]))
    dot(d, (20.2, u1b.out[1]))
    E(d, elm.Resistor(), (20.2, u1b.out[1]), (20.2, 4.0), "R14 10k", "bottom")
    dot(d, (20.2, 4.0), True, "VCMP", "top")
    W(d, (20.2, u1b.out[1]), (22, u1b.out[1]))
    dot(d, (22, u1b.out[1]), True, "OUTB → Q3（図1）", "right")

    # HN ノード（下段）
    y = -5.0
    dot(d, (8.6, y)); txt(d, (8.7, y + 0.35), "HN", 10)
    E(d, elm.Capacitor(), (8.6, y), (8.6, y - 2.6), "C1 10µF X7R（1206）", "bottom")
    gnd(d, (8.6, y - 2.6))
    W(d, (8.6, y), (11.2, y)); dot(d, (11.2, y))
    E(d, elm.Resistor(), (11.2, y), (11.2, y - 2.6), "R1 2.2M", "bottom")
    gnd(d, (11.2, y - 2.6))
    W(d, (11.2, y), (12.6, y)); dot(d, (12.6, y))
    E(d, elm.Resistor(), (12.6, y), (15.6, y), "R2 4.7M", "top")
    E(d, elm.Diode().reverse(), (15.6, y), (18.1, y), "D5 1N4148WS", "top")
    dot(d, (18.1, y), True, "ACC", "right")
    # 急速OFF
    E(d, elm.Resistor(), (12.6, y), (12.6, y - 2.6), "R22 1k", "bottom")
    q5 = elm.NFet(bulk=False).right().reverse().anchor("drain").at((12.6, y - 2.6)).label("Q5 2N7002", "right", ofst=(0.2, 0))
    d += q5
    gnd(d, q5.source)
    E(d, elm.Resistor(), q5.gate, (q5.gate[0] - 2.6, q5.gate[1]), "R20 1k", "bottom")
    dot(d, (q5.gate[0] - 2.6, q5.gate[1]), True, "XIAO D2 DISCH（Hで急速OFF）", "left")
    # チャージポンプ（左）
    W(d, (8.6, y), (7.2, y))
    E(d, elm.Diode().reverse(), (7.2, y), (5.0, y), "D6", "top")
    dot(d, (4.6, y)); W(d, (5.0, y), (4.6, y)); txt(d, (4.5, y + 0.35), "P", 9)
    E(d, elm.Diode().reverse(), (4.6, y), (4.6, y - 2.6), "D7（D6・D7=BAV99）", "bottom")
    gnd(d, (4.6, y - 2.6))
    E(d, elm.Capacitor(), (4.6, y), (2.0, y), "C2 100nF", "top")
    dot(d, (1.6, y)); W(d, (2.0, y), (1.6, y)); txt(d, (1.0, y + 0.35), "PD", 9)
    E(d, elm.Resistor(), (1.6, y), (1.6, y + 2.6), "R19 10k", "bottom")
    dot(d, (1.6, y + 2.6), True, "VCMP", "top")
    q4 = elm.NFet(bulk=False).right().reverse().anchor("drain").at((1.6, y)).label("Q4 2N7002", "right", ofst=(0.2, 0))
    d += q4
    gnd(d, q4.source)
    E(d, elm.Resistor(), q4.gate, (q4.gate[0] - 2.6, q4.gate[1]), "R17 1k", "bottom")
    dot(d, (q4.gate[0] - 2.6, q4.gate[1]), True, "XIAO D3 HOLD_CLK\n（約1kHzの矩形波）", "left")

    txt(d, (-4, -12.0),
        "Q4・Q5のゲートは100kでGNDへ（R18・R21）。U1（LM2903、2回路入り）の電源はVCMP。\n"
        "しきい値：HNが約1.76V（VCMP 12V時）を超えると保持ON、約1.19Vを下回るとOFF。\n"
        "HNの充電：ACC（R2経由、約8秒）またはポンプ（数十ms）。放電：R1（τ=22秒）またはQ5（約30ms）。", 10)
    save(d, "b2_timer")

# ------------------------------------------------------------------
# 図3：ハブ用5V
# ------------------------------------------------------------------
with schemdraw.Drawing(show=False) as d:
    txt(d, (0, 2.6), "図3　ハブ用5V（LM2576HVS-ADJ、5.0V。合計2A以下で使う）", 13)
    dot(d, (0, 0), True, "VSW", "left")
    E(d, elm.Fuse(), (0, 0), (2.5, 0), "F3 4A", "top")
    E(d, elm.Diode(), (2.5, 0), (5, 0), "D11 SS56", "top")
    W(d, (5, 0), (10, 0))
    dot(d, (5.6, 0)); txt(d, (5.3, 0.45), "VIN5", 9)
    E(d, elm.Capacitor(polar=True), (5.6, 0), (5.6, -2.6), "C10 100µF/63V", "bottom")
    gnd(d, (5.6, -2.6))
    dot(d, (8.2, 0))
    E(d, elm.Capacitor(), (8.2, 0), (8.2, -2.6), "C11 1µF/100V", "bottom")
    gnd(d, (8.2, -2.6))
    ic = elm.Ic(pins=[elm.IcPin(name="VIN", side="left", slot="2/2"),
                      elm.IcPin(name="ONOFF", side="left", slot="1/2"),
                      elm.IcPin(name="OUT", side="right", slot="2/2"),
                      elm.IcPin(name="FB", side="right", slot="1/2"),
                      elm.IcPin(name="GND", side="bottom")],
                pinspacing=1.4, edgepadH=0.5, edgepadW=0.5).right().anchor("VIN").at((10, 0)).label("U3 LM2576HVS-ADJ", "top")
    d += ic
    gnd(d, ic.GND)
    xo = ic.OUT[0] + 1.0
    W(d, ic.OUT, (xo, 0)); dot(d, (xo, 0)); txt(d, (xo, 0.45), "SW", 9)
    E(d, elm.Diode().reverse(), (xo, 0), (xo, -2.6), "D10 SS56", "bottom")
    gnd(d, (xo, -2.6))
    E(d, elm.Inductor2(loops=4), (xo, 0), (xo + 3, 0), "L1 100µH（Isat 3A以上）", "top")
    W(d, (xo + 3, 0), (xo + 10, 0))
    dot(d, (xo + 4, 0))
    E(d, elm.Capacitor(polar=True), (xo + 4, 0), (xo + 4, -2.6), "C12 1000µF/10V", "bottom")
    gnd(d, (xo + 4, -2.6))
    dot(d, (xo + 6.5, 0))
    E(d, elm.Capacitor(), (xo + 6.5, 0), (xo + 6.5, -2.6), "C13 10µF", "bottom")
    gnd(d, (xo + 6.5, -2.6))
    dot(d, (xo + 8.5, 0))
    dot(d, (xo + 10, 0), True, "+5V_HUB → CH334R×2・ポート電源スイッチ", "right")
    # FB 分圧（下段）
    yf = ic.FB[1]
    W(d, ic.FB, (ic.FB[0] + 0.4, yf), (ic.FB[0] + 0.4, -4.0), (xo + 1.6, -4.0))
    dot(d, (xo + 1.6, -4.0)); txt(d, (xo + 1.7, -3.6), "FB", 9)
    E(d, elm.Resistor(), (xo + 1.6, -4.0), (xo + 1.6, -6.6), "RFB2 1k", "bottom")
    gnd(d, (xo + 1.6, -6.6))
    E(d, elm.Resistor(), (xo + 1.6, -4.0), (xo + 8.5, -4.0), "RFB1 3.07k", "bottom")
    W(d, (xo + 8.5, -4.0), (xo + 8.5, 0))
    # UVLO（下段左）
    yo = ic.ONOFF[1]
    W(d, ic.ONOFF, (9.2, yo), (9.2, -4.0))
    dot(d, (9.2, -4.0)); txt(d, (9.3, -3.6), "ONOFF", 9)
    E(d, elm.Resistor(), (9.2, -4.0), (12.2, -4.0), "R40 100k → VIN5", "bottom")
    dot(d, (12.2, -4.0), True)
    E(d, elm.Capacitor(), (9.2, -4.0), (9.2, -6.6), "C40 10nF", "bottom")
    gnd(d, (9.2, -6.6))
    W(d, (9.2, -4.0), (7.0, -4.0))
    q6 = elm.BjtNpn(circle=True).right().anchor("collector").at((7.0, -4.0)).label("Q6 MMBT3904", "right", ofst=(0.3, -0.4))
    d += q6
    gnd(d, q6.emitter)
    xb = 5.0
    W(d, q6.base, (xb, q6.base[1])); dot(d, (xb, q6.base[1]))
    E(d, elm.Resistor(), (xb, q6.base[1]), (xb, q6.base[1] - 2.4), "R42 22k", "bottom")
    gnd(d, (xb, q6.base[1] - 2.4))
    E(d, elm.Resistor(), (xb, q6.base[1]), (2.0, q6.base[1]), "R41 10k", "top")
    E(d, elm.Zener(), (2.0, q6.base[1]), (-0.6, q6.base[1]), "ZD40 BZT52C4V7", "top")
    dot(d, (-0.6, q6.base[1]), True, "VIN5", "left")
    W(d, (xb, q6.base[1]), (xb, q6.base[1] + 1.7))
    E(d, elm.Resistor(), (xb, q6.base[1] + 1.7), (2.0, q6.base[1] + 1.7), "R43 100k", "top")
    dot(d, (2.0, q6.base[1] + 1.7), True, "+5V_HUB", "left")
    txt(d, (-0.6, -9.6),
        "低電圧停止（UVLO）：VIN5 約6.3Vで起動。R43で、5Vが出ている間はONを保ち、約4.1Vで停止（始動中の6Vでは止まらない）。\n"
        "出力：1.23V×(1＋3.07k/1k)=5.0V。D11は逆電圧（ISOパルス1・逆接）からU3を守る。", 10)
    save(d, "b3_5v")
print("ok")
