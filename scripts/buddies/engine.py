"""Pixel sprite engine v2: 48x48, part-aware shading, selective outlines, face toolkit."""
import colorsys, math
N=48
INK=(11,14,36)
def hx(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))
def tohex(c): return '#%02X%02X%02X'%c
def _hls(c): return colorsys.rgb_to_hls(*[v/255 for v in c])
def _rgb(h,l,s): return tuple(round(v*255) for v in colorsys.hls_to_rgb(h%1,min(.98,max(0.02,l)),min(1,max(0,s))))
def ramp(base):
    c=hx(base); h,l,s=_hls(c)
    def toward(t,a): d=((t-h+0.5)%1)-0.5; return h+d*a
    return {'hi':_rgb(toward(0.14,0.12),l+.10,s+.04),'b':c,
            'sh':_rgb(toward(0.70,0.10),l-.12,s-.02),'dk':_rgb(toward(0.70,0.16),l-.26,s-.05)}

class Sprite:
    def __init__(s,ramps):
        s.R={k:ramp(v) for k,v in ramps.items()}
        s.px={}; s.desat=0.0
    def put(s,x,y,r,part,flat=None):
        x,y=int(x),int(y)
        if 0<=x<N and 0<=y<N: s.px[(x,y)]=(r,part,flat)
    def get(s,x,y): return s.px.get((int(x),int(y)))
    def erase(s,x,y): s.px.pop((int(x),int(y)),None)
    def ell(s,cx,cy,rx,ry,r,part,clip=None):
        for y in range(N):
            for x in range(N):
                if ((x+.5-cx)/rx)**2+((y+.5-cy)/ry)**2<=1 and (clip is None or clip(x,y)): s.put(x,y,r,part)
    def rect(s,x0,y0,x1,y1,r,part):
        for y in range(int(y0),int(y1)+1):
            for x in range(int(x0),int(x1)+1): s.put(x,y,r,part)
    def poly(s,pts,r,part):
        n=len(pts)
        for y in range(N):
            for x in range(N):
                X,Y=x+.5,y+.5; c=False
                for i in range(n):
                    (x1,y1),(x2,y2)=pts[i],pts[(i+1)%n]
                    if (y1>Y)!=(y2>Y) and X<(x2-x1)*(Y-y1)/(y2-y1)+x1: c=not c
                if c: s.put(x,y,r,part)
    def recolor(s,cond,r,part):
        for (x,y),v in list(s.px.items()):
            if cond(x,y,v): s.px[(x,y)]=(r,part,None)
    def F(s,x,y,c,part='_f'): s.put(x,y,None,part,hx(c) if isinstance(c,str) else c)
    def rowsF(s,x0,y0,rows,key):
        for j,row in enumerate(rows):
            for i,ch in enumerate(row):
                if ch in key and key[ch] is not None: s.F(x0+i,y0+j,key[ch])
    def render(s):
        img={}; masks={}
        for (x,y),(r,p,f) in s.px.items(): masks.setdefault(p,set()).add((x,y))
        for (x,y),(r,p,f) in s.px.items():
            if f is not None: img[(x,y)]=f; continue
            M=masks[p]; R=s.R[r]; t='b'
            if len(M)>=20 and not p.startswith('_'):
                if (x,y+1) not in M or ((x+1,y+1) not in M and (x+1,y) not in M): t='sh'
                elif (x,y+2) not in M and (x+1,y+1) not in M: t='sh'
                elif (x,y-1) not in M and ((x-1,y-1) not in M or (x-1,y) not in M): t='hi'
            img[(x,y)]=R[t]
        filled=set(s.px); out={}
        for x in range(N):
            for y in range(N):
                if (x,y) in filled: continue
                nb=[(x+dx,y+dy) for dx,dy in ((0,1),(0,-1),(1,0),(-1,0)) if (x+dx,y+dy) in filled]
                if nb:
                    r,p,f=s.px[nb[0]]
                    if p.startswith('~'): continue   # floating extras (sparkles, hearts) get no outline
                    base=s.R[r]['dk'] if r else tuple(int(v*.45) for v in f)
                    out[(x,y)]=tuple(round(base[i]*.45+INK[i]*.55) for i in range(3))
        img.update(out)
        if s.desat:
            k=s.desat
            for p,c in img.items():
                g=sum(c)/3
                img[p]=tuple(round((c[i]*(1-k)+g*k)*0.9) for i in range(3))
        return img

def to_png(img,path,scale=8,bg=(240,242,250)):
    from PIL import Image
    im=Image.new('RGB',(N,N),bg)
    for (x,y),c in img.items(): im.putpixel((x,y),c)
    im.resize((N*scale,N*scale),Image.NEAREST).save(path)
