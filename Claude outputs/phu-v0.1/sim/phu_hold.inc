* =====================================================================
* PHU 電源・ハブユニット  回路（v0.1 書き起こし）  共通ネットリスト
*   外部から与えるノード：VBAT_IN（+B、ハーネスのヒューズの前）、ACC_IN
*                         HOLD_CLK・DISCH（XIAOのピン、テストベンチの電源で模擬）
*   出力ノード：VSW（リレーの後ろ）、V5（ハブ用5V）
*   パラメータ：CH（保持コンデンサの実効容量）
* =====================================================================
.include ../models/lm2903_beh.lib
.include ../models/tl431_beh.lib
.include ../models/si2309ds.lib
.include ../models/smcj_bourns.lib
.include ../models/discrete.lib

* ---------- 入力（ハーネス：F1 15A／F2 1A、線の抵抗を含む） ----------
RF1   VBAT_IN VBAT 15m
RF2   ACC_IN  ACC  0.2

* ---------- メインリレー K1（G2RL-1A-E DC12） ----------
XK1   COILP 0 VBAT VSW RELAY_G2RL
D1    ACC   COILP SS14            ; ACCでコイルを直接ON（ショットキーで電圧降下を小さく）
D2    0     COILP 1N4148WS        ; フライバック
* 自己保持：VSW → Q2（Pch）→ コイル
XQ2   Q2D QG VSW Si2309DS         ; D G S
D8    Q2D COILP SS14              ; Q2のボディダイオード経由でACCがVSWへ流れ込むのを防ぐ（SPICEで発見）
XZ2   QG z2k DI_BZT52C12          ; ゲート保護 12V
VsZ2  VSW z2k 0                  ; 電流測定用（0V）
R11   QG VSW 100k
R12   QG Q3D 10k
XQ3  Q3D Q3G 0 N2N7002
R13   Q3G 0 100k

* ---------- 比較器の電源 VCMP（ACCかVSWから、15Vでクランプ） ----------
D3    ACC VCR 1N4148WS
D4    VSW VCR 1N4148WS
R5    VCR VCMP 1k                    ; 1206（35Vで0.36W、0.4秒）
XZ1   0 z1k DI_BZT52C15
VsZ1  VCMP z1k 0                 ; 電流測定用（0V）
C3    VCMP 0 1u
* 基準電圧 2.495V
R6    VCMP r6b 2.2k                  ; TL431のImin（最大1mA）を9Vでも確保
Vs431 r6b VREF 0                 ; 電流測定用（0V）
XU2   VREF 0 VREF TL431

* ---------- 保持タイマー（比較器 LM2903 ×2回路） ----------
* U1A：HN が しきい値を超えると OUTA=L
XU1A  TH HN VCMP 0 OUTA LM2903B
R7    VREF TH 100k
R8    TH 0 100k
R9    OUTA TH 1Meg
CTH   TH 0 10p        ; 配線の浮遊容量
R10   VCMP OUTA 10k
* U1B：反転（OUTA=L → Q3G=H → Q3 ON → Q2 ON）
XU1B  VREF OUTA VCMP 0 Q3G LM2903B
R14   VCMP Q3G 10k

* 保持ノード HN
C1    HN 0 {CH}
R1    HN 0 2.2Meg
D5    ACC HA 1N4148WS
R2    HA HN 4.7Meg

* マイコンからのチャージポンプ（矩形波が止まると保持できない）
R17   HOLD_CLK Q4G 1k
R18   Q4G 0 100k
XQ4  PD Q4G 0 N2N7002
R19   VCMP PD 10k
C2    PD P 100n
D6    P HN DI_BAV99
D7    0 P DI_BAV99

* 急速OFF（マイコンがHにするとHNを放電）
R20   DISCH Q5G 1k
R21   Q5G 0 100k
XQ5  HD Q5G 0 N2N7002
R22   HN HD 1k

* ---------- VSW の保護 ----------
XTVS1 0 tvsk SMCJ33A
VsTVS VSW tvsk 0                 ; 電流測定用（0V）
C4    VSW 0 1u

* ---------- 電圧の監視（XIAO の ADC：D0=ACC、D1=VSW） ----------
R30   ACC AM 68k
R31   AM 0 6.8k
C30   AM 0 100n
R32   AM ADC0 10k
R33   VSW VM 68k
R34   VM 0 6.8k
C31   VM 0 100n
R35   VM ADC1 10k

