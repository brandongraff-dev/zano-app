"""Shared expression kit. Each buddy passes its own eye style, colours and anchor points, so the
faces read as one family without being copies."""
from engine import hx
EXPRS=['drained','sad','meh','content','happy','excited','ecstatic','sleepy']
# Activity emotions (session 15): what the buddy feels while you work out, drink, eat, focus.
# All additive and positive; hunger/thirst read as "ready for it", never guilt.
ACTIVITY=['lifting','flexing','sipping','thirsty','eating','hungry','focused','yawning','proud','lovey']
# Page companions (session 29): the streak's fire eyes and ice eyes, and one face per tab.
PAGE=['blaze','frozen','guarding','tinkering','analyzing']
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
    if expr in ('sipping','eating','proud'):   # blissful closed eyes: one thin ^
        for i in range(w):
            d=abs(i-(w-1)/2); s.F(x+i,y+2+round(d*0.9),lid)
        return
    if expr=='lovey':                           # heart eyes
        hx0=x+(w-5)//2
        s.rowsF(hx0,y,["KK.KK","KKKKK","KKKKK",".KKK.","..K.."],{'K':'#FF4F7B'})
        s.F(hx0+1,y+1,'#FFC2D1','~h'); return
    if expr=='blaze':                           # glowing ember eyes: warm orange over gold, a bright sparkle
        for (i,j) in O:
            s.F(x+i,y+j,'#FFD447' if j>=h*0.5 else '#FF8A2E')
        s.F(x+1,y+1,WHITE); s.F(x+2,y+1,WHITE); s.F(x+1,y+2,WHITE)
        s.F(x+w-2,y+h-2,'#FFF1B8'); return
    if expr=='frozen':                          # ice eyes: pale crystal with a small dark pupil
        for (i,j) in O: s.F(x+i,y+j,'#CFF3FF')
        cx=x+w//2; cy=y+h//2
        for dx in (0,1):
            for dy in (-1,0,1): s.F(cx-1+dx,cy+dy,INKC)
        s.F(x+1,y+1,WHITE); s.F(x+2,y+1,WHITE); return
    if rim and expr not in ('ecstatic','sleepy','drained','yawning'):
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
    if expr in ('drained','yawning'):  # > <  squeezed
        for j in range(h):
            k=abs(j-(h-1)/2); off=round((w-1)*(k/((h-1)/2)))
            xx=x+off if side<0 else x+w-1-off
            s.F(xx,y+j,lid)
            s.F(xx+(1 if side<0 else -1),y+j,lid)
        if expr=='drained': tears(s,x+w//2,y+h+1,4)
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
    if expr=='hungry':             # big wet eyes, no tear
        s.F(x+w-2,y+2,WHITE); s.F(x+w-3,y+h-2,'#D9E2FF')
    if expr=='sad':                # extra wet shine and a tear at the outer corner
        s.F(x+w-2,y+2,WHITE); s.F(x+w-3,y+h-2,'#D9E2FF')
        tx=x if side<0 else x+w-1
        s.F(tx,y+h,TEAR,'~t'); s.F(tx,y+h+1,TEAR,'~t'); s.F(tx-side*0,y+h+2,'#BFEAFF','~t')
    if expr in ('happy','flexing'):  # smiling lower lid
        r,p=skin
        for i in range(1,w-1): s.put(x+i,y+h-1,r,p)
    if expr in ('meh','thirsty','focused','guarding'):  # heavy lid: top half becomes skin, lid line
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
    elif expr in ('lifting','focused','guarding'):    # angry-V: determined, never mean (no mouth to match)
        for i in range(w-1):
            s.F(lx+i, y-1+(i*2)//(w-1), col); s.F(rx+w-2-i, y-1+(i*2)//(w-1), col)
    elif expr in ('hungry','frozen'):
        for i in range(w-1):
            s.F(lx+i, y+1-(i*2)//(w-1), col); s.F(rx+w-2-i, y+1-(i*2)//(w-1), col)
    elif expr in ('excited','flexing','proud','blaze'):
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
 'lifting':["KKKKKK","KWWWWK","KKKKKK"],
 'flexing':["KKKKK","KRRRK",".KKK."],
 'sipping':[".KK.","KRRK",".KK."],
 'thirsty':["KKKKK","K...K",".KTK.","..T.."],
 'eating': ["KKKKKK","KRRRRK","KRTTRK",".KKKK."],
 'hungry': ["K...K",".KKK."],
 'focused':["KKKK"],
 'yawning':[".KKK.","KRRRK","KRTRK","KRRRK",".KKK."],
 'proud':  ["K...K",".KKK."],
 'lovey':  ["KKKKK","KRRRK",".KTK."],
 'blaze':  ["KKKKK","KRRRK","KRTRK",".KKK."],
 'frozen': ["KKKKK","KWKWK","KKKKK"],
 'guarding':["KKKK"],
 'tinkering':["K...K",".KKK."],
 'analyzing':["K...K",".KKK."],
}
CAT={'content':["K.K.K",".K.K."]}

def mouth(s,cx,y,expr,style='smile'):
    rows=(CAT.get(expr) if style=='cat' else None) or MOUTHS[expr]
    w=len(rows[0]); x=cx-w//2 + (1 if expr=='meh' else 0)
    s.rowsF(x,y,rows,{'K':INKC,'R':MOUTH_IN,'T':TONGUE,'W':WHITE})

def blush(s,lx,rx,y,expr,col='#FF8FAB'):
    if expr in ('drained','sad','meh','thirsty','hungry','focused','guarding'): return
    w=4 if expr in ('happy','excited','ecstatic','flexing','proud','lovey','eating','sipping','blaze') else 3
    for i in range(w):
        s.F(lx+i,y,col,'_bl'); s.F(rx+i-(w-3),y,col,'_bl')
    if expr in ('ecstatic','lovey'):
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

# ---- activity props: small floating stickers (no outline), placed in free space around the buddy
PROPS={
 'dumbbell':([".PP........PP.","PPPP......PPPP","PPPBBBBBBBBPPP","PPPBBBBBBBBPPP","PPPP......PPPP",".PP........PP."],{'P':'#6A74A0','B':'#D5DBEE'}),
 'bottle':(["..CC..",".CCCC.","BBBBBB","BWWWWB","BAAAAB","BAAAAB","BAAAAB","BBBBBB"],{'C':'#3F7BFF','B':'#9FDFFF','W':'#EAF8FF','A':'#35A8F2'}),
 'bottleEmpty':(["..CC..",".CCCC.","BBBBBB","BWWWWB","BWWWWB","BWWWWB","BWAAWB","BBBBBB"],{'C':'#3F7BFF','B':'#9FDFFF','W':'#EAF8FF','A':'#BFE8FF'}),
 'drumstick':(["..MMMM...",".MHHMMM..","MMHMMMM..","MMMMMMM..",".MMMMM.B.","...BB.BBB","....BBBBB",".....BB.."],{'M':'#C4691F','H':'#F2A24A','B':'#F4EEDD'}),
 'egg':(["..WWWW..",".WWWWWW.","WWWYYWWW","WWYYYYWW","WWYYYYWW",".WWYYWW.","..WWWW.."],{'W':'#FFF8E8','Y':'#FFC83D'}),
 'target':([".RRRRR.","RRWWWRR","RWWRWWR","RWRRRWR","RWWRWWR","RRWWWRR",".RRRRR."],{'R':'#E5484D','W':'#F7F8FF'}),
 'medal':(["...Y...","..YYY..","YYYYYYY",".YYWYY.",".YYYYY.",".YY.YY.","YY...YY"],{'Y':'#FFC94A','W':'#FFF1B8'}),
 'zzz':(["ZZZZ","..Z.",".Z..","ZZZZ"],{'Z':'#9FB0FF'}),
 'drop':([".D.","DDD","DWD",".D."],{'D':'#7FD3FF','W':'#FFFFFF'}),
 'sweat':([".D.",".D.","DDD",".D."],{'D':'#7FD3FF'}),
 'spark':([".Y.","YWY",".Y."],{'Y':'#FFD447','W':'#FFFFFF'}),
 'flame':(["..R..",".RO..",".ROR.","ROYOR","ROYYR",".ROR."],{'R':'#FF4D2E','O':'#FF9A2E','Y':'#FFE066'}),
 'snow':(["..S..","S.S.S",".SSS.","S.S.S","..S.."],{'S':'#BFEFFF'}),
 'padlock':(["..GGGG..",".GG..GG.",".G....G.","YYYYYYYY","YYYKKYYY","YYYKKYYY","YYYYYYYY"],{'G':'#C9D2F0','Y':'#FFC94A','K':'#7A5A10'}),
 'hammer':(["SSSSSS","SSSSSS","SSSSSS","..WW..","..WW..","..WW..","..WW..","..WW.."],{'S':'#B7C0DE','W':'#C4691F'}),
 'chart':(["......CC","......CC","...BB.CC","...BB.CC","AA.BB.CC","AA.BB.CC","WWWWWWWW"],{'A':'#7FD3FF','B':'#6AF0B0','C':'#FFD447','W':'#D5DBEE'}),
}
def place(s,name,prefer='tr',margin=1):
    """Draw a prop in the free space nearest `prefer` (tr, tl, br, bl): the nine buddies are all
    different shapes, so a fixed coordinate would sit on some and float away from others."""
    rows,key=PROPS[name]; h=len(rows); w=len(rows[0])
    ty={'t':0,'b':48-h}[prefer[0]]; tx={'l':0,'r':48-w}[prefer[1]]
    cands=sorted(((x,y) for x in range(0,48-w+1) for y in range(0,48-h+1)),
                 key=lambda c:(c[0]-tx)**2+(c[1]-ty)**2)
    def free(x,y,m):
        for yy in range(y-m,y+h+m):
            for xx in range(x-m,x+w+m):
                if (xx,yy) in s.px: return False
        return True
    spot=None
    for m in (margin,0):
        spot=next(((x,y) for x,y in cands if free(x,y,m)),None)
        if spot: break
    x0,y0=spot or cands[0]
    for j,row in enumerate(rows):
        for i,ch in enumerate(row):
            if ch in key: s.F(x0+i,y0+j,key[ch],'~prop')


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
    elif expr=='lifting':
        place(s,'dumbbell','tr'); place(s,'sweat','tl')
    elif expr=='flexing':
        place(s,'spark','tr'); place(s,'spark','tl'); place(s,'sweat','br')
    elif expr=='sipping':
        place(s,'bottle','tr'); place(s,'spark','tl')
    elif expr=='thirsty':
        place(s,'bottleEmpty','tr'); place(s,'sweat','tl')
    elif expr=='eating':
        place(s,'drumstick','tr'); place(s,'spark','tl')
    elif expr=='hungry':
        place(s,'egg','tr'); s.F(cheek[0],cheek[1],TEAR,'~t'); s.F(cheek[0],cheek[1]+1,TEAR,'~t'); s.F(cheek[0],cheek[1]+2,'#BFEAFF','~t')
    elif expr=='focused':
        place(s,'target','tr')
    elif expr=='yawning':
        place(s,'zzz','tr')
    elif expr=='proud':
        place(s,'medal','tr'); place(s,'spark','tl')
    elif expr=='lovey':
        heart(s,top_right[0]-1,top_right[1]); heart(s,top_left[0],top_left[1]+4,'#FFB3C7')
    elif expr=='blaze':
        place(s,'flame','tr'); place(s,'spark','tl')
    elif expr=='frozen':
        place(s,'snow','tr'); place(s,'snow','tl')
    elif expr=='guarding':
        place(s,'padlock','tr')
    elif expr=='tinkering':
        place(s,'hammer','tr'); place(s,'spark','tl')
    elif expr=='analyzing':
        place(s,'chart','tr')

def arms_pose(expr):
    return {'ecstatic':'up','excited':'wave','drained':'droop','sad':'droop',
            'lifting':'up','yawning':'up','flexing':'wave','sipping':'wave','proud':'wave',
            'blaze':'up','tinkering':'wave'}.get(expr,'down')
def ears_droop(expr): return expr in ('drained','sad')
