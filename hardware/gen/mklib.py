import sys,os,re,shutil
sys.path.insert(0,'/home/claude/pcb/gen')
from sexp import *
from lib import parse,find,find1,uq,q
LIB='/home/claude/pcb/lib'
# ---------- symbols ----------
def pin(t,x,y,a,name,num,L=2.54):
    return f'(pin {t} line (at {x} {y} {a}) (length {L}) (name {q(name)} (effects (font (size 1.27 1.27)))) (number {q(num)} (effects (font (size 1.27 1.27)))))'
def sym(name,ref,val,fp,desc,body,pins,extra=''):
    return f'''(symbol {q(name)} (exclude_from_sim no) (in_bom yes) (on_board yes)
 (property "Reference" {q(ref)} (at 0 0 0) (effects (font (size 1.27 1.27))))
 (property "Value" {q(val)} (at 0 -2 0) (effects (font (size 1.27 1.27))))
 (property "Footprint" {q(fp)} (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
 (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
 (property "Description" {q(desc)} (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
 (symbol {q(name+"_0_1")} {body})
 (symbol {q(name+"_1_1")} {" ".join(pins)})
 {extra})'''
syms=[]
# XIAO
P=[]
left=['D0','D1','D2','D3','D4','D5','D6']
for i,n in enumerate(left):
    P.append(pin('bidirectional',-12.7,7.62-2.54*i,0,n,str(i+1)))
right={14:('5V','power_in'),13:('GND','power_in'),12:('3V3','power_out'),11:('D10','bidirectional'),10:('D9','bidirectional'),9:('D8','bidirectional'),8:('D7','bidirectional')}
for j,num in enumerate([14,13,12,11,10,9,8]):
    n,t=right[num]; P.append(pin(t,12.7,7.62-2.54*j,180,n,str(num)))
body='(rectangle (start -10.16 10.16) (end 10.16 -10.16) (stroke (width 0.254) (type default)) (fill (type background))) (text "USB-C" (at 0 8.5 0) (effects (font (size 1 1))))'
syms.append(sym('XIAO_ESP32S3','U','XIAO ESP32S3','OpenCruise:XIAO_Socket_THT','Seeed XIAO ESP32S3 on 2x 1x7 2.54mm female sockets (rows 15.24mm)',body,P))
# XL7015
P=[pin('power_in',-12.7,2.54,0,'VIN','1'),pin('input',-12.7,-2.54,0,'EN','5'),pin('output',12.7,2.54,180,'SW','2'),pin('input',12.7,-2.54,180,'FB','4'),
   pin('power_in',0,-10.16,90,'GND','3'),pin('passive',2.54,-10.16,90,'GND','6')]
body='(rectangle (start -10.16 5.08) (end 10.16 -7.62) (stroke (width 0.254) (type default)) (fill (type background)))'
syms.append(sym('XL7015E1','U','XL7015E1','OpenCruise:TO-252-5_XL7015','XLSEMI XL7015 80V 0.8A buck, TO-252-5 (1 VIN,2 SW,3 GND,4 FB,5 EN, tab GND)',body,P))
# PESD1CAN
P=[pin('passive',-7.62,2.54,0,'CANL','1'),pin('passive',-7.62,-2.54,0,'CANH','2'),pin('passive',7.62,0,180,'GND','3')]
body='(rectangle (start -5.08 5.08) (end 5.08 -5.08) (stroke (width 0.254) (type default)) (fill (type background)))'
syms.append(sym('PESD1CAN','D','PESD1CAN','Package_TO_SOT_SMD:SOT-23','Nexperia PESD1CAN CAN bus ESD protection (1 CANL? 2 CANH? per datasheet: pins 1,2 = bus lines, 3 = GND)',body,P))
open(f'{LIB}/OpenCruise.kicad_sym','w').write('(kicad_symbol_lib (version 20241209) (generator "ocgen") (generator_version "9.0")\n'+'\n'.join(syms)+')\n')
# ---------- footprints ----------
E=f'{LIB}/easy.pretty'
ren={'DO-218AB_L13.5-W8.4-LS15.5-FD':'DO-218AB','TO-252-5_L6.6-W5.8-P1.27-TL':'TO-252-5_XL7015','IND-SMD_L8.0-W8.0_1217AS':'L_8040_SWPA8040',
     'USB-A-TH_U-USBAR04P-M002':'USB_A_Plug_U-USBAR04P-M','USB-A-TH_AF-WJDG':'USB_A_Receptacle_AF90'}
for a,b in ren.items():
    s=open(f'{E}/{a}.kicad_mod').read()
    s=re.sub(r'\(footprint "[^"]*"',f'(footprint "{b}"',s,1)
    s=re.sub(r'\(module (\S+)',f'(module {b}',s,1)
    s=s.replace('(model "easy.3dshapes','(model "${KIPRJMOD}/../lib/easy.3dshapes')
    open(f'{LIB}/OpenCruise.pretty/{b}.kicad_mod','w').write(s)
# XIAO socket footprint
pads=[]
for i in range(7):
    y=-7.62+2.54*i
    pads.append(f'(pad "{i+1}" thru_hole {"rect" if i==0 else "circle"} (at -7.62 {y:.2f}) (size 1.7 1.7) (drill 1.0) (layers "*.Cu" "*.Mask"))')
for k,num in enumerate(range(8,15)):
    y=7.62-2.54*k
    pads.append(f'(pad "{num}" thru_hole circle (at 7.62 {y:.2f}) (size 1.7 1.7) (drill 1.0) (layers "*.Cu" "*.Mask"))')
lab=['D0','D1','D2','D3','D4','D5','D6']; rl={8:'D7',9:'D8',10:'D9',11:'D10',12:'3V3',13:'GND',14:'5V'}
txt=[f'(fp_text user "{lab[i]}" (at -4.9 {-7.62+2.54*i:.2f}) (layer "F.SilkS") (effects (font (size 1.0 1.0) (thickness 0.15))))' for i in range(7)]
txt+=[f'(fp_text user "{rl[n]}" (at 4.9 {7.62-2.54*(n-8):.2f}) (layer "F.SilkS") (effects (font (size 1.0 1.0) (thickness 0.15))))' for n in range(8,15)]
fp=f'''(footprint "XIAO_Socket_THT" (version 20241229) (generator "ocgen") (layer "F.Cu")
 (descr "Seeed XIAO (21x17.8mm) socketed on 2x 1x7 2.54mm female headers, rows 15.24mm apart, hole 1.0mm (Seeed XIAO Package and PCB Design). USB-C toward -Y.")
 (attr through_hole)
 (property "Reference" "REF**" (at 0 -13.2 0) (layer "F.SilkS") (effects (font (size 1 1) (thickness 0.15))))
 (property "Value" "XIAO_ESP32S3" (at 0 12.2 0) (layer "F.Fab") (effects (font (size 1 1) (thickness 0.15))))
 (fp_rect (start -8.9 -10.5) (end 8.9 10.5) (stroke (width 0.15) (type solid)) (fill none) (layer "F.SilkS"))
 (fp_rect (start -4.5 -12) (end 4.5 -10.5) (stroke (width 0.15) (type solid)) (fill none) (layer "F.SilkS"))
 (fp_text user "USB-C" (at 0 -9.3 0) (layer "F.SilkS") (effects (font (size 1.0 1.0) (thickness 0.15))))
 (fp_line (start -9.6 -10.1) (end -9.6 -8.7) (stroke (width 0.2) (type solid)) (layer "F.SilkS"))
 (fp_rect (start -9.2 -12.5) (end 9.2 11) (stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd"))
 (fp_rect (start -8.9 -10.5) (end 8.9 10.5) (stroke (width 0.1) (type solid)) (fill none) (layer "F.Fab"))
 {" ".join(txt)}
 {" ".join(pads)})'''
open(f'{LIB}/OpenCruise.pretty/XIAO_Socket_THT.kicad_mod','w').write(fp)
print('ok')

# ---- fix courtyards of EasyEDA footprints: rectangle = bbox(pads+graphics)+0.25mm, remove silk on pads circles
import pcbnew
lp=f'{LIB}/OpenCruise.pretty'
for nm in ['DO-218AB','L_8040_SWPA8040','TO-252-5_XL7015','USB_A_Plug_U-USBAR04P-M','USB_A_Receptacle_AF90']:
    fp=pcbnew.FootprintLoad(lp,nm)
    bb=None
    for p in list(fp.Pads()):
        b_=p.GetBoundingBox()
        if bb is None: bb=pcbnew.BOX2I(b_.GetPosition(),b_.GetSize())
        else: bb.Merge(b_)
    rem=[]
    for it in list(fp.GraphicalItems()):
        if it.GetLayer() in (pcbnew.F_CrtYd,pcbnew.B_CrtYd): rem.append(it)
        elif nm=='L_8040_SWPA8040' and it.GetLayer()==pcbnew.F_SilkS and it.GetClass()=='PCB_SHAPE' and it.GetShape()==pcbnew.SHAPE_T_CIRCLE: rem.append(it)
        elif it.GetLayer() in (pcbnew.F_SilkS,pcbnew.F_Fab) and it.GetClass()=='PCB_SHAPE': bb.Merge(it.GetBoundingBox())
    m=0.25
    x0,y0,x1,y1=[pcbnew.ToMM(v) for v in (bb.GetX(),bb.GetY(),bb.GetRight(),bb.GetBottom())]
    txt=open(f'{lp}/{nm}.kicad_mod').read().splitlines()
    out=[l for l in txt if 'CrtYd' not in l and not (nm=='L_8040_SWPA8040' and 'fp_circle' in l and 'F.SilkS' in l)]
    # insert before final ')'
    k=max(i for i,l in enumerate(out) if l.strip()==')')
    out.insert(k,f'\t(fp_rect (start {x0-m:.3f} {y0-m:.3f}) (end {x1+m:.3f} {y1+m:.3f}) (stroke (width 0.05) (type solid)) (fill no) (layer "F.CrtYd"))')
    open(f'{lp}/{nm}.kicad_mod','w').write('\n'.join(out)+'\n')
print('courtyards fixed')
