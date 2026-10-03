import colorsys
N=32
INK=(11,14,36)
def hx(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))
def tohex(c): return '#%02X%02X%02X'%c
def shift(c,dl,dh,ds=0):
    r,g,b=[v/255 for v in c]; h,l,s=colorsys.rgb_to_hls(r,g,b)
    h=(h+dh)%1; l=min(1,max(0,l+dl)); s=min(1,max(0,s+ds))
    return tuple(round(v*255) for v in colorsys.hls_to_rgb(h,l,s))
def ramp(base):
    c=hx(base)
    # hue shift: highlights toward warm, shadows toward cool/purple
    def toward(c,target,amt):
        r,g,b=[v/255 for v in c]; h,l,s=colorsys.rgb_to_hls(r,g,b)
        d=((target-h+0.5)%1)-0.5
        return h+d*amt
    def mk(dl,target,amt,ds):
        r,g,b=[v/255 for v in c]; h,l,s=colorsys.rgb_to_hls(r,g,b)
        h2=toward(c,target,amt)%1
        return tuple(round(v*255) for v in colorsys.hls_to_rgb(h2,min(.97,max(0.03,l+dl)),min(1,max(0,s+ds))))
    return {'hi':mk(+.11,0.14,0.12,.05),'b':c,'sh':mk(-.13,0.70,0.10,-.02),'dk':mk(-.27,0.70,0.16,-.05)}

class Sprite:
    def __init__(s,ramps):
        s.R={k:ramp(v) for k,v in ramps.items()}
        s.px={}   # (x,y)->(ramp,part,flat_color or None)
        s.parts={}
        s.flat={}
    def put(s,x,y,r,part,flat=None):
        if 0<=x<N and 0<=y<N:
            s.px[(x,y)]=(r,part,flat)
    def ell(s,cx,cy,rx,ry,r,part):
        for y in range(N):
            for x in range(N):
                if ((x+.5-cx)/rx)**2+((y+.5-cy)/ry)**2<=1: s.put(x,y,r,part)
    def rect(s,x0,y0,x1,y1,r,part):
        for y in range(y0,y1+1):
            for x in range(x0,x1+1): s.put(x,y,r,part)
    def poly(s,pts,r,part):
        def inside(x,y):
            c=False; n=len(pts)
            for i in range(n):
                (x1,y1),(x2,y2)=pts[i],pts[(i+1)%n]
                if (y1>y)!=(y2>y) and x<(x2-x1)*(y-y1)/(y2-y1)+x1: c=not c
            return c
        for y in range(N):
            for x in range(N):
                if inside(x+.5,y+.5): s.put(x,y,r,part)
    def rows(s,x0,y0,rows,key):
        # key: char -> (ramp, part) or ('#hex',) flat
        for j,row in enumerate(rows):
            for i,ch in enumerate(row):
                if ch in key:
                    v=key[ch]
                    if v is None: s.px.pop((x0+i,y0+j),None)
                    elif v[0].startswith('#'): s.put(x0+i,y0+j,None,v[1] if len(v)>1 else 'flat',hx(v[0]))
                    else: s.put(x0+i,y0+j,v[0],v[1])
    def mirror(s,fn,cx=16):
        """call fn(sign, X) where X(x)->mirrored x around center line between 15|16"""
        fn(lambda x:x); fn(lambda x:31-x)
    def render(s,shade=True,outline=True):
        img={}
        masks={}
        for (x,y),(r,p,f) in s.px.items(): masks.setdefault(p,set()).add((x,y))
        for (x,y),(r,p,f) in s.px.items():
            if f is not None: img[(x,y)]=f; continue
            M=masks[p]; R=s.R[r]; t='b'
            if shade and len(M)>=14 and not p.startswith('_'):
                below=(x,y+1) not in M; right=(x+1,y) not in M; br=(x+1,y+1) not in M
                if below or (br and right): t='sh'
                elif (x,y+2) not in M and (x+1,y+1) not in M: t='sh'
                above=(x,y-1) not in M; left=(x-1,y) not in M
                if t=='b' and above and ((x-1,y-1) not in M or left): t='hi'
            img[(x,y)]=R[t]
        if outline:
            filled=set(s.px)
            out={}
            for (x,y) in [(x,y) for x in range(N) for y in range(N)]:
                if (x,y) in filled: continue
                nb=[(x+dx,y+dy) for dx,dy in ((0,1),(0,-1),(1,0),(-1,0)) if (x+dx,y+dy) in filled]
                if nb:
                    # selective outline: dark version of neighbor, pulled toward ink
                    q=nb[0]; r,p,f=s.px[q]
                    base=s.R[r]['dk'] if r else tuple(int(v*.45) for v in f)
                    mix=.55
                    out[(x,y)]=tuple(round(base[i]*(1-mix)+INK[i]*mix) for i in range(3))
            img.update(out)
        return img

def to_png(img,path,scale=10,bg=(240,242,250)):
    from PIL import Image
    im=Image.new('RGB',(N*scale,N*scale),bg)
    for (x,y),c in img.items():
        for i in range(scale):
            for j in range(scale): im.putpixel((x*scale+i,y*scale+j),c)
    im.save(path)
def to_svg(img,cell,extra=''):
    rects=''.join(f'<rect x="{x}" y="{y}" width="1.02" height="1.02" fill="{tohex(c)}"></rect>' for (x,y),c in sorted(img.items(),key=lambda k:(k[0][1],k[0][0])))
    return f'<svg viewBox="0 0 {N} {N}" width="{N*cell}" height="{N*cell}" shape-rendering="crispEdges" style="display: block" aria-hidden="true">{rects}{extra}</svg>'

# eye glyphs (flat colors drawn after shading)
EYE_INK='#141836'
def eye(s,x,y,mood='idle',w=3,h=4,iris=None):
    W='#FFFFFF'
    if mood in ('idle','grin'):
        for j in range(h):
            for i in range(w):
                c=iris if (iris and j>=h-2) else EYE_INK
                s.put(x+i,y+j,None,'eye',hx(c))
        s.put(x,y,None,'eye',hx(W)); s.put(x+1,y,None,'eye',hx(W)); s.put(x,y+1,None,'eye',hx(W))
        if not iris: s.put(x+w-1,y+h-1,None,'eye',hx('#B9C6FF'))
        else: s.put(x+w-1,y+h-2,None,'eye',shift(hx(iris),.25,0))
    elif mood in ('tired','meh'):
        # Heavy lids: the top row is gone; tired also draws the lid line across what's left.
        top=1 if mood=='meh' else 2
        for j in range(top,h):
            for i in range(w):
                c=iris if (iris and j>=h-2 and not (mood=='tired' and j==top)) else EYE_INK
                s.put(x+i,y+j,None,'eye',hx(c))
        if mood=='meh': s.put(x,y+top,None,'eye',hx(W))
    elif mood=='sleepy':
        for i in range(w): s.put(x+i,y+h-1,None,'eye',hx(EYE_INK))
        s.put(x-1 if x<16 else x+w,y+h-2,None,'eye',hx(EYE_INK)) if False else None
    elif mood=='happy':
        # ^ shape
        s.put(x,y+h-1,None,'eye',hx(EYE_INK)); s.put(x+w-1,y+h-1,None,'eye',hx(EYE_INK))
        for i in range(1,w-1): s.put(x+i,y+h-2,None,'eye',hx(EYE_INK))
        if w==3: s.put(x+1,y+h-2,None,'eye',hx(EYE_INK))
def blush(s,x,y,c='#FF8FA8'):
    s.put(x,y,None,'blush',hx(c)); s.put(x+1,y,None,'blush',hx(c))
