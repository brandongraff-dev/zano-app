"""Shared expression kit. Each buddy passes its own eye style, colours and anchor points, so the
faces read as one family without being copies."""
from engine import hx
EXPRS=['drained','sad','meh','content','happy','excited','ecstatic','sleepy']
INKC='#1A1633'; MOUTH_IN='#7A2240'; TONGUE='#FF7A93'; TEAR='#7FD3FF'; WHITE='#FFFFFF'

def oval(w,h):
    pts=[]
    for j in range(h):
        for i in range(w):
            if ((i+.5-w/2)/(w/2))**2+((j+.5-h/2)/(h/2))**2<=1.08: pts.append((i,j))
    return pts

def eye(s,x,y,w,h,expr,iris,side,skin,lid=INKC,rim=None):
    """x,y = top-left of the eye box; side = -1 left eye, +1 right eye; skin = (ramp, part).
    rim: a 1px light ring around open eyes (for eyes on dark fur, like Stash's mask)."""
    O=oval(w,h)
    if rim and expr not in ('ecstatic','sleepy','drained'):
        for (i,j) in oval(w+2,h+2): s.F(x-1+i,y-1+j,rim)
    if expr=='ecstatic':           # ^ ^, 2px thick
        for i in range(w):
            d=abs(i-(w-1)/2)
            yy=y+round(d*1.0)+1
            s.F(x+i,yy,lid); s.F(x+i,yy+1,lid)
        return
    if expr=='sleepy':             # closed, curved down
        for i in range(w):
            d=abs(i-(w-1)/2); yy=y+h-3+ (0 if d<w/2-1 else -1)
            s.F(x+i,yy,lid)
        return
    if expr=='drained':            # > <  squeezed
        for j in range(h):
            k=abs(j-(h-1)/2); off=round((w-1)*(k/((h-1)/2)))
            xx=x+off if side<0 else x+w-1-off
            s.F(xx,y+j,lid)
            s.F(xx+(1 if side<0 else -1),y+j,lid)
        tears(s,x+w//2,y+h+1,4)
        return
    for (i,j) in O:
        c=iris if (iris and j>=h*0.55) else INKC
        s.F(x+i,y+j,c)
    if expr=='excited':            # sparkle eyes: a white 4-point star
        cx,cy=x+w//2,y+h//2
        for dx,dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1),(0,-2),(0,2),(2,0),(-2,0)]:
            s.F(cx+dx,cy+dy,WHITE)
        return
    # highlights
    s.F(x+1,y+1,WHITE); s.F(x+2,y+1,WHITE); s.F(x+1,y+2,WHITE)
    if w>=5: s.F(x+2,y+2,WHITE)
    s.F(x+w-2,y+h-2,'#D9E2FF')
    if expr=='sad':                # extra wet shine and a tear at the outer corner
        s.F(x+w-2,y+2,WHITE); s.F(x+w-3,y+h-2,'#D9E2FF')
        tx=x if side<0 else x+w-1
        s.F(tx,y+h,TEAR,'~t'); s.F(tx,y+h+1,TEAR,'~t'); s.F(tx-side*0,y+h+2,'#BFEAFF','~t')
    if expr=='happy':              # smiling lower lid
        r,p=skin
        for i in range(1,w-1): s.put(x+i,y+h-1,r,p)
    if expr=='meh':                # heavy lid: top half becomes skin, lid line
        r,p=skin
        for (i,j) in O:
            if j<h//2: s.put(x+i,y+j,r,p)
        for i in range(w): s.F(x+i,y+h//2,lid)
        s.F(x+1,y+h//2+1,WHITE)

def eyes(s,lx,rx,y,w,h,expr,iris,skin,lid=INKC,rim=None):
    eye(s,lx,y,w,h,expr,iris,-1,skin,lid,rim); eye(s,rx,y,w,h,expr,iris,1,skin,lid,rim)

def brows(s,lx,rx,y,w,expr,col):
    """Worried brows (sad/drained), flat low brows (meh), raised (excited/ecstatic)."""
    if expr in ('sad','drained'):
        for i in range(w-1):
            s.F(lx+i, y+1-(i*2)//(w-1), col); s.F(rx+w-2-i, y+1-(i*2)//(w-1), col)
    elif expr=='meh':
        for i in range(w-1): s.F(lx+1+i,y+1,col); s.F(rx+i,y+1,col)
    elif expr in ('excited',):
        for i in range(1,w-1): s.F(lx+i,y-1,col); s.F(rx+i,y-1,col)

MOUTHS={
 'drained':["..KKK..",".K...K.","K.....K"],
 'sad':    [".KKK.","K...K"],
 'meh':    ["KKKK"],
 'content':["K...K",".KKK."],
 'happy':  ["KKKKK","KRRRK",".KTK."],
 'excited':["KKKKKKK","KRRRRRK","KRTTTRK",".KTTTK.","..KKK.."],
 'ecstatic':["KKKKKKKKK","KRRRRRRRK","KRRTTTRRK",".KRTTTRK.","..KKKKK.."],
 'sleepy': ["KK"],
}
CAT={'content':["K.K.K",".K.K."]}

def mouth(s,cx,y,expr,style='smile'):
    rows=(CAT.get(expr) if style=='cat' else None) or MOUTHS[expr]
    w=len(rows[0]); x=cx-w//2 + (1 if expr=='meh' else 0)
    s.rowsF(x,y,rows,{'K':INKC,'R':MOUTH_IN,'T':TONGUE})

def blush(s,lx,rx,y,expr,col='#FF8FAB'):
    if expr in ('drained','sad','meh'): return
    w=4 if expr in ('happy','excited','ecstatic') else 3
    for i in range(w):
        s.F(lx+i,y,col,'_bl'); s.F(rx+i-(w-3),y,col,'_bl')
    if expr=='ecstatic':
        for i in range(w): s.F(lx+i,y+1,col,'_bl'); s.F(rx+i-(w-3),y+1,col,'_bl')

def spark(s,x,y,col='#FFD447'):
    for dx,dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1)]: s.F(x+dx,y+dy,col,'~sp')
    s.F(x,y,WHITE,'~sp')
def heart(s,x,y,col='#FF6F91'):
    s.rowsF(x,y,[".K.K.","KKKKK","KKKKK",".KKK.","..K.."],{'K':col})
    s.F(x+1,y+1,'#FFC2D1','~h')
def tears(s,x,y,n):
    for j in range(n): s.F(x,y+j,TEAR,'~t')
def drop(s,x,y):
    s.rowsF(x,y,[".D.","DDD","DWD",".D."],{'D':TEAR,'W':WHITE})
def cloud(s,x,y):
    s.rowsF(x,y,["..GGG...",".GGGGGG.","GGGGGGGG",".GGGGGG."],{'G':'#6B7290'})
    for i in (1,4,7): s.F(x+i-1,y+5,TEAR); s.F(x+i-2,y+6,TEAR)
def bubble(s,x,y):
    s.rowsF(x,y,[".BB.","B.WB","B..B",".BB."],{'B':'#9FDFFF','W':WHITE})

def extras(s,expr,top_right=(40,4),top_left=(3,4),cheek=(36,20)):
    if expr=='drained':
        s.desat=0.4; cloud(s,*top_left); drop(s,*top_right)
    elif expr=='meh':
        drop(s,*top_right)
    elif expr=='excited':
        spark(s,top_right[0]+2,top_right[1]+2); spark(s,top_left[0]+2,top_left[1]+6)
    elif expr=='ecstatic':
        heart(s,top_right[0]-1,top_right[1]); heart(s,top_left[0],top_left[1]+4,'#FFB3C7')
        spark(s,top_right[0]+4,top_right[1]+10)
    elif expr=='sleepy':
        bubble(s,*cheek)

def arms_pose(expr):
    return {'ecstatic':'up','excited':'wave','drained':'droop','sad':'droop'}.get(expr,'down')
def ears_droop(expr): return expr in ('drained','sad')
