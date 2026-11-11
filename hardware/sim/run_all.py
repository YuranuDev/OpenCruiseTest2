#!/usr/bin/env python3
"""PWR-CTRL v2.4.1 SPICE verification runner.

    python run_all.py            # run every case, write out/report.md and out/*.png
    python run_all.py tb3        # run only cases whose name starts with "tb3"

Needs: ngspice (Windows: ngspice_con.exe), Python 3 with numpy + matplotlib.
Set the environment variable NGSPICE to the ngspice executable if it is not on PATH.

Each CASE = (name, testbench, {param: value}, title, [checks], plot spec)
A check is (measure name or expression, op, limit, level, description)
  level "NG"  : must pass (design requirement)
  level "WARN": design margin / known limitation, read the note
Edit CASES below to add your own variants (e.g. a different harness resistance).
"""
import os, re, sys, shutil, subprocess, datetime, json
ACCDIV = (47 + 6.8) / 6.8   # ACC_SENSE divider R5/R6 (v1.8: 47k / 6.8k = 7.912)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')

CASES = [
 ('tb1_nominal', 'tb1_power_sequence.cir', {'MCUFAIL': 0},
  'Power sequence: ACC on -> crank -> ACC off -> MCU HOLD=L at 12 s',
  [('t_relay_on-1', '<', 1.0, 'NG', 'ACCだけで1秒以内にリレーが入る [s]（通常はマイコンが先にHOLD=Hにする）'),
   ('vsw_min_crank', '>', 6.0, 'NG', 'クランキング中のVSWがDFR0946の最低入力6V以上 [V]'),
   ('v5_min_crank', '>', 4.5, 'NG', 'クランキング中の+5V（XIAOの5V入力） [V]'),
   ('v3_min_all', '>', 3.0, 'NG', '動作中に3V3が下がらない [V]'),
   ('t_relay_off-12', '<', 0.2, 'NG', 'HOLD=Lから0.2秒以内にリレーが切れる [s]'),
   ('ibat_peak', '<', 200, 'WARN', 'リレーが閉じたときの突入電流 [A]（tb5で詳しく確認）'),
   ('abs(v5s_on-5.3)', '<', 0.15, 'NG', '+5VS（センサー用5V）が5.3V±0.15V'),
   ('v5s_min_crank', '>', 4.75, 'NG', 'クランキング中の+5VS [V]'),
   ('v3s_min_crank', '>', 3.135, 'NG', 'クランキング中の+3V3S（3.3V−5%以上） [V]')],
  ('tb1_nominal', ['acc', 'vbat', 'vsw', 'v5', 'v3v3', 'holdn', 'holdg', 'coil', 'ivsw', 'v5s', 'v3s'],
   [['vbat', 'acc', 'vsw'], ['v5', 'v3v3', 'holdn', 'holdg']])),
 ('tb1_mcufail', 'tb1_power_sequence.cir', {'MCUFAIL': 1},
  'Same, but the MCU pin goes Hi-Z at 12 s (crash): HOLD_N RC must release the relay',
  [('t_relay_off-12', '>', 2.0, 'NG', 'Hi-Z後の保持時間が2秒以上（マイコンのリセットに足りる） [s]'),
   ('t_relay_off-12', '<', 30.0, 'NG', '30秒以内にリレーが切れる（暗電流ゼロ） [s]')],
  ('tb1_mcufail', ['acc', 'vbat', 'vsw', 'v5', 'v3v3', 'holdn', 'holdg', 'coil', 'ivsw', 'v5s', 'v3s'],
   [['vbat', 'acc', 'vsw'], ['v5', 'v3v3', 'holdn', 'holdg']])),
 ('tb2_sweep', 'tb2_supply_sweep.cir', {},
  'Slow supply sweep 0->30->0 V (MCU Hi-Z): ADC scaling, relay pull-in, jump start',
  [('accs_max', '<', 3.3, 'NG', 'ACC_SENSEが3.3V（ESP32の上限）を超えない [V]'),
   ('abs(accs_at12/(12/ACCDIV)-1)', '<', 0.03, 'NG', '12VでのACC_SENSEの誤差が3%未満'),
   ('abs(accs_at16/(16/ACCDIV)-1)', '<', 0.03, 'WARN', '16VでのACC_SENSEの誤差が3%未満（ZD2の漏れ）'),
   ('v_relay_in', '<', 10.5, 'NG', '電源10.5V未満でリレーが入る [V]'),
   ('v5_ok_in', '<', 7.0, 'NG', '電源7V未満で+5Vが4.75V以上になる [V]'),
   ('i_tvs1_24v', '<', 1.0, 'WARN', '24VジャンプスタートでのTVS1の電流 [A]'),
   ('i_tvs2_24v', '<', 0.1, 'WARN', '24VジャンプスタートでのTVS2の電流 [A]'),
   ('v3s_ok_in', '<', 10.5, 'NG', '+3V3S（センサー用3.3V）が確立する電源電圧 [V]')],
  ('tb2_sweep', ['vsup', 'vsw', 'accs', 'holdn', 'v5', 'itvs1', 'v5s', 'v3s'],
   [['vsup', 'vsw', 'v5'], ['accs', 'holdn']])),
 ('tb3_tja_only', 'tb3_kline.cir', {'PAR': 0},
  'K-line, JP6 only (TJA1021): fast init / 10400 bps / 5-baud start bit',
  [('k_idle', '>', 0.8 * 13.8, 'NG', '待機中のK-LineがVBATの80%以上 [V]'),
   ('k_fast_low', '<', 0.2 * 13.8, 'NG', 'ファスト初期化のLがVBATの20%以下（ISO 14230） [V]'),
   ('k_bit_late', '<', 0.2 * 13.8, 'WARN', '5ボー初期化の200msの間Lを保つ [V]（TJA1021は約27msで解除されるため、想定どおり満たさない）')],
  ('tb3_tja_only', ['txs', 'kline', 'rxd', 'kgate'], [['kline'], ['txs', 'rxd', 'kgate']])),
 ('tb3_parallel', 'tb3_kline.cir', {'PAR': 1},
  'K-line, JP6 + JP7 (parallel drive with Q9)',
  [('k_idle', '>', 0.8 * 13.8, 'NG', '待機中のK-LineがVBATの80%以上 [V]'),
   ('k_fast_low', '<', 0.2 * 13.8, 'NG', 'ファスト初期化のLがVBATの20%以下 [V]'),
   ('k_bit_late', '<', 0.2 * 13.8, 'NG', '5ボー初期化の200msの間Lを保つ [V]'),
   ('rxd_bit_late', '<', 0.5, 'NG', 'RXDがLを受信する（エコー） [V]'),
   ('p_r14_low', '<', 0.5, 'NG', 'K-LineがLの間のR14（1W品）の消費電力 [W]')],
  ('tb3_parallel', ['txs', 'kline', 'rxd', 'kgate'], [['kline'], ['txs', 'rxd', 'kgate']])),
 ('tb4_5b_35V', 'tb4_load_dump.cir', {'US': 87, 'RI': 1, 'CLAMP': 35},
  'Load dump, suppressed (alternator clamps at 35 V), Ri 1 ohm, td 200 ms',
  [('vsw_peak', '<', 35, 'NG', 'VSWがDFR0946の上限35V未満 [V]'),
   ('acc_peak', '<', 40, 'NG', 'ACCが40V未満 [V]'),
   ('v5_min', '>', 4.5, 'NG', '+5Vが止まらない [V]'),
   ('e_tvs1_total', '<', 75, 'WARN', 'TVS1が吸収するエネルギー [J]（SM8S20Aの目安 約75J）'),
   ('p_tvs2_peak', '<', 40, 'WARN', 'TVS2 SMAJ20Aのピーク電力 [W]（約200msのパルス）'),
   ('v5s_min', '>', 4.75, 'NG', '+5VSが止まらない [V]'),
   ('vswext_peak', '<', 30, 'WARN', 'ポートの12V端子（VSW_EXT）の最大 [V]（外付け機器の耐圧の目安30V）')],
  ('tb4_5b_35V', ['alt', 'vsw', 'acc', 'v5', 'itvs1', 'itvs2', 'v5s'], [['alt', 'vsw', 'acc'], ['v5', 'v5s']])),
 ('tb4_5a_87V_1R', 'tb4_load_dump.cir', {'US': 87, 'RI': 1, 'CLAMP': 200},
  'Load dump, unsuppressed 87 V, Ri 1 ohm (severe ISO 16750-2 test A)',
  [('vsw_peak', '<', 35, 'NG', 'VSWがDFR0946の上限35V未満 [V]'),
   ('e_tvs1_total', '<', 75, 'WARN', 'TVS1が吸収するエネルギー [J]'),
   ('p_tvs2_peak', '<', 40, 'WARN', 'TVS2のピーク電力 [W]'),
   ('v5s_min', '>', 4.75, 'NG', '+5VSが止まらない [V]'),
   ('vswext_peak', '<', 30, 'WARN', 'ポートの12V端子（VSW_EXT）の最大 [V]（外付け機器の耐圧の目安30V）')],
  ('tb4_5a_87V_1R', ['alt', 'vsw', 'acc', 'v5', 'itvs1', 'itvs2', 'v5s'], [['alt', 'vsw', 'acc'], ['v5', 'v5s']])),
 ('tb4_5a_87V_4R', 'tb4_load_dump.cir', {'US': 87, 'RI': 4, 'CLAMP': 200},
  'Load dump, unsuppressed 87 V, Ri 4 ohm (mild test A)',
  [('vsw_peak', '<', 35, 'NG', 'VSWがDFR0946の上限35V未満 [V]'),
   ('e_tvs1_total', '<', 75, 'WARN', 'TVS1が吸収するエネルギー [J]'),
   ('p_tvs2_peak', '<', 40, 'WARN', 'TVS2のピーク電力 [W]'),
   ('v5s_min', '>', 4.75, 'NG', '+5VSが止まらない [V]'),
   ('vswext_peak', '<', 30, 'WARN', 'ポートの12V端子（VSW_EXT）の最大 [V]（外付け機器の耐圧の目安30V）')],
  ('tb4_5a_87V_4R', ['alt', 'vsw', 'acc', 'v5', 'itvs1', 'itvs2', 'v5s'], [['alt', 'vsw', 'acc'], ['v5', 'v5s']])),
 ('tb5_inrush', 'tb5_inrush.cir', {},
  'Relay-close inrush into C1-C3 + DFR0946 input capacitors',
  [('i_peak', '<', 150, 'WARN', '接点電流のピーク [A]'),
   ('i2t_total', '<', 5, 'NG', 'I²t [A²s]（7.5Aヒューズの溶断は約20A²s）'),
   ('i_d7_peak', '<', 50, 'NG', 'D7（SS34）のピーク電流 [A]（サージ定格IFSM 80A）'),
   ('i_f4_peak', '<', 20, 'NG', 'F4（1.1A PTC）を通る突入電流のピーク [A]')],
  ('tb5_inrush', ['ik', 'vsw', 'vdfr', 'id7', 'if4'], [['ik', 'id7', 'if4'], ['vsw', 'vdfr']])),
]
# TB6 hold-time corner cases: (C11, R2, VTN, zener model)
for nm, c, r, vtn, z in [('nom', '10u', '1Meg', 1.0, 'DZ3V6'),
                         ('sharpZ', '10u', '1Meg', 1.0, 'DZ3V6_SHARP'),
                         ('worst', '8u', '0.95Meg', 1.2, 'DZ3V6'),
                         ('best', '12u', '1.05Meg', 0.8, 'DZ3V6_SHARP')]:
    CASES.append(('tb6_' + nm, 'tb6_hold_time.cir', {'C11': c, 'R2': r, 'VTN': vtn, '@ZMODEL': z},
                  f'Hold time after Hi-Z: C11={c} R2={r} VT-={vtn} V zener={z}',
                  [('hold_s', '>', 2.0, 'NG', '保持時間が2秒以上（マイコンのリセットに足りる） [s]'),
                   ('hold_s', '>', 3.0, 'WARN', '保持時間がwdt_timeout_ms（3000ms）より長い（ファーム仕様） [s]'),
                   ('hold_s', '<', 30.0, 'NG', '30秒以内にリレーが切れる（暗電流ゼロ） [s]')],
                  ('tb6_' + nm, ['holdn', 'holdg', 'vout'], [['holdn', 'holdg']])))

# TB7 pulse-input adapter: (name, params, title, expected frequency or None = must NOT toggle)
for nm, prm, ttl, fexp in [
    ('speed12', {'F': 200, 'VHI': 12, 'VLO': 0.8, 'OC': 0, 'PU': 12, 'JP2': 0, 'SPIKE': 0}, '12V方形波・Lが0.8V浮く（車速パルス想定）200Hz', 200),
    ('tach12_jp2', {'F': 300, 'VHI': 12, 'VLO': 0.8, 'OC': 0, 'PU': 12, 'JP2': 1, 'SPIKE': 0}, '12V方形波・JP2（12Vしきい値）あり（タコ信号想定）300Hz', 300),
    ('oc5', {'F': 200, 'VHI': 5, 'VLO': 0, 'OC': 1, 'PU': 5, 'JP2': 0, 'SPIKE': 0}, 'オープンコレクタ・5Vプルアップ 200Hz', 200),
    ('oc12_jp2', {'F': 200, 'VHI': 5, 'VLO': 0, 'OC': 1, 'PU': 12, 'JP2': 1, 'SPIKE': 0}, 'オープンコレクタ・12Vプルアップ・JP2あり 200Hz', 200),
    ('sensor3v3', {'F': 5000, 'VHI': 3.3, 'VLO': 0, 'OC': 0, 'PU': 12, 'JP2': 0, 'SPIKE': 0}, '3.3Vセンサー 5kHz', 5000),
    ('spike', {'F': 200, 'VHI': 12, 'VLO': 0.8, 'OC': 0, 'PU': 12, 'JP2': 0, 'SPIKE': 1}, '12V方形波＋40Vスパイク', 200),
    ('5v_jp2_ng', {'F': 1000, 'VHI': 5, 'VLO': 0, 'OC': 0, 'PU': 12, 'JP2': 1, 'SPIKE': 0}, '5V信号でJP2を閉じた場合（使えない組み合わせの確認）', None)]:
    if fexp:
        ck = [(f'abs(f_out/{fexp}-1)', '<', 0.01, 'NG', f'出力の周波数が入力（{fexp}Hz）と一致（パルスの抜け・余分なし）'),
              ('duty', '>', 0.3, 'NG', 'デューティ比 30%以上'), ('duty', '<', 0.7, 'NG', 'デューティ比 70%以下'),
              ('out_hi', '>', 3.0, 'NG', '出力のH電圧 [V]'),
              ('siga_max', '<', 5.5, 'NG', 'U1入力の最大電圧 [V]（74LVC1G17の推奨上限5.5V）')]
    else:
        ck = [('out_hi', '<', 0.5, 'NG', '出力が変化しない [V]（5V信号ではJP2を閉じないこと）')]
    CASES.append(('tb7_' + nm, 'tb7_pulse_in.cir', prm, ttl, ck,
                  ('tb7_' + nm, ['sigin', 'siga', 'out'], [['sigin'], ['siga', 'out']])))

# ---------------- v2.x additions ----------------
# TB8 XL7015 switching model: U1 (MCU 5V, C4 470uF) and U8 (sensor 5VS, C40 100uF)
for nm, prm, ttl, ilim in [
    ('u1', {'CB': '470u', 'ESRB': 0.08, 'I0': 0.15, 'I1': 0.5, 'CC': '0.6u'}, 'U1（マイコン用5V）：入力C4 470µF＋C5 1µF、負荷0.15→0.5A', 0.6),
    ('u8', {'CB': '100u', 'ESRB': 0.3, 'I0': 0.3, 'I1': 0.7, 'CC': '3u'}, 'U8（センサー用5VS）：入力C40 100µF＋C41 10µF（14Vで約3µF）、負荷0.3→0.7A', 0.3)]:
    CASES.append(('tb8_' + nm, 'tb8_buck_switching.cir', prm, ttl,
        [('abs(vout_avg-5.3)', '<', 0.15, 'NG', '出力電圧が5.3V±0.15V'),
         ('vout_pp', '<', 0.1, 'NG', '出力のリップル（ピーク間） [V]'),
         ('vout_min_step', '>', 4.75, 'NG', '負荷が増えた瞬間の最低電圧 [V]'),
         ('vout_max_rel', '<', 5.8, 'WARN', '負荷が減った瞬間の最高電圧 [V]'),
         ('il_peak', '<', 1.1, 'WARN', 'インダクタ電流のピーク [A]（SWPA8040S101MTの飽和電流は要確認）'),
         ('icb_rms', '<', ilim, 'WARN', f'電解コンデンサの入力リップル電流（実効値） [A]（目安{ilim}A、部品の定格は要確認）'),
         ('t_start*1000', '<', 10, 'NG', '起動時間 [ms]')],
        ('tb8_' + nm, ['vout', 'sw', 'il', 'icb', 'icc', 'vin'], [['vout'], ['il', 'icb', 'icc']])))
# TB9 I2C 400 kHz: (CBUS, RMOD, RPU).  v2.4.1: R30/R31 = 1.2k
for nm, cb, rm, rpu, ttl in [('100p', '100p', '1e9', '1.2k', 'バス容量100pF（ケーブル短め）'), ('200p', '200p', '1e9', '1.2k', 'バス容量200pF'),
                             ('250p', '250p', '1e9', '1.2k', 'バス容量250pF（6ポートに約50cmずつ）'),
                             ('200p_mod2', '200p', '5k', '1.2k', 'バス容量200pF＋センサー基板のプルアップ10k×2'),
                             ('400p', '400p', '1e9', '1.2k', '限界の確認：バス容量400pF'),
                             ('200p_mod6', '200p', '1.67k', '1.2k', '限界の確認：センサー基板のプルアップ10k×6')]:
    CASES.append(('tb9_' + nm, 'tb9_i2c.cir', {'CBUS': cb, 'RMOD': rm, 'RPU': rpu}, 'I2C 400kHz：' + ttl,
        [('trise_ns', '<', 300, 'WARN' if nm == '400p' else 'NG', '立ち上がり時間（30→70%） [ns]（Fast-modeの上限300ns）'),
         ('scl_hi_end', '>', 2.31, 'NG', '次の立ち下がりまでにHレベル（70%）に達する [V]'),
         ('sda_vol', '<', 0.4, 'WARN' if nm == '200p_mod6' else 'NG', 'Lレベル（弱いデバイス、約3mA） [V]（上限0.4V）')],
        ('tb9_' + nm, ['scl', 'sda'], [['scl', 'sda']])))
# TB10 CAN front end (TJA1042T/3 + PESD1CAN)
for nm, vs, vt, ttl in [('rx', 0, 0, '500kbpsの受信'), ('short14', 14.4, 0, 'CANHが14.4Vに短絡'),
                        ('short24', 24, 0, 'CANHが24Vに短絡（24Vジャンプスタート）'),
                        ('pulse_a', 0, -150, 'ISO 7637-3 パルスa（−150V）'), ('pulse_b', 0, 100, 'ISO 7637-3 パルスb（+100V）')]:
    ck = [('ch_max', '<', 58, 'NG', 'U6のCANHが+58V以下 [V]（TJA1042の絶対最大定格）'),
          ('ch_min', '>', -58, 'NG', 'U6のCANHが−58V以上 [V]'),
          ('cl_max', '<', 58, 'NG', 'U6のCANLが+58V以下 [V]'),
          ('cl_min', '>', -58, 'NG', 'U6のCANLが−58V以上 [V]')]
    if nm == 'rx':
        ck = [('vdiff_dom', '>', 1.5, 'NG', 'ドミナントの差動電圧 [V]（1.5〜3.0V）'), ('vdiff_dom', '<', 3.0, 'NG', 'ドミナントの差動電圧 [V]'),
              ('rxd_dom', '<', 0.5, 'NG', 'RXDのL（ドミナント受信） [V]'), ('rxd_rec', '>', 2.8, 'NG', 'RXDのH（レセッシブ） [V]')] + ck
    if nm.startswith('short'):
        ck += [('ipesd_end', '<', 0.005, 'NG', '短絡が続いている間にJ3から流れ込む電流 [A]（PESD1CANが導通しない）')]
    CASES.append(('tb10_' + nm, 'tb10_can.cir', {'VSHORT': vs, 'VTR': vt}, 'CAN：' + ttl, ck,
        ('tb10_' + nm, ['jh', 'jl', 'ch', 'cl', 'rxd', 'txr', 'ipesd'], [['jh', 'jl', 'ch', 'cl'], ['rxd', 'txr']])))
# TB11 GPIO miswire protection (series resistor R80-R84, v2.4.1: 1k)
for nm, vf, i3, ttl in [('12v', 12, 0.04, 'ポートの信号ピンに12Vを誤配線（3.3Vの消費40mA）'), ('25v', 25, 0.04, '25V（ロードダンプ時のVSW_EXT）'),
                        ('12v_sleep', 12, 0.005, '参考：12V・マイコンがスリープ中（3.3Vの消費5mA）')]:
    CASES.append(('tb11_' + nm, 'tb11_gpio.cir', {'RSER': '1k', 'VF': vf, 'I3': i3}, 'GPIO保護（1kΩ）：' + ttl,
        [('v3_max', '<', 3.6, 'WARN' if 'sleep' in nm else 'NG', 'XIAOの3.3Vが上がらない [V]（ESP32-S3の絶対最大3.6V）'),
         ('ipin_max*1000', '<', 10, 'WARN', 'ピンに流れ込む電流 [mA]（目安10mA以下）'),
         ('trise_ns', '<', 1000, 'NG', '通常使用：受信側（GPSのTX→XIAO）の立ち上がり [ns]'),
         ('trise_tx_ns', '<', 271, 'WARN', '通常使用：送信側（XIAO→ケーブル100pF→GPSのRX）の立ち上がり [ns]（921600bpsの1ビットの25%）')],
        ('tb11_' + nm, ['port', 'pin', 'v3', 'ir'], [['port', 'pin', 'v3'], ['ir']])))

def find_ngspice():
    for c in [os.environ.get('NGSPICE'), 'ngspice_con', 'ngspice']:
        if c and shutil.which(c):
            return shutil.which(c)
    for p in [r'C:\Spice64\bin\ngspice_con.exe', r'C:\Program Files\Spice64\bin\ngspice_con.exe']:
        if os.path.exists(p):
            return p
    sys.exit('ngspice not found. Install it (README.md) or set NGSPICE=path\\to\\ngspice_con.exe')


def prepare(name, tb, params):
    src = open(os.path.join(HERE, tb), encoding='utf-8').read()
    for k, v in params.items():
        if k == '@ZMODEL':
            src = re.sub(r'^(DZ1 0 holdn )\S+', r'\g<1>' + v, src, flags=re.M)
            continue
        pat = re.compile(r'^(\.param\b.*?\b' + k + r')=(\S+)', re.M | re.I)
        if not pat.search(src):
            sys.exit(f'{tb}: .param {k} not found')
        src = pat.sub(lambda m: m.group(1) + '=' + str(v), src)
    src = re.sub(r'^(wrdata\s+)\S+', r'\g<1>out/' + name + '.txt', src, flags=re.M)
    path = os.path.join(HERE, '_run_' + name + '.cir')
    open(path, 'w', encoding='utf-8').write(src)
    return path


def run(ng, path):
    p = subprocess.run([ng, '-b', os.path.basename(path)], cwd=HERE, capture_output=True,
                       text=True, timeout=600)
    txt = p.stdout + p.stderr
    meas = {}
    for m in re.finditer(r'^\s*([a-z_][a-z0-9_]*)\s*=\s*([-+0-9.eE]+)', txt, re.M | re.I):
        meas.setdefault(m.group(1).lower(), float(m.group(2)))
    err = [l for l in txt.splitlines() if re.search(r'error|too small|aborted', l, re.I)]
    return meas, err, txt


def evaluate(expr, meas):
    env = dict(meas); env['abs'] = abs; env['ACCDIV'] = ACCDIV
    try:
        return eval(expr, {'__builtins__': {}}, env)
    except Exception:
        return None


def plot(name, names, groups, title):
    try:
        import numpy as np, matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
    except ImportError:
        return None
    f = os.path.join(OUT, name + '.txt')
    if not os.path.exists(f):
        return None
    d = np.loadtxt(f)
    t = d[:, 0]
    fig, axs = plt.subplots(len(groups), 1, figsize=(10, 2.8 * len(groups)), sharex=True, squeeze=False)
    for ax, g in zip(axs[:, 0], groups):
        for n in g:
            k = names.index(n)
            ax.plot(t, d[:, 2 * k + 1], label=n, lw=1.2)
        ax.grid(alpha=.3); ax.legend(loc='upper right', fontsize=8)
    axs[0, 0].set_title(title, fontsize=10)
    axs[-1, 0].set_xlabel('time [s]')
    png = os.path.join(OUT, name + '.png')
    fig.tight_layout(); fig.savefig(png, dpi=110); plt.close(fig)
    return os.path.basename(png)


def main():
    sel = sys.argv[1:]
    ng = find_ngspice()
    os.makedirs(OUT, exist_ok=True)
    rows, sections, results = [], [], []
    for name, tb, params, title, checks, pl in CASES:
        if sel and not any(name.startswith(s) for s in sel):
            continue
        path = prepare(name, tb, params)
        try:
            meas, err, log = run(ng, path)
        finally:
            os.remove(path)
        open(os.path.join(OUT, name + '.log'), 'w', encoding='utf-8').write(log)
        res_case = {'name': name, 'tb': tb, 'title': title, 'params': params, 'meas': meas,
                    'errors': err[:5], 'columns': pl[1], 'checks': []}
        results.append(res_case)
        sec = [f'## {name}  ({tb})', title, '']
        if err:
            sec += ['```'] + err[:5] + ['```']
        sec += ['| check | value | limit | result | note |', '|---|---|---|---|---|']
        for expr, op, lim, lvl, desc in checks:
            v = evaluate(expr, meas)
            ok = v is not None and ((v < lim) if op == '<' else (v > lim))
            res = 'PASS' if ok else ('FAIL' if lvl == 'NG' else 'WARN')
            vs = 'n/a' if v is None else f'{v:.4g}'
            sec.append(f'| `{expr}` | {vs} | {op} {lim:g} | **{res}** | {desc} |')
            rows.append((name, expr, vs, res))
            res_case['checks'].append({'expr': expr, 'value': v, 'op': op, 'limit': lim,
                                       'level': lvl, 'result': res, 'desc': desc})
            print(f'{name:16s} {res:4s} {expr:28s} = {vs:>10s}  ({op} {lim:g})  {desc}')
        png = plot(pl[0], pl[1], pl[2], title)
        if png:
            sec += ['', f'![{name}]({png})']
        sections.append('\n'.join(sec))
    nfail = sum(r[3] == 'FAIL' for r in rows); nwarn = sum(r[3] == 'WARN' for r in rows)
    head = [f'# PWR-CTRL v2.4.1 SPICE report', f'{datetime.datetime.now():%Y-%m-%d %H:%M}  ngspice: {ng}', '',
            f'**FAIL {nfail} / WARN {nwarn} / checks {len(rows)}**', '']
    open(os.path.join(OUT, 'report.md'), 'w', encoding='utf-8').write('\n'.join(head) + '\n\n'.join(sections) + '\n')
    json.dump({'date': f'{datetime.datetime.now():%Y-%m-%d %H:%M}', 'cases': results},
              open(os.path.join(OUT, 'results.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'\nFAIL {nfail}  WARN {nwarn}  -> out/report.md, out/results.json')
    if not sel:
        try:
            import make_report
            make_report.main()
        except ImportError:
            pass
    sys.exit(1 if nfail else 0)


if __name__ == '__main__':
    main()
