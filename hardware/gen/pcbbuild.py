import sys,os,math
sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
from sexp import parse,find,find1,uq
SYS='/usr/share/kicad/footprints'; OC='/home/claude/pcb/lib/OpenCruise.pretty'
def libpath(lib): return OC if lib=='OpenCruise' else f'{SYS}/{lib}.pretty'
def read_net(path):
    N=parse(open(path).read())[0]
    comps={}
    for c in find(find1(N,'components'),'comp'):
        ref=uq(find1(c,'ref')[1]); fp=uq(find1(c,'footprint')[1]) if find1(c,'footprint') else ''
        val=uq(find1(c,'value')[1])
        props={uq(find1(p,'name')[1]):(uq(find1(p,'value')[1]) if find1(p,'value') else '') for p in find(c,'property')}
        comps[ref]=dict(fp=fp,val=val,props=props,pads={})
    for n in find(find1(N,'nets'),'net'):
        name=uq(find1(n,'name')[1]).lstrip('/')
        for x in find(n,'node'):
            comps[uq(find1(x,'ref')[1])]['pads'][uq(find1(x,'pin')[1])]=name
    return comps
SMALL=('0402','0603','0805','1206','1210','1812','SOD-123','SOT-23','SolderJumper','TestPoint','D_SMA','R_2512','LED_')
def build(netfile,out,W,H,place,holes=(),radius=2.0,title='',hide_refs=(),ref_pos={}):
    comps=read_net(netfile)
    b=pcbnew.BOARD()
    ds=b.GetDesignSettings()
    nets={}
    def net(n):
        if n not in nets:
            ni=pcbnew.NETINFO_ITEM(b,n); b.Add(ni); nets[n]=ni
        return nets[n]
    missing=[r for r in comps if r not in place]
    for ref,c in comps.items():
        lib,name=c['fp'].split(':')
        fp=pcbnew.FootprintLoad(libpath(lib),name)
        assert fp, c['fp']
        fp.SetReference(ref); fp.SetValue(c['val'])
        for k,v in c['props'].items():
            if k in ('LCSC','MPN','Assembly'):
                fp.SetField(k,v)
                f=fp.GetFieldByName(k); f.SetVisible(False); f.SetLayer(pcbnew.F_Fab)
        x,y,rot,side=(place.get(ref)+(0,'F'))[:4] if len(place.get(ref,()))<4 else place[ref]
        b.Add(fp)
        if side=='B': fp.Flip(fp.GetPosition(),False)
        fp.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(x),pcbnew.FromMM(y)))
        fp.SetOrientationDegrees(rot)
        if 'dnp' in c['props']: fp.SetDNP(True)
        for p in fp.Pads():
            n=c['pads'].get(p.GetNumber())
            if n: p.SetNet(net(n))
        # silkscreen reference policy: small parts -> hidden, large parts -> shown (1.0 mm)
        small=any(k in name for k in SMALL) or ref.startswith(('H','TP'))
        rf=fp.Reference()
        rf.SetVisible(not small and ref not in hide_refs)
        rf.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(1.0),pcbnew.FromMM(1.0))); rf.SetTextThickness(pcbnew.FromMM(0.15))
        if ref in ref_pos:
            dx,dy,ang=ref_pos[ref]; rf.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(x+dx),pcbnew.FromMM(y+dy))); rf.SetTextAngleDegrees(ang)
        fp.Value().SetVisible(False)
    # outline
    def seg(x1,y1,x2,y2):
        s=pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_SEGMENT); s.SetLayer(pcbnew.Edge_Cuts)
        s.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(x1),pcbnew.FromMM(y1))); s.SetEnd(pcbnew.VECTOR2I(pcbnew.FromMM(x2),pcbnew.FromMM(y2))); s.SetWidth(pcbnew.FromMM(0.1)); b.Add(s)
    def arc(cx,cy,sx,sy,ang):
        s=pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_ARC); s.SetLayer(pcbnew.Edge_Cuts)
        s.SetCenter(pcbnew.VECTOR2I(pcbnew.FromMM(cx),pcbnew.FromMM(cy))); s.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(sx),pcbnew.FromMM(sy)))
        s.SetArcAngleAndEnd(pcbnew.EDA_ANGLE(ang,pcbnew.DEGREES_T),True); s.SetWidth(pcbnew.FromMM(0.1)); b.Add(s)
    # JLC 2-layer/2oz board settings
    ds.SetCopperLayerCount(2)
    ds.m_SolderMaskMinWidth=pcbnew.FromMM(0.2)      # 2oz mask dam
    ds.m_SolderMaskExpansion=0                     # JLC LDI 1:1
    ds.m_CopperEdgeClearance=pcbnew.FromMM(0.3)
    ds.m_MinClearance=pcbnew.FromMM(0.2); ds.m_TrackMinWidth=pcbnew.FromMM(0.2)
    ds.m_ViasMinSize=pcbnew.FromMM(0.85); ds.m_MinThroughDrill=pcbnew.FromMM(0.3); ds.m_ViasMinAnnularWidth=pcbnew.FromMM(0.254)
    ds.m_HoleToHoleMin=pcbnew.FromMM(0.5); ds.m_HoleClearance=pcbnew.FromMM(0.3)
    ds.m_SilkClearance=pcbnew.FromMM(0.15)
    # silkscreen graphics: JLC min line width 0.15 mm
    for fp in b.GetFootprints():
        for it in fp.GraphicalItems():
            if it.GetLayer() in (pcbnew.F_SilkS,pcbnew.B_SilkS):
                if it.GetClass()=='PCB_SHAPE' and 0<it.GetWidth()<pcbnew.FromMM(0.15): it.SetWidth(pcbnew.FromMM(0.15))
                if it.GetClass() in ('PCB_TEXT',) :
                    if it.GetTextHeight()<pcbnew.FromMM(1.0): it.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(1.0),pcbnew.FromMM(1.0)))
                    if it.GetTextThickness()<pcbnew.FromMM(0.15): it.SetTextThickness(pcbnew.FromMM(0.15))
    r=radius
    seg(r,0,W-r,0); seg(W,r,W,H-r); seg(W-r,H,r,H); seg(0,H-r,0,r)
    arc(W-r,r,W-r,0,90); arc(W-r,H-r,W,H-r,90); arc(r,H-r,r,H,90); arc(r,r,0,r,90)
    pcbnew.SaveBoard(out,b)
    return b,comps,missing
