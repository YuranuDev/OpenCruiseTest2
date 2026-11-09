import sys,math; sys.path.insert(0,'/home/claude/pcb/gen')
import pcbnew, matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle,Circle,Polygon
PWR={'VBAT_IN':'#d62728','VSW':'#d62728','GND':'#555555','+5V':'#ff7f0e','VIN5':'#ff7f0e','V5REG':'#ff7f0e','SW5':'#ff7f0e','+3V3':'#bcbd22','ACC_IN':'#9467bd'}
def mm(v): return pcbnew.ToMM(v)
def render(pcbfile,png,groups=(),title='',ratsnest=True,dpi=110):
    b=pcbnew.LoadBoard(pcbfile)
    bb=b.GetBoardEdgesBoundingBox(); W=mm(bb.GetWidth()); H=mm(bb.GetHeight())
    fig,ax=plt.subplots(figsize=(W/7+2,H/7+1.5))
    for d in b.GetDrawings():
        if d.GetLayer()==pcbnew.Edge_Cuts:
            if d.GetShape()==pcbnew.SHAPE_T_SEGMENT:
                ax.plot([mm(d.GetStart().x),mm(d.GetEnd().x)],[mm(d.GetStart().y),mm(d.GetEnd().y)],'k-',lw=1.5)
            else:
                c=d.GetCenter(); r=mm(d.GetRadius()); a0=math.degrees(math.atan2(d.GetStart().y-c.y,d.GetStart().x-c.x))
                t=[a0+i*90/20 for i in range(21)]
                ax.plot([mm(c.x)+r*math.cos(math.radians(x)) for x in t],[mm(c.y)+r*math.sin(math.radians(x)) for x in t],'k-',lw=1.5)
    for (x1,y1,x2,y2,name,col) in groups:
        ax.add_patch(Rectangle((x1,y1),x2-x1,y2-y1,fill=True,alpha=0.08,color=col)); ax.text(x1+0.5,y1+1.5,name,fontsize=6,color=col,weight='bold')
    padpos={}
    for fp in b.GetFootprints():
        dnp=fp.IsDNP() if hasattr(fp,'IsDNP') else False
        cy=fp.GetCourtyard(pcbnew.F_CrtYd) if fp.GetLayer()==pcbnew.F_Cu else fp.GetCourtyard(pcbnew.B_CrtYd)
        bbx=fp.GetBoundingBox(False)
        try:
            if cy.OutlineCount():
                pts=[(mm(cy.COutline(0).CPoint(i).x),mm(cy.COutline(0).CPoint(i).y)) for i in range(cy.COutline(0).PointCount())]
                ax.add_patch(Polygon(pts,closed=True,fill=False,ec='#1f77b4',lw=0.6))
            else: raise Exception
        except Exception:
            ax.add_patch(Rectangle((mm(bbx.GetX()),mm(bbx.GetY())),mm(bbx.GetWidth()),mm(bbx.GetHeight()),fill=False,ec='#1f77b4',lw=0.6))
        for p in fp.Pads():
            pp=p.GetPosition(); s=p.GetBoundingBox()
            col='#c8a000' if p.GetAttribute()==pcbnew.PAD_ATTRIB_PTH else '#d4a017'
            ax.add_patch(Rectangle((mm(s.GetX()),mm(s.GetY())),mm(s.GetWidth()),mm(s.GetHeight()),color=col,alpha=0.7,lw=0))
            n=p.GetNetname()
            if n: padpos.setdefault(n,[]).append((mm(pp.x),mm(pp.y)))
        c=fp.GetPosition(); ref=fp.GetReference()
        ax.text(mm(bbx.GetCenter().x),mm(bbx.GetCenter().y),ref,fontsize=5.5 if len(fp.Pads())>3 else 4.5,ha='center',va='center',color='red' if 'DNP' in fp.GetValue() else 'navy',weight='bold')
    if ratsnest:
        for n,pts in padpos.items():
            if n=='GND' or len(pts)<2: continue
            # MST prim
            done=[pts[0]]; rest=pts[1:]
            col=PWR.get(n,'#2ca02c'); lw=1.2 if n in PWR else 0.4
            while rest:
                best=min(((math.dist(a,b_),a,b_) for a in done for b_ in rest))
                _,a,b_=best; ax.plot([a[0],b_[0]],[a[1],b_[1]],'-',color=col,lw=lw,alpha=0.6); done.append(b_); rest.remove(b_)
    ax.set_xlim(-3,W+3); ax.set_ylim(H+3,-3); ax.set_aspect('equal'); ax.set_title(title,fontsize=9)
    ax.set_xticks(range(0,int(W)+1,10)); ax.set_yticks(range(0,int(H)+1,10)); ax.grid(alpha=0.2); ax.tick_params(labelsize=6)
    fig.tight_layout(); fig.savefig(png,dpi=dpi); plt.close(fig)
