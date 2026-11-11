* ---------- ハブ用 5V（LM2576HV）平均化モデル ----------
* 長い時間の試験（始動・ロードダンプ・パルス・突入電流）用。スイッチングは再現しない。
* 値は TIの LM2576HV スイッチングモデル（tb4 で確認）とデータシートに合わせた：
*   出力 5.00V、ドロップアウト 約1.5V（3A）、効率 約80%、電流制限 約4.5A
* 入力側の部品（F3・D11・C10・C11）と UVLO（Q6まわり）は実際の回路と同じ
RF3   VSW vin5a 20m                      ; F3 4A ブレードヒューズ
D11   vin5a VIN5 SS56                    ; 逆電圧からLM2576を守る
C10   VIN5 c10 100u
RC10  c10 0 0.15
C11   VIN5 0 1u
RBL5  VIN5 0 1Meg
* UVLO（実回路と同じ）：約6.3Vで起動、5Vが出ている間はONを保ち、約4Vで停止
R40   VIN5 ONOFF 100k
XZ40  q6b0 VIN5 DZ4V7
R41   q6b0 q6b 10k
R42   q6b 0 22k
Q6    ONOFF q6b 0 MMBT3904
C40   ONOFF 0 10n
R43   V5 q6b 100k
* 変換部（平均化）
Ben   en5 0 V = 0.5*(1-tanh((v(ONOFF)-1.4)*10))
Bset  vset 0 V = v(en5)*0.5*(5.0 + v(VIN5)-1.5 - sqrt((5.0-(v(VIN5)-1.5))^2+0.01))
* 出力：設定電圧の電圧源（出力抵抗10mΩ）。4.5Aを超えると電圧を下げる（電流制限）
Bout  v5i 0 V = max(v(vset) - 2*max(i(Vio)-4.5,0), 0)
Rout  v5i v5s 10m
Vio   v5s V5 0
Bin   VIN5 0 I = v(V5)*max(i(Vio),0)/(0.80*max(v(VIN5),2))
C12   V5 c12 1000u
RC12  c12 0 40m
C13   V5 0 10u
