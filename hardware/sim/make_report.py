#!/usr/bin/env python3
"""Build out/report.html (graphical SPICE report) from out/results.json + out/<case>.txt.

    python make_report.py      (run_all.py calls this automatically after a full run)

The page is self-contained (no internet needed except the web fonts) and has
interactive waveforms: move the mouse over a chart to read every trace.
Edit SPEC below to change what is drawn for each test.
"""
import os, json, re
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
NPTS = 700          # min/max buckets per trace (keeps spikes, keeps the page small)

# --------------------------------------------------------------------------------------
# What to draw for each test.  Trace keys are "case:column" (columns from run_all.CASES)
# or derived traces defined in DERIVED.  Times in seconds; "xscale" converts for display.
# --------------------------------------------------------------------------------------
TB1_EVENTS = [{'t': 1.0, 'label': 'ACC ON'}, {'t': 1.5, 'label': 'MCU HOLD=H'},
              {'t': 8.0, 'label': 'ACC OFF'}]
TB1_BANDS = [{'t0': 3.0, 't1': 4.0, 'label': 'クランキング（ACC断・7V→9V）'}]


def tb1_charts(c, last):
    return [{
        'title': '電源シーケンス全体（0〜24秒）', 'xunit': 's', 'xscale': 1,
        'events': TB1_EVENTS + [{'t': 12.0, 'label': last}],
        'marks': [{'meas': c + ':t_relay_on', 'label': 'リレーON'},
                  {'meas': c + ':t_relay_off', 'label': 'リレーOFF'}],
        'bands': TB1_BANDS,
        'panels': [
            {'label': '電源 [V]', 'traces': [(c + ':vbat', '+B（VBAT）'), (c + ':acc', 'ACC'), (c + ':vsw', 'VSW（リレー後）')],
             'limits': [{'y': 6, 'label': 'DFR0946 最低入力 6V', 'kind': 'ng'}], 'ymin': 0, 'ymax': 16},
            {'label': '制御 [V]', 'traces': [(c + ':v5', '+5V'), (c + ':v3v3', '+3V3'), (c + ':holdn', 'HOLD_N'), (c + ':holdg', 'HOLD_G（Q1ゲート）')],
             'limits': [{'y': 1.8, 'label': 'U5 VT+ 1.8V', 'kind': 'ref'}, {'y': 1.0, 'label': 'U5 VT− 1.0V', 'kind': 'ref'}],
             'ymin': 0, 'ymax': 5.6},
            {'label': 'センサー用 [V]', 'traces': [(c + ':v5s', '+5VS（U8）'), (c + ':v3s', '+3V3S（U9）')],
             'limits': [{'y': 4.75, 'label': '4.75V', 'kind': 'ng'}], 'ymin': 0, 'ymax': 5.6},
            {'label': '+B電流 [A]', 'traces': [(c + ':ivsw', '+Bからの電流')], 'ymin': 0, 'ymax': 16,
             'note': 'リレーが閉じた瞬間の突入ピーク（約130A）は範囲外。詳しくはtb5'},
        ]}, {
        'title': '拡大：クランキング（2.9〜4.3秒）', 'xunit': 's', 'xscale': 1, 'xmin': 2.9, 'xmax': 4.3,
        'bands': TB1_BANDS, 'events': [],
        'panels': [
            {'label': '電源 [V]', 'traces': [(c + ':vbat', '+B（VBAT）'), (c + ':acc', 'ACC'), (c + ':vsw', 'VSW')],
             'limits': [{'y': 6, 'label': 'DFR0946 最低入力 6V', 'kind': 'ng'}], 'ymin': 0, 'ymax': 16},
            {'label': '制御 [V]', 'traces': [(c + ':v5', '+5V'), (c + ':v3v3', '+3V3'), (c + ':holdn', 'HOLD_N'), (c + ':v5s', '+5VS'), (c + ':v3s', '+3V3S')],
             'limits': [{'y': 4.5, 'label': '+5V 判定 4.5V', 'kind': 'ng'}], 'ymin': 0, 'ymax': 5.6},
        ]}]


SPEC = {
 'tb1_nominal': {
   'group': '電源制御', 'parts': 'K1, Q1, U5, C11, R1〜R3, ZD1, D1〜D3, U1（マイコン用5V）, F4・U8・U9（センサー用電源）',
   'what': 'ACCを入れてから、クランキング、ACC OFF、マイコンによる遮断までの一連の動作を確認する。',
   'steps': ['1秒：ACC ON。ACC→D3→R3でHOLD_Nが上がり、U5がQ1をONにしてリレーが入る',
             '1.5秒：マイコンがHOLDをHにして保持を引き継ぐ',
             '3〜4秒：クランキング。ACCが切れ、+Bは7V（50ms）→9Vに落ちる。マイコンの保持でリレーは入ったまま',
             '8秒：ACC OFF。マイコンはシャットダウン処理中（リレーは入ったまま）',
             '12秒：シャットダウン完了。マイコンがHOLDをLにしてリレーを切る'],
   'charts': tb1_charts('tb1_nominal', 'MCU HOLD=L'),
   'comment': 'すべて合格。クランキング中もVSWは6.55V以上で、DFR0946の最低入力6Vを下回らない。v2.0で追加したセンサー用電源（+5VSに0.3A、+3V3Sに0.4Aの負荷）も、クランキング中に+5VSは5.23V、+3V3Sは3.28Vを保つ。HOLD=Lから36msでリレーが切れる。'},
 'tb1_mcufail': {
   'group': '電源制御', 'parts': 'C11, R2, ZD1, U5, Q1, K1',
   'what': 'シャットダウン中にマイコンが止まった（ピンがHi-Z）場合でも、時間がたてばリレーが切れて暗電流がゼロになることを確認する。',
   'steps': ['12秒まではtb1_nominalと同じ', '12秒：マイコンのピンがHi-Zになる（停止・リセット・抜去）',
             'HOLD_Nは、C11 10µFがR2 1MΩとZD1の漏れで放電しながら下がる', 'VT−（1.0V）を下回るとU5がLになり、リレーが切れる'],
   'charts': tb1_charts('tb1_mcufail', 'MCU Hi-Z'),
   'comment': '12秒から7.9秒後にリレーが切れる（v1.8でC11を10µFに変更。4.7µFでは3.7秒だった）。部品のばらつきはtb6で見る。'},
 'tb2_sweep': {
   'group': '電源制御', 'parts': 'R5, R6, ZD2, TVS1, TVS2, K1, XL7015（U1）',
   'what': '電源（+BとACCを同時に）を0Vから30Vまでゆっくり上げ、各部の電圧を電源電圧に対して見る。マイコンのピンはHi-Z。',
   'steps': ['0→30V（60秒）→0V（60秒）。ここでは上げていく側だけを表示', 'ACC_SENSEは理想の分圧（電源÷5.7）と比べる',
             '24Vは、24V車からのジャンプスタート（ISO 16750-2）を想定した点'],
   'charts': [{
     'title': '電源電圧に対する各部の電圧と電流（上げていく側）', 'xunit': 'V', 'xtrace': 'tb2_sweep:vsup', 'tmax': 60,
     'xmin': 0, 'xmax': 30, 'xlabel': '電源電圧 [V]',
     'events': [{'t': 24, 'label': '24Vジャンプスタート'}, {'t': 12, 'label': '通常 12V'}],
     'marks': [{'meas': 'tb2_sweep:v_relay_in', 'label': 'リレーON', 'xis': 'value'},
               {'meas': 'tb2_sweep:v5_ok_in', 'label': '+5V確立', 'xis': 'value'}],
     'panels': [
       {'label': 'ACC_SENSE [V]', 'traces': [('tb2_sweep:accs', 'ACC_SENSE（シミュレーション）'), ('tb2_sweep:accs_ideal', '理想値（電源÷7.91）')],
        'limits': [{'y': 3.3, 'label': 'ESP32 上限 3.3V', 'kind': 'ng'}], 'ymin': 0, 'ymax': 4},
       {'label': '電圧 [V]', 'traces': [('tb2_sweep:vsw', 'VSW'), ('tb2_sweep:v5', '+5V'), ('tb2_sweep:holdn', 'HOLD_N'), ('tb2_sweep:v5s', '+5VS'), ('tb2_sweep:v3s', '+3V3S')],
        'ymin': 0, 'ymax': 32},
       {'label': 'TVS1電流 [A]', 'traces': [('tb2_sweep:itvs1', 'TVS1 SM8S20A')],
        'limits': [{'y': 7.5, 'label': 'F1 7.5A', 'kind': 'warn'}], 'ymin': 0, 'ymax': 40,
        'note': '30Vでは81A（範囲外）'},
     ]}],
   'comment': 'v1.8でR6を10kから6.8kに変え、ACC_SENSEを低めの電圧で使うようにした。ZD2の漏れが効かなくなり、16Vでの誤差は0.2%（変更前は7%）。0〜20V程度まで電圧計として使える。24VではTVSが導通し、ヒューズが切れる（変更なし）。センサー用の+5VS・+3V3Sは、リレーが入る9.9Vで同時に立ち上がる。'},
 'tb3_tja_only': {
   'group': 'K-Line', 'parts': 'U4 TJA1021, R14, D10, TVS3, JP6',
   'what': 'TJA1021だけ（JP6のみ）でK-Lineを駆動したときの、ファスト初期化・10400bpsの送信・5ボー初期化の波形を確認する。',
   'steps': ['0.30秒：ファスト初期化（L 25ms → H 25ms）', '0.40秒：10400bpsで2バイト（0xC1、0x33）',
             '0.60秒〜：5ボー初期化でアドレス0x33（1ビット200ms）'],
   'charts': 'kline:tb3_tja_only',
   'comment': 'ファスト初期化と通常の送信は問題ない。5ボー初期化は、TJA1021のTXDタイムアウト（約27ms）でLが解除されるため送れない（設計どおり。並列駆動を使う）。'},
 'tb3_parallel': {
   'group': 'K-Line', 'parts': 'U4, Q8, Q9, R20〜R23, F3, JP6＋JP7',
   'what': 'JP6とJP7を両方つないだ並列駆動で、同じ送信パターンを確認する。Q9がTJA1021のタイムアウト後もLを保持する。',
   'steps': ['送信パターンはtb3_tja_onlyと同じ', 'Q8でTXを反転してQ9のゲートを駆動し、Q9（＋F3）でK-LineをGNDへ引く'],
   'charts': 'kline:tb3_parallel',
   'comment': 'すべて合格。L電圧は0.2V（基準はVBATの20%＝2.76V以下）。5ボー初期化の200msもLを保持する。R14の消費電力は0.32W（1W品）。'},
 'tb4_5b_35V': {
   'group': '保護', 'parts': 'TVS1 SM8S20A, TVS2 SMAJ20A, C1〜C3',
   'what': '走行中にバッテリーが外れたときのロードダンプ（電圧の跳ね上がり）。オルタネーター側で35Vに抑えられる場合（パルス5b）。',
   'steps': ['50ms：電圧が跳ね上がる（内部抵抗1Ω、持続時間200ms）', 'TVS1・TVS2が電圧を約23Vに抑える', 'PCとマイコンは動き続ける'],
   'charts': 'dump:tb4_5b_35V',
   'comment': 'VSWの最大は22.8Vで、DFR0946の上限35Vを十分に下回る。TVS1が吸収するエネルギーは56J（目安75J以下）。ポートの12V端子（VSW_EXT）も22.8Vまでで、+5VSは止まらない。'},
 'tb4_5a_87V_1R': {
   'group': '保護', 'parts': 'TVS1 SM8S20A, TVS2 SMAJ20A',
   'what': '抑制のないロードダンプ（87V、内部抵抗1Ω）。ISO 16750-2の厳しい側の条件。',
   'steps': ['オルタネーターの開放電圧は87Vまで上がる', '内部抵抗1Ωなので、TVSに最大51A流れる'],
   'charts': 'dump:tb4_5a_87V_1R',
   'comment': 'VSWは25Vに抑えられ、DFR0946は守られる。ただしTVS1のエネルギーが165Jで、目安の75Jを超える。TVS2のピーク電力も90Wと大きい。ポートの12V端子にも最大25Vが出るので、外付け機器は30V程度まで耐えるものを使う。'},
 'tb4_5a_87V_4R': {
   'group': '保護', 'parts': 'TVS1 SM8S20A, TVS2 SMAJ20A',
   'what': '抑制のないロードダンプ（87V、内部抵抗4Ω）。小型オルタネーター（Keiクラス）に近い条件。',
   'steps': ['開放電圧87V、内部抵抗4Ω'],
   'charts': 'dump:tb4_5a_87V_4R',
   'comment': 'TVS1のエネルギーは25J、TVS2のピーク電力は19Wで、どちらも問題ない。'},
 'tb5_inrush': {
   'group': '電源制御', 'parts': 'K1, C1〜C3, DFR0946の入力コンデンサ, D7→C4/C5（U1入力）, F4→C40/C41（U8入力）',
   'what': 'リレーが閉じた瞬間に、VSW側のコンデンサ（C1〜C3とDFR0946の入力、約560µF）と、2つのDC-DCの入力コンデンサ（C4 470µF、C40 100µF）へ流れ込む突入電流を確認する。',
   'steps': ['10ms：リレーの接点が閉じる（チャタリングは扱わない）', 'ハーネス：30mΩ・1µH、DFR0946まで10mΩ・0.5µH'],
   'charts': [{
     'title': '突入電流（10ms付近を拡大）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 9.98e-3, 'xmax': 10.3e-3,
     'events': [{'t': 0.010, 'label': '接点が閉じる'}], 'marks': [{'meas': 'tb5_inrush:i_peak', 'label': 'ピーク', 'yis': 'value', 'trace': 'tb5_inrush:ik'}],
     'panels': [
       {'label': '電流 [A]', 'traces': [('tb5_inrush:ik', 'K1接点の電流'), ('tb5_inrush:id7', 'D7（C4へ）'), ('tb5_inrush:if4', 'F4（C40へ）')], 'ymin': -10, 'ymax': 100},
       {'label': '電圧 [V]', 'traces': [('tb5_inrush:vsw', 'VSW（基板上）'), ('tb5_inrush:vdfr', 'DFR0946入力')], 'ymin': 0, 'ymax': 14},
     ]}],
   'comment': 'ピーク91A、I²tは1.17A²s（DC-DCの入力コンデンサを含めたため、v1.8の75A・0.87A²sから増えた）。7.5Aヒューズ（溶断I²t 約20A²s）には十分小さい。D7のピークは25A（SS34のサージ定格80A）、F4を通る電流は6.5A（v2.4.1でC41を10µFにしたため6.0Aから少し増えた。PTCはこの程度の瞬間電流では切れない）。'},

 'tb8': {
   'title': 'XL7015 降圧回路（U1・U8）',
   'group': 'センサー用電源・DC-DC', 'parts': 'U1／U8 XL7015、D11／D12 SS34、L1／L2 100µH、C4／C40（入力の電解）、C5／C41（入力のセラミック）、C6／C42、C7／C43、FB分圧',
   'what': 'XL7015の降圧回路を150kHzのスイッチング動作まで再現し、出力のリップル、負荷の変化への応答、インダクタの電流、入力コンデンサが受け持つリップル電流を確認する。',
   'steps': ['電源13.8V（エンジン動作中）、ハーネス50mΩ・1µH', '起動→8msで負荷を増やす→11msで戻す',
             'U1（マイコン用5V）：入力C4 470µF（ESR 0.08Ω）、負荷0.15→0.5A', 'U8（センサー用5VS）：入力C40 100µF（ESR 0.3Ω）＋C41 10µF/50V X7R（v2.4.1で1µFから変更。14Vの直流電圧で実効約3µFとして計算）、負荷0.3→0.7A',
             'XL7015の内部の制御はメーカーのモデルがないため、電圧モードのPWM（150kHz）で近似。電力段（スイッチ、SS34、インダクタ、コンデンサ）は実部品の値'],
   'cases': ['tb8_u1', 'tb8_u8'],
   'charts': [{'title': '起動と負荷の変化（0〜14ms）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0, 'xmax': 0.014,
       'events': [{'t': 0.008, 'label': '負荷増'}, {'t': 0.011, 'label': '負荷減'}],
       'panels': [{'label': '出力 [V]', 'traces': [('tb8_u1:vout', 'U1 +5V（V5REG）'), ('tb8_u8:vout', 'U8 +5VS')],
                   'limits': [{'y': 4.75, 'label': '4.75V', 'kind': 'ng'}, {'y': 5.3, 'label': '5.30V', 'kind': 'ref'}], 'ymin': 4.0, 'ymax': 6.0},
                  {'label': 'インダクタ電流 [A]', 'traces': [('tb8_u1:il', 'L1（U1）'), ('tb8_u8:il', 'L2（U8）')], 'ymin': 0, 'ymax': 1.2}]},
      {'title': '拡大：スイッチング波形（U8、負荷0.7A、9.00〜9.03ms）', 'xunit': 'µs', 'xscale': 1e6, 'xmin': 0.009, 'xmax': 0.00903,
       'panels': [{'label': 'SWノード [V]', 'traces': [('tb8_u8:sw', 'SW（U8 2番ピン）')], 'ymin': -1, 'ymax': 15},
                  {'label': '電流 [A]', 'traces': [('tb8_u8:il', 'L2'), ('tb8_u8:icb', 'C40（電解）'), ('tb8_u8:icc', 'C41（セラミック10µF）')], 'ymin': -0.9, 'ymax': 1.2},
                  {'label': '+5VS [V]', 'traces': [('tb8_u8:vout', '+5VS')], 'ymin': 5.2, 'ymax': 5.4}]}],
   'comment': '出力は5.30V、リップルは約25mV、負荷を増やした瞬間も4.98V以上で、どれも合格。v2.4.1でC41を1µF→10µF（X7R 1206）にした結果、C40（電解）のリップル電流は0.33A→0.27Aに下がった。C40（JIERR RV50V100M8X10、定格140mA@120Hz）の発熱で比べると、許容（約31mW、120Hzのtanδから推定）に対して約22mW（約70%）。実物のC40のESRが0.3Ωより大きければ、電流はさらにC41側へ移る（ESR 1Ωで0.15A）。U1側（C4 470µF）はC5 1µFのままで0.25A。インダクタのピーク1.0Aは、SWPA8040S101MTの飽和電流（1.15A、販売店の表記）に近いので、U8の負荷は0.7Aまでにする。'},
 'tb9': {
   'title': 'I2C 400kHz（6条件、R30/R31 1.2kΩ）',
   'group': 'I2C・CAN・GPIO', 'parts': 'R30／R31 1.2k（v2.4.1で2.2kから変更、JP3）、XIAO D4/D5、I2C1〜6（J6・J7・J12〜J15）',
   'what': 'I2Cを400kHz（Fast-mode）で使うとき、プルアップ1.2kΩとバスの容量で立ち上がりが規格（300ns以内）に収まるか、センサー基板のプルアップが並列に入ってもLレベルが規格（3mAで0.4V以下）に収まるかを確認する。',
   'steps': ['SCLを400kHz（周期2.5µs）でマイコンが駆動。SDAは弱いデバイス（約3mA）がLにする',
             'バス容量：XIAOのピン約10pF＋基板約15pF＋ポート＋ケーブル（1mで50〜100pF）＋センサーの入力',
             '100pF、200pF、250pF、200pF＋センサー基板のプルアップ10k×2',
             '限界の確認：400pF、センサー基板のプルアップ10k×6'],
   'cases': ['tb9_100p', 'tb9_200p', 'tb9_250p', 'tb9_200p_mod2', 'tb9_400p', 'tb9_200p_mod6'],
   'charts': [{'title': 'SCLとSDAの波形（5.5〜9µs）', 'xunit': 'µs', 'xscale': 1e6, 'xmin': 5.5e-6, 'xmax': 9e-6,
       'panels': [{'label': 'SCL [V]', 'traces': [('tb9_100p:scl', '100pF'), ('tb9_200p:scl', '200pF'), ('tb9_250p:scl', '250pF'), ('tb9_400p:scl', '400pF')],
                   'limits': [{'y': 2.31, 'label': '70%', 'kind': 'ref'}, {'y': 0.99, 'label': '30%', 'kind': 'ref'}], 'ymin': -0.2, 'ymax': 3.6},
                  {'label': 'SDA [V]', 'traces': [('tb9_200p:sda', 'プルアップ1.2kのみ'), ('tb9_200p_mod2:sda', '＋10k×2'), ('tb9_200p_mod6:sda', '＋10k×6')],
                   'limits': [{'y': 0.4, 'label': 'VOL 0.4V', 'kind': 'ng'}], 'ymin': -0.2, 'ymax': 3.6}]}],
   'bars': {'title': '立ち上がり時間（30→70%）', 'unit': 'ns', 'items': [('tb9_100p', '100pF'), ('tb9_200p', '200pF'), ('tb9_250p', '250pF'), ('tb9_200p_mod2', '200pF＋10k×2'), ('tb9_400p', '400pF')],
            'meas': 'trise_ns', 'limits': [{'y': 300, 'label': 'Fast-mode上限 300ns', 'kind': 'ng'}], 'max': 500},
   'comment': 'R30/R31を1.2kΩにしたことで、400kHzを守れるバス容量は約160pF→約295pFに広がった（2.2kΩのときは200pFで373ns、1.2kΩでは203ns）。Lレベルは0.25Vで合格。新しく生じた制限：プルアップ全体の合成値が約970Ω（3.3V÷3mA）を下回ると、弱いデバイスのLレベルが0.4Vを超える。センサー基板に載っているプルアップは、合成で約5kΩ以上にとどめる（10kの基板なら2枚まで。SparkFunのQwiic基板の2.2kはジャンパーを切る）。10k×6では0.41Vで要注意。基板のプルアップを使いたい場合は、JP3を切ってR30/R31を外す。5Vのセンサー基板が5Vへプルアップしている場合は、1.2kΩのほうがバスのHレベルが3.3Vに近くなる（10kで5Vへの場合：2.2kΩでは3.61V、1.2kΩでは3.48V）。'},
 'tb10': {
   'title': 'CAN フロントエンド（5条件）',
   'group': 'I2C・CAN・GPIO', 'parts': 'J3、U7 PESD1CAN、U6 TJA1042T/3、R60（STB）、R61、C14・C18',
   'what': 'CANの受信と、車両側からの異常（電源への短絡、24Vジャンプスタート、ISO 7637-3の高速パルス）で、U6のバスピンが絶対最大定格（±58V）を超えないかを確認する。',
   'steps': ['車両のCANバス：両端に120Ω（合計60Ω）、相手のECUが500kbpsで送信、OBDケーブル1m、U7とU6の間に基板の配線10nH',
             '受信：相手が送ったビット列をU6のRXDが受ける',
             '短絡：20µsでJ3のCANHを14.4V（バッテリー）または24V（24Vジャンプスタート）に短絡',
             'パルス：30µsでISO 7637-3のパルスa（−150V）またはb（+100V）を、50Ω・100pFで両方の線に加える'],
   'cases': ['tb10_rx', 'tb10_short14', 'tb10_short24', 'tb10_pulse_a', 'tb10_pulse_b'],
   'charts': [{'title': '受信（0〜20µs）', 'xunit': 'µs', 'xscale': 1e6, 'xmin': 0, 'xmax': 2e-5,
       'panels': [{'label': 'バス [V]', 'traces': [('tb10_rx:ch', 'CANH（U6）'), ('tb10_rx:cl', 'CANL（U6）')], 'ymin': 0, 'ymax': 5},
                  {'label': 'ロジック [V]', 'traces': [('tb10_rx:txr', '相手ECUのTXD'), ('tb10_rx:rxd', 'U6のRXD（XIAOへ）')], 'ymin': -0.2, 'ymax': 3.6}]},
      {'title': 'CANHの短絡（19.9〜22µs）', 'xunit': 'µs', 'xscale': 1e6, 'xmin': 1.99e-5, 'xmax': 2.2e-5,
       'panels': [{'label': 'U6のCANH [V]', 'traces': [('tb10_short14:ch', '14.4Vに短絡'), ('tb10_short24:ch', '24Vに短絡')],
                   'limits': [{'y': 58, 'label': 'TJA1042 上限 58V', 'kind': 'ng'}, {'y': 16, 'label': '旧SN65HVD230 上限 16V', 'kind': 'warn'}], 'ymin': 0, 'ymax': 62}]},
      {'title': 'ISO 7637-3 パルス（29.95〜30.4µs）', 'xunit': 'µs', 'xscale': 1e6, 'xmin': 2.995e-5, 'xmax': 3.04e-5,
       'panels': [{'label': 'U6のCANH [V]', 'traces': [('tb10_pulse_a:jh', 'J3（パルスa）'), ('tb10_pulse_a:ch', 'U6（パルスa）'), ('tb10_pulse_b:ch', 'U6（パルスb）')],
                   'limits': [{'y': 58, 'label': '+58V', 'kind': 'ng'}, {'y': -58, 'label': '−58V', 'kind': 'ng'}, {'y': 16, 'label': '旧16V', 'kind': 'warn'}], 'ymin': -62, 'ymax': 62}]}],
   'comment': 'すべて合格。受信の差動電圧は2.08V。24Vに短絡すると、つないだ瞬間の振動でCANHは最大41Vになるが、TJA1042の±58V以内（旧SN65HVD230の16Vは超えていた）。短絡が続いてもPESD1CANは導通しない（J3から流れ込むのはU6の入力抵抗の分の1.7mAだけ）。ISO 7637-3のパルスはPESD1CANが−33〜+31Vに抑える。なお、このモデルにはICの内部の伝搬遅延は入れていない。'},
 'tb11': {
   'title': 'GPIO の誤配線保護（R80〜R84 1kΩ、3条件）',
   'group': 'I2C・CAN・GPIO', 'parts': 'R80〜R84 1k（v2.4.1で100Ωから変更。XIAOのピンとポートの間の直列抵抗）、XIAO ESP32-S3',
   'what': 'ポートの信号ピン（PULSE-A/B、GPS、AUX）に、誤って12V（ポートの1番ピン）や25V（ロードダンプ時）をつないだとき、XIAOが壊れないかを確認する。あわせて、1kΩにしたことで通常の信号が遅くならないかを確認する。',
   'steps': ['0.1〜1.5ms：信号ピンに12Vまたは25Vをつなぐ', 'ESP32のピンはESDダイオードで3.3Vにクランプされる。XIAOの3.3V（LDO）は電流を吸い込めないので、流れ込む電流が3.3Vの消費より多いと3.3Vが上がる',
             '3.3Vの消費は動作中40mA。参考としてスリープ中の5mAも確認', '通常使用：受信（GPSのTX→ケーブル→1k→ピン）と送信（ピン→1k→ケーブル100pF→GPSのRX、921600bps）の立ち上がり'],
   'cases': ['tb11_12v', 'tb11_25v', 'tb11_12v_sleep'],
   'charts': [{'title': '誤配線（0〜1.6ms）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0, 'xmax': 0.0016,
       'panels': [{'label': 'XIAOの3.3V [V]', 'traces': [('tb11_12v:v3', '12V'), ('tb11_25v:v3', '25V'), ('tb11_12v_sleep:v3', '12V・スリープ中')],
                   'limits': [{'y': 3.6, 'label': 'ESP32-S3 絶対最大 3.6V', 'kind': 'ng'}], 'ymin': 0, 'ymax': 6},
                  {'label': 'ピンの電流 [mA]', 'traces': [('tb11_12v:irm', '12V'), ('tb11_25v:irm', '25V'), ('tb11_12v_sleep:irm', '12V・スリープ中')],
                   'ymin': 0, 'ymax': 30}]}],
   'comment': '1kΩにしたことで、12Vの誤配線でもピンの電流は8mA、XIAOの3.3Vは3.30Vのままで合格（100Ωのときは75mA流れて3.3Vが6.1Vまで上がり、壊れていた）。25V（ロードダンプの短い間）は21mAで要注意だが、3.3Vは上がらない。注意：マイコンがスリープなどで3.3Vの消費が8mA未満だと、12Vでも3.3Vが3.67Vまで上がる。ファームの仕様にはスリープがない（動作中の消費は数十mA）ので通常は問題ないが、将来スリープを使う場合は3.3Vに数mAの負荷（例：470Ω）を足すこと。信号への影響：受信の立ち上がりは16ns、送信は235ns（ケーブル100pF）。921600bpsでも1ビットの22%で通信はできるが、GPSは460800bps以下を推奨。AUXで1-Wireを使う場合は、プルアップを4.7k以上にする（マイコンがLにしたときの電圧が0.58V。2.2kでは1.0Vになり、DS18B20のL判定0.8Vを超える）。'},
 'tb6': {
   'title': '保持時間のばらつき（4条件）',
   'group': '電源制御', 'parts': 'C11, R2, ZD1, U5',
   'what': 'マイコンのピンがHi-Zになってからリレーが切れるまでの時間（保持時間）を、部品のばらつきの4条件で比べる。',
   'steps': ['1秒：ピンがHi-Zになる（それまではHで3.3V）', 'HOLD_Nが放電し、VT−を下回るとリレーが切れる',
             '標準：C11 10µF（v1.8で4.7µFから変更）、R2 1MΩ、VT− 1.0V、ZD1は膝がなだらかなモデル（漏れ多め）',
             '最悪：C11 −20%（8µF）、R2 −5%、VT− 1.2V ／ 最良：C11 +20%（12µF）、R2 +5%、VT− 0.8V、漏れの少ないZD1'],
   'cases': ['tb6_nom', 'tb6_sharpZ', 'tb6_worst', 'tb6_best'],
   'charts': [{
     'title': 'HOLD_Nの放電（4条件）', 'xunit': 's', 'xscale': 1, 'xmin': 0, 'xmax': 20,
     'events': [{'t': 1.0, 'label': 'ピンHi-Z'}],
     'panels': [{'label': 'HOLD_N [V]', 'traces': [('tb6_nom:holdn', '標準'), ('tb6_sharpZ:holdn', '漏れの少ないZD1'),
                                                  ('tb6_worst:holdn', '最悪'), ('tb6_best:holdn', '最良')],
                 'limits': [{'y': 1.2, 'label': 'VT− 1.2V（最悪）', 'kind': 'warn'}, {'y': 1.0, 'label': 'VT− 1.0V（標準）', 'kind': 'ref'},
                            {'y': 0.8, 'label': 'VT− 0.8V（最良）', 'kind': 'ref'}], 'ymin': 0, 'ymax': 3.6}]}],
   'bars': {'title': '保持時間', 'unit': '秒', 'items': [('tb6_nom', '標準'), ('tb6_sharpZ', '漏れの少ないZD1'), ('tb6_worst', '最悪'), ('tb6_best', '最良')],
            'meas': 'hold_s', 'limits': [{'y': 2, 'label': 'リセットに必要 2秒', 'kind': 'ng'}, {'y': 3, 'label': 'WDT 3秒（ファーム仕様）', 'kind': 'warn'}], 'max': 20},
   'comment': 'v1.8でC11を10µFにした結果、保持時間は4.6〜17.5秒（標準7.9秒）。最悪条件でもファーム仕様の「WDTの3秒より長いこと」を満たす（4.7µFでは最悪2.2秒だった）。'},
 'tb7': {
   'title': 'パルス入力アダプター（7条件）',
   'group': 'パルス入力', 'parts': 'PULSE-INアダプター：R1〜R4, C1, DZ1, U1 74LVC1G17, U2 XC6206, JP1, JP2。メイン基板側：ケーブル100pF、R80/R81 1k（v2.4.1）、XIAOのピン10pF',
   'what': '車速パルス・タコ信号・外付けセンサーのパルスを、J8/J9につなぐ小基板（PULSE-IN）で3.3Vの信号に変換できるかを確認する。',
   'steps': ['入力：12V方形波（Lが0.8V浮いた状態も含む）、オープンコレクタ（5V／12Vプルアップ）、3.3Vセンサー 5kHz',
             '22kの直列抵抗＋1nFで高周波ノイズを落とし、4.7Vツェナーで電圧を抑え、74LVC1G17（シュミット）で波形を整える',
             'JP2を閉じると10kが入り、しきい値が約5.8V／3.2Vに上がる（ノイズの多い12V信号向け。5V信号では使えない）',
             '40Vのスパイクを重ねても、U1の入力は4.7V前後に抑えられることを確認'],
   'cases': ['tb7_speed12', 'tb7_tach12_jp2', 'tb7_oc5', 'tb7_oc12_jp2', 'tb7_sensor3v3', 'tb7_spike', 'tb7_5v_jp2_ng'],
   'charts': [{'title': '12V方形波 200Hz（車速パルス想定）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0, 'xmax': 0.03,
       'panels': [{'label': '入力 [V]', 'traces': [('tb7_speed12:sigin', '入力（SIG_IN）')], 'ymin': -0.5, 'ymax': 14},
                  {'label': 'アダプター [V]', 'traces': [('tb7_speed12:siga', 'U1入力（SIG_A）'), ('tb7_speed12:out', 'XIAOのピン（R80/R81 1kの後）')],
                   'limits': [{'y': 1.8, 'label': 'VT+ 1.8V', 'kind': 'ref'}, {'y': 1.0, 'label': 'VT− 1.0V', 'kind': 'ref'}, {'y': 5.5, 'label': '推奨上限 5.5V', 'kind': 'ng'}],
                   'ymin': -0.3, 'ymax': 6}]},
              {'title': 'オープンコレクタ・5Vプルアップ 200Hz', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0, 'xmax': 0.03,
       'panels': [{'label': '入力 [V]', 'traces': [('tb7_oc5:sigin', '入力（SIG_IN）')], 'ymin': -0.5, 'ymax': 14},
                  {'label': 'アダプター [V]', 'traces': [('tb7_oc5:siga', 'U1入力（SIG_A）'), ('tb7_oc5:out', 'XIAOのピン（R80/R81 1kの後）')],
                   'limits': [{'y': 1.8, 'label': 'VT+ 1.8V', 'kind': 'ref'}, {'y': 1.0, 'label': 'VT− 1.0V', 'kind': 'ref'}, {'y': 5.5, 'label': '推奨上限 5.5V', 'kind': 'ng'}],
                   'ymin': -0.3, 'ymax': 6}]},
              {'title': '3.3Vセンサー 5kHz', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0, 'xmax': 0.0012,
       'panels': [{'label': '入力 [V]', 'traces': [('tb7_sensor3v3:sigin', '入力（SIG_IN）')], 'ymin': -0.5, 'ymax': 14},
                  {'label': 'アダプター [V]', 'traces': [('tb7_sensor3v3:siga', 'U1入力（SIG_A）'), ('tb7_sensor3v3:out', 'XIAOのピン（R80/R81 1kの後）')],
                   'limits': [{'y': 1.8, 'label': 'VT+ 1.8V', 'kind': 'ref'}, {'y': 1.0, 'label': 'VT− 1.0V', 'kind': 'ref'}, {'y': 5.5, 'label': '推奨上限 5.5V', 'kind': 'ng'}],
                   'ymin': -0.3, 'ymax': 6}]},
              {'title': '12V方形波＋40Vスパイク（0.5ms〜）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0, 'xmax': 0.03,
       'panels': [{'label': '入力 [V]', 'traces': [('tb7_spike:sigin', '入力（SIG_IN）')], 'ymin': -0.5, 'ymax': 14},
                  {'label': 'アダプター [V]', 'traces': [('tb7_spike:siga', 'U1入力（SIG_A）'), ('tb7_spike:out', 'XIAOのピン（R80/R81 1kの後）')],
                   'limits': [{'y': 1.8, 'label': 'VT+ 1.8V', 'kind': 'ref'}, {'y': 1.0, 'label': 'VT− 1.0V', 'kind': 'ref'}, {'y': 5.5, 'label': '推奨上限 5.5V', 'kind': 'ng'}],
                   'ymin': -0.3, 'ymax': 6}]},
              {'title': '5V信号でJP2を閉じた場合（出力が出ない＝使えない組み合わせ）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0, 'xmax': 0.006,
       'panels': [{'label': '入力 [V]', 'traces': [('tb7_5v_jp2_ng:sigin', '入力（SIG_IN）')], 'ymin': -0.5, 'ymax': 14},
                  {'label': 'アダプター [V]', 'traces': [('tb7_5v_jp2_ng:siga', 'U1入力（SIG_A）'), ('tb7_5v_jp2_ng:out', 'XIAOのピン（R80/R81 1kの後）')],
                   'limits': [{'y': 1.8, 'label': 'VT+ 1.8V', 'kind': 'ref'}, {'y': 1.0, 'label': 'VT− 1.0V', 'kind': 'ref'}, {'y': 5.5, 'label': '推奨上限 5.5V', 'kind': 'ng'}],
                   'ymin': -0.3, 'ymax': 6}]}],
   'comment': '7条件すべてで、入力のパルスを抜けも余分もなく3.3Vの信号に変換できた。U1の入力は最大4.6Vで、推奨上限5.5V以下。5V以下の信号ではJP2を開けたままにする。'},
}


def kline_charts(c):
    lim = [{'y': 0.2 * 13.8, 'label': 'L判定 20%VBAT', 'kind': 'ng'}, {'y': 0.8 * 13.8, 'label': 'H判定 80%VBAT', 'kind': 'ref'}]
    logic = {'label': 'ロジック [V]', 'traces': [(c + ':txs', 'MCU TX（KL_TXS）'), (c + ':rxd', 'RXD（エコー）'), (c + ':kgate', 'Q9ゲート')], 'ymin': -0.2, 'ymax': 3.8}
    k = {'label': 'K-Line [V]', 'traces': [(c + ':kline', 'K-Line')], 'limits': lim, 'ymin': -0.5, 'ymax': 15}
    return [
        {'title': '送信パターン全体', 'xunit': 's', 'xscale': 1, 'xmin': 0.2, 'xmax': 2.9,
         'bands': [{'t0': 0.3, 't1': 0.35, 'label': 'ファスト初期化'}, {'t0': 0.6, 't1': 2.6, 'label': '5ボー初期化（アドレス0x33）'}],
         'panels': [k, logic]},
        {'title': '拡大：ファスト初期化と10400bpsのバイト（0.29〜0.41秒）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0.29, 'xmax': 0.4025,
         'bands': [{'t0': 0.3, 't1': 0.325, 'label': 'L 25ms'}], 'events': [{'t': 0.4, 'label': '0xC1 0x33'}],
         'panels': [k, logic]},
        {'title': '拡大：5ボー初期化のスタートビット（0.59〜0.82秒）', 'xunit': 'ms', 'xscale': 1000, 'xmin': 0.59, 'xmax': 0.82,
         'bands': [{'t0': 0.6, 't1': 0.627, 'label': 'TJA1021 タイムアウト 27ms'}],
         'panels': [k, logic]},
    ]


def dump_charts(c):
    return [{
        'title': 'ロードダンプ（0〜0.9秒）', 'xunit': 's', 'xscale': 1, 'xmin': 0, 'xmax': 0.9,
        'events': [{'t': 0.05, 'label': 'バッテリー外れ'}],
        'panels': [
            {'label': '電圧 [V]', 'traces': [(c + ':alt', 'オルタネーター開放電圧'), (c + ':vsw', 'VSW'), (c + ':acc', 'ACC')],
             'limits': [{'y': 35, 'label': 'DFR0946 上限 35V', 'kind': 'ng'}, {'y': 40, 'label': 'TJA1021 上限 40V', 'kind': 'ref'}],
             'ymin': 0, 'ymax': 90},
            {'label': 'TVS電流 [A]', 'traces': [(c + ':itvs1', 'TVS1 SM8S20A'), (c + ':itvs2', 'TVS2 SMAJ20A')], 'ymin': 0, 'ymax': 55},
            {'label': 'TVS1エネルギー [J]', 'traces': [(c + ':etvs1', 'TVS1 累積エネルギー')],
             'limits': [{'y': 75, 'label': '目安 75J', 'kind': 'warn'}], 'ymin': 0, 'ymax': 180},
            {'label': '+5V [V]', 'traces': [(c + ':v5', '+5V'), (c + ':v5s', '+5VS（センサー用）')], 'limits': [{'y': 4.5, 'label': '4.5V', 'kind': 'ng'}], 'ymin': 0, 'ymax': 6},
        ]}]


def derived(name, cols, d):
    """extra columns computed from the waveform file"""
    t = d[:, 0]
    out = {}
    if name.startswith('tb4'):
        v = d[:, 2 * cols.index('vsw') + 1]; i = d[:, 2 * cols.index('itvs1') + 1]
        p = v * i
        out['etvs1'] = np.concatenate([[0], np.cumsum(0.5 * (p[1:] + p[:-1]) * np.diff(t))])
    if name.startswith('tb11'):
        out['irm'] = d[:, 2 * cols.index('ir') + 1] * 1000
    if name == 'tb2_sweep':
        out['accs_ideal'] = d[:, 2 * cols.index('vsup') + 1] / (54.8 / 6.8)
    return out


def decimate(t, y, n=NPTS):
    if len(t) <= 2 * n:
        return t, y
    edges = np.linspace(t[0], t[-1], n + 1)
    idx = np.searchsorted(t, edges)
    xs, ys = [], []
    for a, b in zip(idx[:-1], idx[1:]):
        if b <= a:
            continue
        seg = y[a:b]
        i1, i2 = a + int(np.argmin(seg)), a + int(np.argmax(seg))
        for i in sorted({i1, i2}):
            xs.append(t[i]); ys.append(y[i])
    xs.append(t[-1]); ys.append(y[-1])
    return np.array(xs), np.array(ys)


def build():
    res = json.load(open(os.path.join(OUT, 'results.json'), encoding='utf-8'))
    cases = {c['name']: c for c in res['cases']}
    wave = {}
    for name, c in cases.items():
        f = os.path.join(OUT, name + '.txt')
        if not os.path.exists(f):
            continue
        d = np.loadtxt(f); t = d[:, 0]; cols = c['columns']
        cols_all = {k: d[:, 2 * j + 1] for j, k in enumerate(cols)}
        cols_all.update(derived(name, cols, d))
        wave[name] = (t, cols_all)

    def trace(key, xkey=None, tmax=None, x0=None, x1=None, scale=1):
        cn, col = key.split(':')
        t, cs = wave[cn]
        y = cs[col]
        if xkey:
            x = wave[xkey.split(':')[0]][1][xkey.split(':')[1]]
            m = t <= tmax if tmax else np.ones_like(t, bool)
            x, y = x[m], y[m]
            o = np.argsort(x, kind='stable'); x, y = x[o], y[o]
        else:
            x = t
        if x0 is not None:
            m = (x >= x0 - (x1 - x0) * 0.02) & (x <= x1 + (x1 - x0) * 0.02)
            x, y = x[m], y[m]
        x, y = decimate(x, y)
        return {'x': [round(float(v) * scale, 7) for v in x], 'y': [round(float(v), 4) for v in y]}

    tests = []
    for key, sp in SPEC.items():
        names = sp.get('cases', [key])
        if not all(n in cases for n in names):
            continue
        charts = sp['charts']
        if isinstance(charts, str):
            kind, cn = charts.split(':')
            charts = kline_charts(cn) if kind == 'kline' else dump_charts(cn)
        outc = []
        for ch in charts:
            sc = ch.get('xscale', 1)
            ch2 = {k: v for k, v in ch.items() if k not in ('panels', 'marks')}
            ch2['xmin'] = ch.get('xmin', None); ch2['xmax'] = ch.get('xmax', None)
            if ch2['xmin'] is not None:
                ch2['xmin'] *= sc; ch2['xmax'] *= sc
            ch2['events'] = [dict(e, t=e['t'] * sc) for e in ch.get('events', [])]
            ch2['bands'] = [dict(b, t0=b['t0'] * sc, t1=b['t1'] * sc) for b in ch.get('bands', [])]
            marks = []
            for m in ch.get('marks', []):
                cn, mn = m['meas'].split(':')
                v = cases[cn]['meas'].get(mn)
                if v is None:
                    continue
                if m.get('yis') == 'value':
                    tt = cases[cn]['meas'].get(mn + '_at')
                    marks.append({'y': v, 'label': f"{m['label']} {v:.3g}"})
                else:
                    marks.append({'t': v * (1 if m.get('xis') == 'value' else sc), 'label': f"{m['label']} {v:.3g}{'V' if m.get('xis') == 'value' else ch['xunit']}"})
            ch2['marks'] = marks
            ch2['panels'] = []
            for p in ch['panels']:
                p2 = {k: v for k, v in p.items() if k != 'traces'}
                p2['traces'] = []
                for tk, lab in p['traces']:
                    x0 = ch.get('xmin'); x1 = ch.get('xmax')
                    if ch.get('xtrace'):
                        tr = trace(tk, ch['xtrace'], ch.get('tmax'))
                    else:
                        tr = trace(tk, None, None, x0, x1, sc)
                    tr['name'] = lab
                    p2['traces'].append(tr)
                ch2['panels'].append(p2)
            outc.append(ch2)
        checks, worst = [], 'PASS'
        for n in names:
            for ck in cases[n]['checks']:
                checks.append(dict(ck, case=n))
                if ck['result'] == 'FAIL' or (ck['result'] == 'WARN' and worst == 'PASS'):
                    worst = ck['result']
        bars = None
        if sp.get('bars'):
            b = sp['bars']
            bars = dict(b, items=[{'label': lab, 'value': cases[cn]['meas'].get(b['meas'])} for cn, lab in b['items']])
        tests.append({'id': key, 'title': sp.get('title') or cases[names[0]]['title'],
                      'tb': cases[names[0]]['tb'], 'group': sp['group'], 'parts': sp['parts'], 'what': sp['what'],
                      'steps': sp['steps'], 'comment': sp['comment'], 'status': worst, 'charts': outc,
                      'checks': checks, 'bars': bars, 'cases': names, 'schem': schem_for(key)})
    return {'date': res['date'], 'tests': tests, 'schem': load_schem()}


# --------------------------------------------------------------------------------------
# Schematics shown on the page: schem/bN.svg (easy-to-read, drawn by schem/blocks.py) and
# schem/bN.png (crop of the real KiCad sheet pwrctrl.kicad_sch, for checking).
# --------------------------------------------------------------------------------------
SCHEM = [
 ('b1', '① 電源入力と7Aの経路', 'J1の常時12V（+B）をリレーK1で切り替えてVSWを作り、PC電源（J2）へ最大7A送る。VSWからはマイコン用（D7→U1）とセンサー用（F4→U8）に分かれる。ACCはTVS2で保護してから各回路へ。'),
 ('b2', '② マイコン用5V（U1 XL7015）', '12V→5.3Vの降圧DC-DC。D8（逆流防止）の後が+5VでXIAOとTJA1042へ。USBから給電したときにDC-DCへ電気が戻らない。'),
 ('b3', '③ リレー保持回路（暗電流ゼロ）', 'ACCかマイコンのHOLDでC11を充電し、シュミットバッファU5→Q1でリレーを入れる。マイコンが止まると約8秒で自動的に切れる。'),
 ('b4', '④ XIAO ESP32-S3のピン割り当て', 'どのピンがどの回路・コネクタにつながるか。外に出るピンには直列抵抗（R80〜R84、v2.4.1で1kΩ）が入る。PCボタン（JP2）はR84の前につながる。'),
 ('b5', '⑤ 車両通信（CAN／K-Line）', 'J3から入った線は、まず保護素子（U7／TVS3）を通ってからICへ。CANはTJA1042T/3、K-LineはTJA1021と直接駆動（Q9）。'),
 ('b6', '⑥ I2Cプルアップ・PCボタン・J5', 'I2Cのプルアップ（JP3で切り離し可）、D10でPCの電源ボタンを押すフォトカプラ、デバッグ用J5のピン表。'),
 ('b7', '⑦ センサー用電源（U8 XL7015＋U9 AMS1117）', 'VSW_EXT（F4の後）から+5VSと+3V3Sを作り、I2C・パルス入力・GPSのポートへ配る。'),
]
SCHEM_FOR = [('tb1', ['b1', 'b3', 'b2', 'b7']), ('tb2', ['b1', 'b4', 'b2', 'b7']), ('tb3', ['b5']),
             ('tb4', ['b1', 'b7']), ('tb5', ['b1', 'b2', 'b7']), ('tb6', ['b3']), ('tb7', ['b4']),
             ('tb8', ['b2', 'b7']), ('tb9', ['b6']), ('tb10', ['b5']), ('tb11', ['b4'])]


def schem_for(key):
    for p, bl in SCHEM_FOR:
        if key == p or key.startswith(p + '_'):
            return bl
    return []


def load_schem():
    import base64
    out = []
    for bid, title, desc in SCHEM:
        p = os.path.join(HERE, 'schem', bid + '.svg')
        if not os.path.exists(p):
            continue
        svg = open(p, encoding='utf-8').read()
        svg = svg[svg.index('<svg'):]
        svg = re.sub(r'<metadata>.*?</metadata>', '', svg, flags=re.S)
        svg = re.sub(r'\swidth="[^"]*pt"\sheight="[^"]*pt"', '', svg, count=1)
        svg = svg.replace('#000000', 'currentColor').replace('<svg ', '<svg fill="currentColor" ', 1)
        png = os.path.join(HERE, 'schem', bid + '.png')
        img = ('data:image/png;base64,' + base64.b64encode(open(png, 'rb').read()).decode()) if os.path.exists(png) else None
        out.append({'id': bid, 'title': title, 'desc': desc, 'svg': svg, 'kicad': img})
    return out


def main():
    data = build()
    tpl = open(os.path.join(HERE, 'report_template.html'), encoding='utf-8').read()
    body = tpl.replace('/*__DATA__*/null', json.dumps(data, ensure_ascii=False, separators=(',', ':')))
    open(os.path.join(OUT, 'report_body.html'), 'w', encoding='utf-8').write(body)
    full = '<!doctype html>\n<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n' + \
           body.replace('<!--BODY-->', '</head><body>') + '\n</body></html>\n'
    open(os.path.join(OUT, 'report.html'), 'w', encoding='utf-8').write(full)
    print('-> out/report.html', f'({len(full) / 1e6:.2f} MB)')


if __name__ == '__main__':
    main()
