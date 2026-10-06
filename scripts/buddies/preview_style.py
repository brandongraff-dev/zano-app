"""Contact sheets for the shop's style items (needs Pillow). Usage:
   python3 scripts/buddies/preview_style.py out.png hat|eyewear|neck|back|skin|backdrop [face]"""
import os, sys
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
import buddies, style
from engine import N, ramp, Sprite
from PIL import Image
out, kind = sys.argv[1], sys.argv[2]; face = sys.argv[3] if len(sys.argv) > 3 else 'happy'
ORDER=['Stash','Zib','Lox','Pip','Moko','Brick','Tank','Volt','Howl']
BG=(22,24,48); S=4
def comp(layers):
    im=Image.new('RGB',(N,N),BG)
    for img in layers:
        for (x,y),c in img.items(): im.putpixel((x,y),c)
    return im
def skinned(buddy, skin):
    sp=buddies.B[buddy](face); img=sp.render()
    base=sp.R and None
    # rebuild the original base hex for the buddy's main ramp
    import engine
    main=style.MAIN_RAMP[buddy]
    probe=buddies.B[buddy]('content')
    # find the base colour from the ramp (b) -> hex
    b=probe.R[main]['b']; hexb='#%02X%02X%02X'%b
    pairs,_=style.skin_table(buddy,hexb,skin); m=dict(pairs)
    return {k:m.get(v,v) for k,v in img.items()}
cols=[]
if kind=='hat': cols=[('hat',i) for i in style.HAT_ORDER]
elif kind=='eyewear': cols=[('eyewear',i) for i in style.EYE_ORDER]
elif kind=='neck': cols=[('neck',i) for i in style.NECK_ORDER]
elif kind=='back': cols=[('back',i) for i in style.BACKS]
elif kind=='skin': cols=[('skin',i) for i in style.SKIN_ORDER]
elif kind=='backdrop': cols=[('backdrop',i) for i in style.BACKDROPS]
if kind=='backdrop':
    rows=['Stash']
else: rows=ORDER
pad=2; sheet=Image.new('RGB',(len(cols)*(N*S+pad),len(rows)*(N*S+pad)),BG)
for r,b in enumerate(rows):
    for c,(slot,item) in enumerate(cols):
        face_img=buddies.B[b](face).render()
        if slot=='skin': layers=[skinned(b,item)]
        elif slot=='backdrop': layers=[style.backdrop(item).render(),face_img]
        else:
            ov=style.overlay(b,slot,item).render()
            layers=[ov,face_img] if slot=='back' else [face_img,ov]
        sheet.paste(comp(layers).resize((N*S,N*S),Image.NEAREST),(c*(N*S+pad),r*(N*S+pad)))
sheet.save(out); print(out,sheet.size)
