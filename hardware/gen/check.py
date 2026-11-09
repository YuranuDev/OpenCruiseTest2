import sys,json,subprocess,collections; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew
def check(pcb,margin=0.3,allow_edge=(),smd_margin=1.0):
    subprocess.run(['kicad-cli','pcb','drc','--severity-all','--format','json','-o','/tmp/claude-0/drc.json',pcb],capture_output=True)
    d=json.load(open('/tmp/claude-0/drc.json'))
    cnt=collections.Counter(v['type'] for v in d['violations'])
    b=pcbnew.LoadBoard(pcb); bb=b.GetBoardEdgesBoundingBox()
    X0,Y0,X1,Y1=[pcbnew.ToMM(v) for v in (bb.GetX(),bb.GetY(),bb.GetRight(),bb.GetBottom())]
    out=[]
    for fp in b.GetFootprints():
        cy=fp.GetCourtyard(pcbnew.F_CrtYd)
        if cy.OutlineCount()==0: out.append((fp.GetReference(),'NO COURTYARD')); continue
        r=cy.BBox(); x0,y0,x1,y1=[pcbnew.ToMM(v) for v in (r.GetX(),r.GetY(),r.GetRight(),r.GetBottom())]
        ref=fp.GetReference(); conn=ref.startswith(('J','H'))
        m=0 if ref in allow_edge else (margin if conn else smd_margin)
        if x0<X0+m-1e-3 or y0<Y0+m-1e-3 or x1>X1-m+1e-3 or y1>Y1-m+1e-3:
            out.append((fp.GetReference(),f'courtyard outside board: ({x0:.1f},{y0:.1f})-({x1:.1f},{y1:.1f})'))
    # silk line width / text size audit (JLC: line>=0.15, text h>=1.0)
    for fp in b.GetFootprints():
        for it in fp.GraphicalItems():
            if it.GetLayer()==pcbnew.F_SilkS and it.GetClass()=='PCB_SHAPE' and 0<it.GetWidth()<pcbnew.FromMM(0.149): out.append((fp.GetReference(),'silk line < 0.15'))
        for f in [fp.Reference()]+[t for t in fp.GraphicalItems() if t.GetClass()=='PCB_TEXT']:
            if f.IsVisible() and f.GetLayer()==pcbnew.F_SilkS and (f.GetTextHeight()<pcbnew.FromMM(0.999) or f.GetTextThickness()<pcbnew.FromMM(0.149)): out.append((fp.GetReference(),'silk text too small'))
    return cnt,d['violations'],out
if __name__=='__main__':
    cnt,v,out=check(sys.argv[1],allow_edge=sys.argv[2].split(',') if len(sys.argv)>2 else ())
    print(dict(cnt))
    for x in v:
        if True:
            print(' ',x['type'],'|',' / '.join(i['description'] for i in x['items']))
    for o in out: print(' CHECK',o)
