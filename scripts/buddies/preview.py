"""Contact sheet of every buddy x every face (old + new), for checking art without a simulator.
Run: python3 scripts/buddies/preview.py [out.png] [expr ...]   (needs Pillow)"""
import os, sys
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
import buddies
from face import EXPRS, ACTIVITY
from engine import N
from PIL import Image
out=sys.argv[1] if len(sys.argv)>1 else 'buddy-sheet.png'
exprs=sys.argv[2:] or ACTIVITY
ORDER=['Stash','Zib','Lox','Pip','Moko','Brick','Tank','Volt','Howl']
S=4; pad=2
sheet=Image.new('RGB',(len(exprs)*(N*S+pad),len(ORDER)*(N*S+pad)),(22,24,48))
for r,name in enumerate(ORDER):
    for c,e in enumerate(exprs):
        img=buddies.B[name](e).render(); im=Image.new('RGB',(N,N),(22,24,48))
        for (x,y),col in img.items(): im.putpixel((x,y),col)
        sheet.paste(im.resize((N*S,N*S),Image.NEAREST),(c*(N*S+pad),r*(N*S+pad)))
sheet.save(out); print(out,sheet.size)
