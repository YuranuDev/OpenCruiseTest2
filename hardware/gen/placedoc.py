import sys; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
from pcbbuild import read_net
comps=read_net('/home/claude/pcb/pwrctrl/pwrctrl.net')
b=pcbnew.LoadBoard('/home/claude/pcb/pwrctrl/pwrctrl.kicad_pcb')
G=[('1 電源入力・メインスイッチ',0,8,45,52),('3 リレー保持回路',40,22,66,44),('2 5V補助電源',62,2,111,44),
   ('5 車両通信（CAN/K-Line）',0,52,45,91),('4 マイコン（XIAO）',45,55,68,91),('6 拡張端子・I2C・電源ボタン',68,44,111,91)]
FUNC={'J1':'電源入力（+B/ACC/GND）','J2':'VSW出力→DFR0946','K1':'メインリレー','TVS1':'サージ保護（VSW）','C1':'VSW平滑','C2':'VSW平滑','C3':'VSW平滑',
'TVS2':'ACCサージ保護','LED1':'VSW表示','R40':'LED1抵抗','U1':'5V降圧IC','L1':'降圧インダクタ','D11':'降圧キャッチダイオード','C4':'降圧入力','C5':'降圧入力','C6':'5V出力','C7':'5V出力',
'D7':'VSW→降圧OR','D9':'ACC→降圧OR','D8':'5V逆流防止','R50':'FB上側','R51':'FB下側','C8':'FB位相補償','C9':'+5Vバイパス','F5':'外部5V PTC','LED2':'5V表示','R41':'LED2抵抗',
'D1':'コイル給電（ACC）','D2':'コイル給電（VSW）','D5':'フライバック','Q1':'コイル駆動','R11':'Q1ゲートPD','U5':'シュミットバッファ','C10':'U5バイパス','D3':'ACC保持','R3':'ACC保持抵抗','R1':'HOLD直列','C11':'保持時定数','R2':'保持放電','ZD1':'保持ノードクランプ',
'U2':'XIAO ESP32S3（ソケット）','C13':'3V3バイパス','R5':'ACC分圧上','R6':'ACC分圧下','ZD2':'ACC検知クランプ','C12':'ACC検知フィルタ',
'J3':'車両診断（K/CANH/CANL/GND）','U6':'CANトランシーバ','U7':'CAN ESD','R62':'CAN終端（未実装）','R60':'CAN Rs','R61':'CAN TXDプルアップ','JP1':'CAN送信許可','C14':'U6バイパス',
'U4':'K-Lineトランシーバ','C15':'U4バイパス','C16':'U4バイパス','R70':'KL RXDプルアップ','R71':'KL SLP','R72':'KL TXDプルアップ','JP6':'KL TJA送信許可','R73':'KL_TXSプルアップ','D10':'Kプルアップ用ダイオード','R14':'Kプルアップ510Ω','TVS3':'Kサージ保護','C17':'K容量（未実装）',
'Q8':'直接駆動 反転','R20':'Q8ベース','R21':'Q8ベースPD','R22':'Q8コレクタPU','JP7':'直接駆動 有効','R23':'Q9ゲートPD','Q9':'K直接駆動','F3':'K直接駆動PTC','JP4':'TX切替 CAN/KL','JP5':'RX切替 CAN/KL',
'J5':'拡張 2x10','F4':'VSW_EXT PTC','J8':'拡張 XH4 A','J9':'拡張 XH4 B','J6':'Qwiic A','J7':'Qwiic B','JP3':'I2Cプルアップ切離し','R30':'SDAプルアップ','R31':'SCLプルアップ',
'JP2':'電源ボタン接続','R12':'フォトカプラLED抵抗','R13':'PWRB PD','U3':'フォトカプラ（未実装）','J4':'PC電源SW（未実装）'}
rows=[]
for fp in b.GetFootprints():
    r=fp.GetReference(); x=pcbnew.ToMM(fp.GetPosition().x); y=pcbnew.ToMM(fp.GetPosition().y)
    blk=next((g[0] for g in G if g[1]<=x<g[3] and g[2]<=y<g[4]),'—')
    if r.startswith('H'): blk='取付穴'; f='M3取付穴'
    elif r.startswith('TP'): f='テストポイント '+fp.GetValue()
    else: f=FUNC.get(r,'')
    c=comps.get(r,{}); dnp='未実装（DNP）' if fp.IsDNP() else ''
    rows.append((blk,r,fp.GetValue(),f,x,y,fp.GetOrientationDegrees(),'表示' if fp.Reference().IsVisible() else '—',dnp))
import re
key=lambda r:(r[0],re.sub(r'\d+','',r[1]),int(re.sub(r'\D','',r[1]) or 0))
rows.sort(key=key)
out=['# メイン基板（PWR-CTRL v1.0）部品配置表','',
'基板サイズ 111×91mm、原点は基板の左上、X→右・Y→下（mm）。座標は部品の中心。回転は反時計回り（度）。',
'シルクの部品番号は、大きい部品で、かつ周囲に余白がある場合だけ表示する（小さいチップ部品・ジャンパー・テストポイントは非表示）。','',
'## 機能ブロック（領域）','','| ブロック | X範囲 | Y範囲 | 内容 |','|---|---|---|---|',
'| 1 電源入力・メインスイッチ | 0–45 | 8–52 | J1/J2を左端に置き、K1、TVS1、C1〜C3。7Aの経路 |',
'| 3 リレー保持回路 | 40–66 | 22–44 | K1のコイル側の直下 |',
'| 2 5V補助電源 | 62–111 | 2–44 | XL7015の降圧回路。車両通信とは対角に配置 |',
'| 5 車両通信 | 0–45 | 52–91 | J3を左端に置き、CAN・K-Line |',
'| 4 マイコン | 45–68 | 55–91 | XIAOのUSB-Cを下端に向ける |',
'| 6 拡張端子 | 68–111 | 44–91 | J5を右端、J8/J9とQwiicを下側に置く |','',
'## 部品一覧','','| ブロック | 部品番号 | 値 | 役割 | X | Y | 回転 | シルク番号 | 備考 |','|---|---|---|---|---|---|---|---|---|']
for r in rows: out.append(f'| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]:.1f} | {r[5]:.1f} | {r[6]:.0f} | {r[7]} | {r[8]} |')
open('/home/claude/pcb/pwrctrl/PLACEMENT.md','w').write('\n'.join(out)+'\n')
print(len(rows))
