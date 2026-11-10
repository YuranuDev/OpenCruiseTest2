import sys; sys.path.insert(0,'/home/claude/pcb/gen')
from schgen import Sheet
# EXT-HUB v1.0 : port hub for PWR-CTRL J5 (ribbon 2x10). Own 5 V / 3.3 V supply from VSW_EXT.
S=Sheet('exthub','OpenCruise EXT-HUB (port hub for PWR-CTRL J5)',paper='A3')
R0603='Resistor_SMD:R_0603_1608Metric'; C0603='Capacitor_SMD:C_0603_1608Metric'; C0805='Capacitor_SMD:C_0805_2012Metric'; C1206='Capacitor_SMD:C_1206_3216Metric'
SMA='Diode_SMD:D_SMA'
XH4='Connector_JST:JST_XH_B4B-XH-A_1x04_P2.50mm_Vertical'; XH5='Connector_JST:JST_XH_B5B-XH-A_1x05_P2.50mm_Vertical'
SH4='Connector_JST:JST_SH_SM04B-SRSS-TB_1x04-1MP_P1.00mm_Horizontal'
def R(ref,v,x,y,a,b,lcsc): S.part(ref,'Device','R',x,y,{'1':a,'2':b},value=v,fp=R0603,lcsc=lcsc)
def C(ref,v,x,y,a,b,fp=C0603,lcsc=None,pol=False): S.part(ref,'Device','C_Polarized' if pol else 'C',x,y,{'1':a,'2':b},value=v,fp=fp,lcsc=lcsc)
# ---- input from PWR-CTRL J5 (same pin numbers; HOLD/ACC/VEH/3V3/5V_EXT are NOT used here) ----
S.box(10,10,140,145,'1. FROM PWR-CTRL J5 (2x10 ribbon, pin 1 = red stripe)')
S.part('J1','Connector_Generic','Conn_02x10_Odd_Even',60,70,{'1':None,'2':None,'3':'D2_IN','4':'D3_IN','5':'SDA','6':'SCL','7':'D6_IN','8':'D7_IN','9':None,'10':None,
  '11':'D10_IN','12':None,'13':None,'14':'+12V','15':'GND','16':'GND','17':'GND','18':'GND','19':'GND','20':'GND'},value='from PWR-CTRL J5 (IDC 2x10)',fp='Connector_IDC:IDC-Header_2x10_P2.54mm_Vertical')
R('R1','100',100,30,'D2_IN','D2',lcsc='C22775'); R('R2','100',100,50,'D3_IN','D3',lcsc='C22775')
R('R3','100',100,70,'D6_IN','GPS_RXD',lcsc='C22775'); R('R4','100',100,90,'D7_IN','GPS_TXD',lcsc='C22775'); R('R5','100',100,110,'D10_IN','D10',lcsc='C22775')
S.note('Not connected on purpose: 1 ACC_SENSE, 2 HOLD (pulling it low cuts the PC power), 9/10 vehicle bus, 12 main 3V3, 13 5V_EXT.\nThe hub makes its own 5 V / 3.3 V from pin 14 (VSW, 12 V, fused 1.1 A on the main board).\n100R series resistors protect the XIAO pins against wiring mistakes.',15,130)
# ---- 5 V buck (same circuit as PWR-CTRL U1) ----
S.box(150,10,330,145,'2. 5.3 V BUCK (XL7015) + 3.3 V LDO')
C('C1','100uF/50V',165,45,'+12V','GND',fp='Capacitor_SMD:CP_Elec_8x10.5',lcsc='C48935390',pol=True)
C('C2','1uF/50V',180,45,'+12V','GND',fp=C1206,lcsc='C1848')
S.part('U1','OpenCruise','XL7015E1',210,45,{'1':'+12V','5':'GND','2':'SW','4':'FB','3':'GND','6':'GND'},value='XL7015E1',lcsc='C73013')
S.part('D1','Diode','SS34',240,70,{'1':'SW','2':'GND'},value='SS34',fp=SMA,lcsc='C8678')
S.part('L1','Device','L',250,40,{'1':'SW','2':'+5V'},value='100uH/1A',fp='OpenCruise:L_8040_SWPA8040',lcsc='C83468',mpn='SWPA8040S101MT')
C('C3','100uF/16V',270,45,'+5V','GND',fp='Capacitor_SMD:CP_Elec_6.3x5.4',lcsc='C2887276',pol=True)
C('C4','10uF/25V',285,45,'+5V','GND',fp=C0805,lcsc='C15850')
R('R6','10.7k',195,95,'+5V','FB',lcsc='C5153968'); R('R7','3.3k',210,95,'FB','GND',lcsc='C22978')
C('C5','33nF',180,95,'+5V','FB',lcsc='C106856')
S.part('U2','Regulator_Linear','AMS1117-3.3',250,100,{'1':'GND','2':'+3V3','3':'+5V'},value='AMS1117-3.3',fp='Package_TO_SOT_SMD:SOT-223-3_TabPin2',lcsc='C6186')
C('C6','10uF/25V',275,100,'+3V3','GND',fp=C0805,lcsc='C15850'); C('C7','10uF/25V',290,100,'+3V3','GND',fp=C0805,lcsc='C15850')
S.part('D2','Device','LED',305,60,{'1':'GND','2':'LED5_A'},value='LED 5V (red)',fp='LED_SMD:LED_0603_1608Metric',lcsc='C2286'); R('R8','1k',305,45,'+5V','LED5_A',lcsc='C21190')
S.part('D3','Device','LED',320,60,{'1':'GND','2':'LED3_A'},value='LED 3V3 (red)',fp='LED_SMD:LED_0603_1608Metric',lcsc='C2286'); R('R9','1k',320,45,'+3V3','LED3_A',lcsc='C21190')
S.flag('+12V',160,125); S.flag('+5V',175,125); S.flag('GND',205,125)
S.note('5 V: 5.30 V, up to ~0.7 A total (XL7015). 3.3 V: AMS1117, up to ~0.4 A (1 W dissipation limit).\nThese rails are separate from the XIAO 3V3 / main 5V_EXT, so sensors do not load the MCU supply.',155,132)
# ---- I2C ----
S.box(10,155,200,280,'3. I2C PORTS (400 kHz). 4x Qwiic 3.3 V + 2x XH4 with 5 V power')
S.part('JP1','Jumper','SolderJumper_2_Bridged',30,175,{'1':'+3V3','2':'I2C_PU'},value='I2C PU 2.7k (cut to remove)',fp='Jumper:SolderJumper-2_P1.3mm_Bridged_RoundedPad1.0x1.5mm')
R('R10','2.7k',50,175,'I2C_PU','SDA',lcsc='C13167'); R('R11','2.7k',65,175,'I2C_PU','SCL',lcsc='C13167')
for i,(x,y) in enumerate([(40,215),(70,215),(100,215),(130,215)]):
    S.part(f'J{2+i}','Connector_Generic','Conn_01x04',x,y,{'1':'GND','2':'+3V3','3':'SDA','4':'SCL'},value=f'I2C-{i+1} Qwiic 3V3',fp=SH4,lcsc='C160404')
for i,(x,y) in enumerate([(160,215),(185,215)]):
    S.part(f'J{6+i}','Connector_Generic','Conn_01x04',x,y,{'1':'GND','2':'+5V','3':'SDA','4':'SCL'},value=f'I2C-{5+i} XH4 5V',fp=XH4,lcsc='C144395')
S.note('Pull-ups: 2.7k here || 4.7k on main (JP3) = 1.7k, fine for 400 kHz.\nXH4 I2C ports: 5 V power, 3.3 V logic (use modules with their own regulator / level shifter).',15,265)
# ---- GPS / pulse / aux ----
S.box(210,155,400,280,'4. GPS (UART) / PULSE / AUX')
S.part('JP2','Jumper','SolderJumper_3_Bridged12',230,175,{'1':'+3V3','2':'GPS_VCC','3':'+5V'},value='GPS VCC 3V3|5V',fp='Jumper:SolderJumper-3_P1.3mm_Bridged12_RoundedPad1.0x1.5mm')
S.part('JP3','Jumper','SolderJumper_2_Open',260,175,{'1':'GPS_PPS','2':'D10'},value='PPS -> D10',fp='Jumper:SolderJumper-2_P1.3mm_Open_RoundedPad1.0x1.5mm')
S.part('J8','Connector_Generic','Conn_01x05',240,215,{'1':'GND','2':'GPS_VCC','3':'GPS_RXD','4':'GPS_TXD','5':'GPS_PPS'},value='GPS XH5 (D6 TX -> GPS RX, D7 RX <- GPS TX)',fp=XH5,lcsc='C157991')
S.part('J9','Connector_Generic','Conn_01x04',290,215,{'1':'+12V','2':'+5V','3':'GND','4':'D2'},value='PULSE-A (D2) XH4',fp=XH4,lcsc='C144395')
S.part('J10','Connector_Generic','Conn_01x04',320,215,{'1':'+12V','2':'+5V','3':'GND','4':'D3'},value='PULSE-B (D3) XH4',fp=XH4,lcsc='C144395')
S.part('J11','Connector_Generic','Conn_01x04',350,215,{'1':'+12V','2':'+5V','3':'GND','4':'D10'},value='AUX (D10) XH4',fp=XH4,lcsc='C144395')
S.note('PULSE-A/B and AUX have the same pin order as PWR-CTRL J8/J9 (1 12V, 2 5V, 3 GND, 4 IO): PULSE-IN plugs in with a straight cable.\nD2/D3 are also on main J8/J9: use only one connector per pin. D10 is shared by AUX and GPS PPS (JP3): use one of them.\nJP2 selects GPS power (default 3V3).',215,265)
for i in range(4):
    S.part(f'H{i+1}','Mechanical','MountingHole',350+i*12,30,{},value='M3',fp='MountingHole:MountingHole_3.2mm_M3',inbom=False)
S.write('/home/claude/pcb/exthub/exthub.kicad_sch')
print(len(S.parts),'parts')
