.include ../models/lm2576hv_trans.lib
* ---------- ハブ用 5V（LM2576HV、5.0V設定） ----------
RF3   VSW vin5a 20m                      ; F3 4A ブレードヒューズ
D11   vin5a VIN5 SS56                    ; 逆電圧（ISOパルス1など）からLM2576を守る
C10   VIN5 c10 100u
RC10  c10 0 0.15                         ; 電解 100uF/63V の ESR
C11   VIN5 0 1u
RBL5  VIN5 0 1Meg                         ; シミュレーション用（入力が浮くのを防ぐ）
XU3   VIN5 SWO 0 FB5 ONOFF LM2576HV_TRANS
* 低電圧で止める（UVLO）：VIN5が約5.6V未満ではON/OFF端子をHにして停止、それ以上でQ6がONしてL（クランキングの6Vでは動き続ける）
R40   VIN5 ONOFF 100k
XZ40  q6b0 VIN5 DZ4V7
R41   q6b0 q6b 10k
R42   q6b 0 22k
Q6    ONOFF q6b 0 MMBT3904
C40   ONOFF 0 10n
R43   V5 q6b 100k                        ; ヒステリシス：5Vが出ている間はONを保つ
D10   0 SWO SS56
L1    SWO l1 100u
RL1   l1 V5 40m
C12   V5 c12 1000u
RC12  c12 0 40m
C13   V5 0 10u
RFB1  V5 FB5 3.07k
RFB2  FB5 0 1k
