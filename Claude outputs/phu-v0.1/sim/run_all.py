#!/usr/bin/env python3
"""PHU（電源・ハブユニット）SPICE検証：全ケースを実行して判定し、レポートを作る

使い方：
  python run_all.py            全ケース
  python run_all.py tb3        名前が tb3 で始まるケースだけ
ngspice の場所は PATH、C:\\Spice64\\bin、環境変数 NGSPICE の順に探す。
結果：out/report.md（判定表＋波形）、out/results.json、out/*.png、out/*.log
"""
import os, re, sys, json, shutil, subprocess, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

def find_ngspice():
    if os.environ.get("NGSPICE"): return os.environ["NGSPICE"]
    for n in ("ngspice_con", "ngspice"):
        p = shutil.which(n)
        if p: return p
    w = r"C:\Spice64\bin\ngspice_con.exe"
    if os.path.exists(w): return w
    sys.exit("ngspice が見つかりません（環境変数 NGSPICE で指定してください）")

def pwl(points):
    if len(points) == 1: return f"DC {points[0][1]}"
    return "PWL(" + " ".join(f"{t} {v}" for t, v in points) + ")"

# ------------------------------------------------------------------
# 共通部分
# ------------------------------------------------------------------
MCU = """Vclk clkraw 0 PULSE(0 3.3 0 20u 20u 480u 1m)
Bhold HOLD_CLK 0 V = v(en)*v(clkraw) + v(stk)*3.3
"""
LOAD_PC = """* PC用DC-DCモジュール：入力470uF（推定）＋定電力65W（6V以下で停止）
Lpc VSW pc1 0.5u
RLpc VSW pc1 2
Rpcw pc1 pc2 10m
Cpc pc2 cpc 470u
Rpc cpc 0 50m
Bpc pc2 0 I = (65/max(v(pc2),6))*0.5*(1+tanh((v(pc2)-6.5)*4))
* ノード3台のフィールド側（合計141uF＋0.3A）
Rnw VSW nd 0.1
Cnd nd cnd 141u
Rcnd cnd 0 0.1
Rnd nd 0 40
"""
HOLD_ONLY_LOAD = """* 5V部を省略した場合のハブ5V分（定電力9.4W）
Bhub VSW 0 I = (9.4/max(v(VSW),6))*0.5*(1+tanh((v(VSW)-6.5)*4))
"""
OPT = ".options reltol=1e-3 abstol=1n vntol=1u method=gear\n"

def net_hold(name, desc, tstop, vb, acc, en, stk, dis, ch="10u", tmax="200u"):
    return f"""* {name}: {desc}
.param CH={ch}
.include phu_hold.inc
Vbat VBAT_IN 0 {pwl(vb)}
Vacc ACC_IN 0 {pwl(acc)}
Ven en 0 {pwl(en)}
Vstk stk 0 {pwl(stk)}
Vdis DISCH 0 {pwl(dis)}
{MCU}{LOAD_PC}{HOLD_ONLY_LOAD}{OPT}.tran 1m {tstop} 0 {tmax}
"""

def net_full(name, desc, sources, tran, five="phu_5v_avg.inc", rl5="3.33"):
    return f"""* {name}: {desc}
.param CH=10u
.include phu_hold.inc
.include {five}
{sources}
Vstk stk 0 0
Vdis DISCH 0 0
{MCU}{LOAD_PC}Rl5 V5 0 {rl5}
{OPT}{tran}
"""

# ------------------------------------------------------------------
# ケース定義：name, 説明, ネットリスト, 測定(.meas行), 波形, 判定
#   判定：(測定名, 演算子, 値, FAIL/WARN, 説明)
# ------------------------------------------------------------------
CASES = []
def case(name, desc, net, meas, waves, checks):
    CASES.append(dict(name=name, desc=desc, net=net, meas=meas, waves=waves, checks=checks))

ACC_10S = [(0,0),(0.1,0),(0.101,14.2),(10,14.2),(10.001,0)]

# ---- tb1 保持回路のシーケンス ----
case("tb1a_normal", "通常：ACC ON→マイコン起動→ACC OFF→PC終了30秒→DISCHでOFF",
     net_hold("tb1a","通常",50,[(0,12.6),(1,12.6),(1.01,14.2),(10,14.2),(10.01,12.6)],ACC_10S,
              [(0,0),(1.0,0),(1.001,1),(40,1),(40.001,0)],[(0,0)],[(0,0),(40,0),(40.001,3.3),(41,3.3),(41.001,0)]),
     ["t_on when v(VSW)=6 rise=1","t_off when v(VSW)=3 fall=last","vsw_hold min v(VSW) from=10.5 to=39.9"],
     ["v(VSW)","v(HN)","v(ACC)"],
     [("t_on","<",0.2,"FAIL","ACC ONから0.1秒以内にリレーON"),("vsw_hold",">",12,"FAIL","PC終了中（ACC OFF後）も保持"),
      ("t_off","<",40.2,"FAIL","DISCHから0.2秒以内にOFF")])
case("tb1b_mcu_dead", "マイコンが動かない（ポンプなし）：ACC 10秒 ON→OFF",
     net_hold("tb1b","マイコン故障",60,[(0,12.6)],ACC_10S,[(0,0)],[(0,0)],[(0,0)]),
     ["t_off when v(VSW)=3 fall=last"], ["v(VSW)","v(HN)","v(TH)"],
     [("t_off","<",70,"FAIL","ハードタイマーで必ず切れる（暗電流ゼロ）")])
case("tb1c_stuckH", "ACC OFF後にマイコンが固まる（ピンH固着）",
     net_hold("tb1c","固着",80,[(0,12.6)],ACC_10S,[(0,0),(1,0),(1.001,1),(15,1),(15.001,0)],[(0,0),(15,0),(15.001,1)],[(0,0)]),
     ["t_off when v(VSW)=3 fall=last"], ["v(VSW)","v(HN)"],
     [("t_off","<",75,"FAIL","固着から60秒以内に切れる")])
case("tb1d_crank", "始動：ACC 3秒断、+B 4.5V(50ms)→6V、マイコンも3.5秒リセット",
     net_hold("tb1d","始動",20,[(0,12.6),(5,12.6),(5.005,4.5),(5.05,4.5),(5.06,6.0),(8,6.0),(8.1,14.2)],
              [(0,0),(0.1,0),(0.101,12.6),(5,12.6),(5.001,0),(8,0),(8.001,14.2)],
              [(0,0),(1,0),(1.001,1),(5,1),(5.001,0),(8.5,0),(8.501,1)],[(0,0)],[(0,0)]),
     ["vsw_min min v(VSW) from=1 to=20","hn_min min v(HN) from=5 to=9"], ["v(VSW)","v(HN)","v(ACC)"],
     [("vsw_min",">",4.0,"FAIL","クランキング中もリレーを保持（VSW≒+B）")])
case("tb1e_crank_early", "ACC ON 0.5秒後（マイコン起動前）にクランキング",
     net_hold("tb1e","起動前の始動",15,[(0,12.6),(0.6,12.6),(0.605,4.5),(0.65,4.5),(0.66,6.0),(3.6,6.0),(3.7,14.2)],
              [(0,0),(0.1,0),(0.101,12.6),(0.6,12.6),(0.601,0),(3.6,0),(3.601,14.2)],[(0,0)],[(0,0)],[(0,0)]),
     ["t_drop when v(VSW)=3 fall=1","t_re when v(VSW)=6 rise=last"], ["v(VSW)","v(HN)"],
     [("t_re","<",3.8,"FAIL","始動後にACCが戻れば再びON")])
case("tb1f_cap_derated", "保持コンデンサがDCバイアスで4.7uFに減った場合（マイコン故障）",
     net_hold("tb1f","容量減",60,[(0,12.6)],ACC_10S,[(0,0)],[(0,0)],[(0,0)],ch="4.7u"),
     ["t_off when v(VSW)=3 fall=last"], ["v(VSW)","v(HN)"],
     [("t_off",">",12,"WARN","ACC OFF後に2秒以上は保持（瞬断対策）")])

# ---- tb2 電圧ごとの部品ストレス ----
for v in [9, 12, 14.2, 16, 24, 35]:
    case(f"tb2_{v}V", f"+B=ACC={v}V 定常（リレーON・ポンプ動作）",
         net_hold(f"tb2_{v}",f"{v}V",0.6,[(0,v)],[(0,0),(0.05,0),(0.051,v)],[(0,0),(0.2,0),(0.201,1)],[(0,0)],[(0,0)]),
         ["vsw find v(VSW) at=0.59","vcmp find v(VCMP) at=0.59","i431 find i(Vs431) at=0.59",
          "pz1 find par('v(VCMP)*i(VsZ1)') at=0.59","pr5 find par('(v(VCR)-v(VCMP))^2/1k') at=0.59",
          "vgs2 find par('v(QG)-v(VSW)') at=0.59","icoil find i(v.xk1.vs) at=0.59",
          "pcoil find par('i(v.xk1.vs)^2*360') at=0.59","hn find v(HN) at=0.59","adc0 find v(AM) at=0.59"],
         [], [("vsw",">",v-0.4,"FAIL","リレーがONしている"),("i431",">",1.0e-3,"WARN","TL431のImin（最大1mA）"),
              ("pz1","<",0.25,"WARN","ZD1 0.5Wの半分以下"),("pr5","<",0.25,"WARN","R5（1206 0.25W）"),
              ("vgs2",">",-15,"FAIL","Q2のVgs（±20V）"),("pcoil","<",0.72,"WARN","リレーコイル（定格0.4W、最大電圧180%＝1.3W相当の半分）"),
              ("adc0","<",3.3,"WARN","ADC入力3.3V以下")])

# ---- tb3 過渡（PHU全体、5Vは平均化モデル） ----
SRC_ON = "Vb VBAT_IN 0 {v}\nVacc ACC_IN 0 PWL(0 0 1m 0 1.01m {v})\nVen en 0 PWL(0 0 50m 0 50.001m 1)\n"
case("tb3a_inrush", "リレーが閉じたときの突入電流（電池10mΩ＋配線1µH）",
     net_full("tb3a","突入","Vb vb0 0 12.6\nRb vb0 vb1 10m\nLb vb1 VBAT_IN 1u\nVacc ACC_IN 0 PWL(0 0 1m 0 1.01m 12.6)\nVen en 0 0",
              ".tran 2u 40m 0 2u"),
     ["ipk max par('-i(Vb)') from=1m to=40m","i2t integ par('i(Vb)^2') from=1m to=40m","v5end find v(V5) at=39m"],
     ["-i(Vb)","v(VSW)","v(V5)"],
     [("ipk","<",80,"WARN","接点の突入電流（目安80A）"),("v5end",">",4.75,"FAIL","5Vが立ち上がる")])
case("tb3b_crank", "始動中の5V（+B 4.5V→6V 1秒、ACC断、マイコンはリセット）",
     net_full("tb3b","始動","Vb VBAT_IN 0 PWL(0 12.6 0.3 12.6 0.302 4.5 0.317 4.5 0.327 6 1.3 6 1.35 14.2)\n"
              "Vacc ACC_IN 0 PWL(0 0 1m 0 1.01m 12.6 0.3 12.6 0.301 0 1.3 0 1.301 14.2)\n"
              "Ven en 0 PWL(0 0 0.1 0 0.101 1 0.3 1 0.301 0 1.5 0 1.501 1)", ".tran 1m 1.6 0 100u"),
     ["v5min min v(V5) from=0.25 to=1.6","vswmin min v(VSW) from=0.25 to=1.6","v5end find v(V5) at=1.59"],
     ["v(VSW)","v(VIN5)","v(V5)"],
     [("vswmin",">",4.0,"FAIL","リレーを保持"),("v5min",">",4.4,"WARN","5Vが4.4V以上（ハブ・ノードがリセットしない）"),
      ("v5end",">",4.75,"FAIL","始動後に5Vが戻る")])
case("tb3c_iso2a", "ISO 7637-2 パルス2a相当（+50V／2Ω／50µs、電池なし）",
     net_full("tb3c","2a","Vpp pp 0 PWL(0 0 50m 0 50.001m 1 50.051m 1 50.061m 0)\n"
              "Bsrc 0 VBAT_IN I = (13.5 + 50*v(pp) - v(VBAT_IN))/(0.05 + 1.95*v(pp))\n"
              "Vacc ACC_IN 0 13.5\nVen en 0 PWL(0 0 5m 0 5.001m 1)", ".tran 0.5u 52m 0 0.5u"),
     ["vswmax max v(VSW) from=49.9m to=52m","itvs max i(VsTVS) from=49.9m to=52m","v5max max v(V5) from=49.9m to=52m"],
     ["v(VSW)","v(V5)"],
     [("vswmax","<",45,"FAIL","40V級の部品の定格以内"),("v5max","<",5.5,"FAIL","5Vに影響しない")])
case("tb3d_iso2a_noload", "パルス2a・PCモジュールなし（大きな入力コンデンサがない最悪条件）",
     net_full("tb3d","2a無負荷","Vpp pp 0 PWL(0 0 50m 0 50.001m 1 50.051m 1 50.061m 0)\n"
              "Bsrc 0 VBAT_IN I = (13.5 + 50*v(pp) - v(VBAT_IN))/(0.05 + 1.95*v(pp))\n"
              "Vacc ACC_IN 0 13.5\nVen en 0 PWL(0 0 5m 0 5.001m 1)\n.param NOPC=1", ".tran 0.5u 52m 0 0.5u").replace("Cpc pc2 cpc 470u","Cpc pc2 cpc 1n").replace("Cnd nd cnd 141u","Cnd nd cnd 1n"),
     ["vswmax max v(VSW) from=49.9m to=52m","vin5max max v(VIN5) from=49.9m to=52m","itvs max i(VsTVS) from=49.9m to=52m","vcmpmax max v(VCMP) from=49.9m to=52m"],
     ["v(VSW)","v(VIN5)","i(VsTVS)"],
     [("vswmax","<",60,"FAIL","LM2576HV（63V）以内"),("vcmpmax","<",30,"FAIL","LM2903の電源（36V）以内")])
case("tb3e_loaddump", "ロードダンプ（抑制後35V・0.2秒、電源側50mΩ）",
     net_full("tb3e","35V","Vb vb0 0 PWL(0 13.5 50m 13.5 55m 35 255m 35 300m 13.5)\nRld vb0 VBAT_IN 0.05\n"
              "Vacc ACC_IN 0 13.5\nVen en 0 PWL(0 0 5m 0 5.001m 1)", ".tran 0.2m 0.35 0 50u"),
     ["vswmax max v(VSW)","itvs max i(VsTVS)","v5max max v(V5) from=40m to=0.35","v5min min v(V5) from=40m to=0.35","vcmpmax max v(VCMP)"],
     ["v(VSW)","v(V5)","i(VsTVS)"],
     [("itvs","<",0.05,"FAIL","TVSが導通しない（焼けない）"),("v5max","<",5.25,"FAIL","5V正常"),("v5min",">",4.75,"FAIL","5V正常")])
case("tb3f_iso1", "ISO 7637-2 パルス1相当（電源断＋−75V／10Ω／2ms）",
     net_full("tb3f","パルス1","Vb vb0 0 13.5\nSbat vb0 VBAT_IN ctl 0 SWB\nVctl ctl 0 PWL(0 1 60m 1 60.001m 0)\n"
              "Vp1 vp 0 PWL(0 0 60m 0 60.001m -75 61m -27.6 62m -10.1 63m -3.7 64m 0)\nRp1 vp VBAT_IN 10\n"
              ".model SWB SW(VT=0.5 VH=0.1 RON=10m ROFF=1G)\nVacc ACC_IN 0 PWL(0 13.5 60m 13.5 60.001m 0)\n"
              "Ven en 0 PWL(0 0 5m 0 5.001m 1)", ".tran 5u 80m 0 5u"),
     ["vswmin min v(VSW) from=59m to=80m","vin5min min v(VIN5) from=59m to=80m","itvsmin min i(VsTVS) from=59m to=80m"],
     ["v(VSW)","v(VIN5)"],
     [("vin5min",">",-0.3,"FAIL","LM2576に逆電圧がかからない"),("vswmin",">",-2,"WARN","PC用モジュールにかかる逆電圧")])
case("tb3g_reverse", "逆接 −14V（駐車中に逆につないだ）",
     net_full("tb3g","逆接","Vb VBAT_IN 0 -14\nVacc ACC_IN 0 -14\nVen en 0 0", ".tran 1m 0.2 0 1m"),
     ["ibat find i(Vb) at=0.19","iacc find i(Vacc) at=0.19","vsw find v(VSW) at=0.19"], [],
     [("vsw",">",-0.5,"FAIL","リレーが閉じない（VSWに逆電圧が出ない）"),("iacc",">",-1e-3,"FAIL","ACCから流れる電流1mA未満")])
case("tb3h_dark", "暗電流（駐車中：+B 12.6V、ACC線は車両の負荷10Ωで0V）",
     net_full("tb3h","暗電流","Vb VBAT_IN 0 12.6\nVacc accs 0 0\nRacc accs ACC_IN 10\nVen en 0 0", ".tran 1m 0.5 0 1m"),
     ["ibat find i(Vb) at=0.49","iacc find i(Vacc) at=0.49","vsw find v(VSW) at=0.49"], [],
     [("ibat",">",-1e-6,"FAIL","+Bから1µA未満（リレーの開放抵抗1GΩ分だけ）"),("iacc",">",-1e-6,"FAIL","ACCから1µA未満")])

# ---- tb4 LM2576 スイッチング（TIモデル、短時間） ----
for vin, rl, tag in [(9,2.5,"2A"),(14.2,2.5,"2A"),(24,2.5,"2A"),(35,2.5,"2A"),(24,1.667,"3A")]:
    case(f"tb4_{vin}V_{tag}", f"LM2576（TIのスイッチングモデル）入力{vin}V・{tag}",
         f"""* tb4 {vin}V {tag}
.include ../models/discrete.lib
.include phu_5v.inc
Vsw VSW 0 PWL(0 0 1m {vin})
Rload V5 0 {rl}
.options reltol=1e-3 method=trap
.tran 2u 30m 0 1u
""", ["v5avg avg v(V5) from=25m to=30m","v5pp pp v(V5) from=25m to=30m","iin avg par('-i(Vsw)') from=25m to=30m"],
         ["v(V5)"], [("v5avg",">",4.85,"WARN" if tag=="3A" else "FAIL","5V（±3%）"),("v5pp","<",0.1,"WARN","リップル100mV以下")])

case("tb5_uvlo", "LM2576の低電圧停止（入力 0→12→0V）",
     """* tb5 UVLO
.include ../models/discrete.lib
.include phu_5v.inc
Vsw VSW 0 PWL(0 0 50m 12 100m 0)
Rload V5 0 3.33
.options reltol=1e-3 method=trap
.tran 5u 100m 0 5u
""", ["vin_on find v(VIN5) when v(ONOFF)=1.4 fall=1","vin_off find v(VIN5) when v(ONOFF)=1.4 rise=last"],
     ["v(VIN5)","v(V5)","v(ONOFF)"],
     [("vin_on","<",7.0,"FAIL","7V以下で起動"),("vin_off","<",5.0,"FAIL","クランキング（6V）では止まらない")])

# ------------------------------------------------------------------
def run_case(c, ng):
    t0 = time.time()
    path = os.path.join(OUT, c["name"] + ".cir")
    ctrl = [".control", "run"]
    if c["waves"]:
        ctrl.append(f"wrdata out/{c['name']}.dat " + " ".join(c["waves"]))
    for m in c["meas"]:
        mm = re.search(r"par\('([^']+)'\)", m)
        if mm:  # 式は let で変数にしてから測る（ngspiceの.control内measはpar()を使えない）
            var = m.split()[0] + "_x"
            ctrl.append(f"let {var} = {mm.group(1)}")
            m = m.replace(mm.group(0), var)
        ctrl.append("meas tran " + m)
    ctrl += [".endc", ".end"]
    open(path, "w", encoding="utf-8").write(c["net"] + "\n".join(ctrl) + "\n")
    r = subprocess.run([ng, "-b", os.path.join("out", c["name"] + ".cir")], cwd=HERE, capture_output=True, text=True)
    log = r.stdout + r.stderr
    open(os.path.join(OUT, c["name"] + ".log"), "w", encoding="utf-8").write(log)
    vals = {}
    for m in c["meas"]:
        k = m.split()[0]
        mm = re.search(rf"^{k}\s*=\s*([-\d.eE+]+)", log, re.M)
        vals[k] = float(mm.group(1)) if mm else None
    res = []
    for k, op, lim, sev, txt in c["checks"]:
        v = vals.get(k)
        ok = v is not None and ((v < lim) if op == "<" else (v > lim))
        res.append(dict(key=k, op=op, lim=lim, val=v, status="PASS" if ok else sev, text=txt))
    aborted = "too small" in log or "aborted" in log
    return dict(name=c["name"], desc=c["desc"], vals=vals, checks=res, aborted=aborted, sec=round(time.time()-t0, 1))

def plot(c):
    f = os.path.join(OUT, c["name"] + ".dat")
    if not c["waves"] or not os.path.exists(f): return None
    import numpy as np
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    d = np.loadtxt(f)
    if d.ndim != 2 or len(d) < 2: return None
    n = len(c["waves"])
    fig, axs = plt.subplots(n, 1, figsize=(8, 1.7*n), sharex=True)
    axs = axs if n > 1 else [axs]
    for i, w in enumerate(c["waves"]):
        axs[i].plot(d[:, 2*i], d[:, 2*i+1], lw=1)
        axs[i].set_ylabel(w, fontsize=8); axs[i].grid(alpha=.3)
    axs[-1].set_xlabel("time [s]")
    fig.suptitle(c["name"], fontsize=9); fig.tight_layout()
    png = os.path.join(OUT, c["name"] + ".png"); fig.savefig(png, dpi=90); plt.close(fig)
    return os.path.basename(png)

def main():
    ng = find_ngspice()
    sel = [c for c in CASES if not sys.argv[1:] or any(c["name"].startswith(a) for a in sys.argv[1:])]
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as ex:
        results = list(ex.map(lambda c: run_case(c, ng), sel))
    for c, r in zip(sel, results):
        r["png"] = plot(c)
    old = {}
    jp = os.path.join(OUT, "results.json")
    if os.path.exists(jp) and sys.argv[1:]:
        old = {r["name"]: r for r in json.load(open(jp, encoding="utf-8"))}
    for r in results: old[r["name"]] = r
    allr = [old[c["name"]] for c in CASES if c["name"] in old]
    json.dump(allr, open(jp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    cnt = {"PASS": 0, "WARN": 0, "FAIL": 0}
    for r in allr:
        for ch in r["checks"]: cnt[ch["status"]] += 1
    L = ["# PHU SPICE検証レポート", "",
         f"ケース {len(allr)}件・判定 {sum(cnt.values())}項目：**FAIL {cnt['FAIL']}件、WARN {cnt['WARN']}件**、PASS {cnt['PASS']}件", "",
         "| ケース | 内容 | 判定項目 | 値 | 基準 | 結果 |", "|---|---|---|---|---|---|"]
    for r in allr:
        first = True
        for ch in r["checks"]:
            v = "—" if ch["val"] is None else f"{ch['val']:.4g}"
            L.append(f"| {r['name'] if first else ''} | {r['desc'] if first else ''} | {ch['text']} | {v} | {ch['op']} {ch['lim']:g} | {ch['status']}{' ⚠中断' if r['aborted'] and first else ''} |")
            first = False
    L += ["", "## 測定値（全項目）", ""]
    for r in allr:
        L.append(f"- **{r['name']}**（{r['sec']}秒）：" + "、".join(f"{k}={v:.4g}" if v is not None else f"{k}=—" for k, v in r["vals"].items()))
    L += ["", "## 波形", ""]
    for r in allr:
        if r.get("png"): L.append(f"### {r['name']}\n{r['desc']}\n\n![{r['name']}]({r['png']})\n")
    open(os.path.join(OUT, "report.md"), "w", encoding="utf-8").write("\n".join(L))
    print(f"完了 {time.time()-t0:.0f}秒：FAIL {cnt['FAIL']} / WARN {cnt['WARN']} / PASS {cnt['PASS']}")
    for r in results:
        bad = [f"{c['key']}={c['val']}({c['status']})" for c in r["checks"] if c["status"] != "PASS"]
        print(f"  {r['name']:20s} {r['sec']:6.1f}s {'中断' if r['aborted'] else ''} {' '.join(bad)}")

if __name__ == "__main__":
    main()
