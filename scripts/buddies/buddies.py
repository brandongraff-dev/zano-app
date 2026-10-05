from engine import *
from face import *
import math
def M(x): return 48-x                     # mirror a continuous x
def mpts(pts): return [(48-x,y) for x,y in pts]
def limb(s,x0,y0,x1,y1,r,part,rad=2.6):
    """A stubby arm from (x0,y0) to a round paw at (x1,y1)."""
    steps=12
    for k in range(steps+1):
        t=k/steps; s.ell(x0+(x1-x0)*t,y0+(y1-y0)*t,rad*0.8,rad*0.8,r,part)
    s.ell(x1,y1,rad,rad,r,part)

# ---------------------------------------------------------------- Stash, raccoon (default)
def stash(expr):
    s=Sprite({'fur':'#A3ABC2','pale':'#F1F3FA','mask':'#454A6E','ring':'#4B5174','case':'#2A2D42','screen':'#2BB5A0','paw':'#454A6E'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    # tail behind, curling up on the right
    s.ell(37.5,33,6.5,11,'fur','tail'); s.ell(39,23.5,4.5,4,'fur','tail')
    s.recolor(lambda x,y,v:v[1]=='tail' and (y+1)%5 in (0,1),'ring','ring')
    s.ell(22,38.5,10.5,8.5,'fur','body'); s.ell(22,40.5,6.5,5.5,'pale','belly')
    s.ell(17,46,3.6,1.8,'paw','footL'); s.ell(27,46,3.6,1.8,'paw','footR')
    # ears
    if droop:
        s.poly([(9,14),(2,13),(5,7),(12,9)],'fur','earL'); s.poly(mpts([(9,14),(2,13),(5,7),(12,9)])[::1],'fur','earR')
        s.poly([(7,12),(4,11),(6,9),(9,10)],'pale','_eiL'); s.poly(mpts([(7,12),(4,11),(6,9),(9,10)]),'pale','_eiR')
    else:
        s.poly([(7,14),(7,2.5),(15,8)],'fur','earL'); s.poly(mpts([(7,14),(7,2.5),(15,8)]),'fur','earR')
        s.poly([(8.5,11),(8.5,5.5),(12.5,8.5)],'pale','_eiL'); s.poly(mpts([(8.5,11),(8.5,5.5),(12.5,8.5)]),'pale','_eiR')
    s.ell(24,19.5,15.5,12.5,'fur','head')
    s.ell(24,10.5,4,2,'pale','_brow')
    s.ell(17.5,20,6.5,4.6,'mask','mask'); s.ell(30.5,20,6.5,4.6,'mask','mask'); s.rect(21,18,26,20,'mask','mask')
    s.ell(24,26.5,7,4.6,'pale','muzzle')
    s.ell(9.5,24,2.6,2.2,'pale','_cheekL'); s.ell(38.5,24,2.6,2.2,'pale','_cheekR')
    s.rowsF(22,23,["KKKK",".KK."],{'K':'#2A2440'}); s.F(22,23,'#6E6890')
    eyes(s,14,29,17,5,6,expr,'#2BC4AE',('mask','mask'),lid='#F1F3FA',rim='#DDE2F2')
    brows(s,14,29,14,5,expr,'#2A2440')
    mouth(s,24,27,expr,'cat')
    blush(s,10,36,26,expr)
    # paws (no phone: it read as odd). Down = little paws clasped on the belly.
    if arms=='up':
        limb(s,15,34,7,27,'fur','armL'); limb(s,33,34,41,27,'fur','armR'); s.ell(7,27,2.6,2.6,'paw','_pL'); s.ell(41,27,2.6,2.6,'paw','_pR')
    elif arms=='wave':
        limb(s,15,34,6,28,'fur','armL'); s.ell(6,28,2.6,2.6,'paw','_pL'); s.ell(26.5,37.5,2.5,2.3,'fur','pR')
    elif arms=='droop':
        s.ell(17.5,42,2.5,2.3,'fur','pL'); s.ell(26.5,42,2.5,2.3,'fur','pR')
    else:
        s.ell(17.5,37.5,2.5,2.3,'fur','pL'); s.ell(26.5,37.5,2.5,2.3,'fur','pR')
    extras(s,expr,top_right=(42,3),top_left=(1,1),cheek=(30,27))
    return s


# ---------------------------------------------------------------- Zib, mochi bunny (one squishy blob)
def zib(expr):
    s=Sprite({'fur':'#E8EDFF','pink':'#FFB7CB','stalk':'#8C97C8','bow':'#3F7BFF'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    if droop:
        s.ell(11,20,3.4,9,'fur','earL'); s.ell(37,20,3.4,9,'fur','earR')
        s.ell(11,21,1.4,6,'pink','_eiL'); s.ell(37,21,1.4,6,'pink','_eiR')
    else:
        s.ell(17,12,3.8,10,'fur','earL'); s.ell(31,12,3.8,10,'fur','earR')
        s.ell(17,12.5,1.6,7,'pink','_eiL'); s.ell(31,12.5,1.6,7,'pink','_eiR')
    s.ell(24,33.5,17,12.5,'fur','body', clip=lambda x,y: y<=45)
    s.ell(18,45.6,3.6,1.6,'fur','footL'); s.ell(30,45.6,3.6,1.6,'fur','footR')
    if arms=='up': s.ell(5.5,26,2.6,3.4,'fur','armL'); s.ell(42.5,26,2.6,3.4,'fur','armR')
    elif arms=='wave': s.ell(5.5,26,2.6,3.4,'fur','armL'); s.ell(41,37,2.6,3,'fur','armR')
    elif arms=='droop': s.ell(7.5,40,2.6,3,'fur','armL'); s.ell(40.5,40,2.6,3,'fur','armR')
    else: s.ell(7,36.5,2.6,3,'fur','armL'); s.ell(41,36.5,2.6,3,'fur','armR')
    # star antenna
    s.rect(23,12,24,20,'stalk','_stalk')
    s.rowsF(20,4,["...YY...","...YY...","YYYYYYYY",".YYWYYY.","..YYYY..",".YY..YY.","YY....YY"],{'Y':'#FFD447','W':'#FFF6C2'})
    # little blue bow on the left ear
    s.rowsF(12,18,["BB.BB","BBBBB","BB.BB"],{'B':'#3F7BFF'}); s.F(14,19,'#2A62E6')
    eyes(s,15,29,27,4,6,expr,'#3F7BFF',('fur','body'))
    brows(s,15,29,24,4,expr,'#8C97C8')
    mouth(s,24,35,expr)
    blush(s,10,35,35,expr)
    extras(s,expr,top_right=(40,6),top_left=(2,8),cheek=(30,33))
    return s

# ---------------------------------------------------------------- Lox, fox (slim, huge wrapped tail)
def lox(expr):
    s=Sprite({'fur':'#FF8A3D','cream':'#FFF1DC','tip':'#5B3B8C','gold':'#FFC94A','paw':'#5B3B8C'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    # bushy tail rising behind on the right, cream tip
    s.poly([(28,44),(36,42),(43,34),(45,22),(41,13),(37,20),(35,30),(28,37)],'fur','tail')
    s.recolor(lambda x,y,v: v[1]=='tail' and y<=19,'cream','_tip')
    s.ell(23,36.5,8.5,9.5,'fur','body'); s.ell(23,38,5,6.5,'cream','chest')
    s.ell(19,46,3,1.6,'paw','footL'); s.ell(27,46,3,1.6,'paw','footR')
    if droop:
        s.poly([(10,16),(1,12),(8,6),(14,10)],'fur','earL'); s.poly(mpts([(10,16),(1,12),(8,6),(14,10)]),'fur','earR')
        s.poly([(3,11),(1,12),(5,10)],'tip','_tL'); s.poly(mpts([(3,11),(1,12),(5,10)]),'tip','_tR')
    else:
        s.poly([(10,14),(8,0.5),(19,8)],'fur','earL'); s.poly(mpts([(10,14),(8,0.5),(19,8)]),'fur','earR')
        s.poly([(8.6,5),(8.2,1),(11,3.5)],'tip','_tL'); s.poly(mpts([(8.6,5),(8.2,1),(11,3.5)]),'tip','_tR')
        s.poly([(11,11),(10,5),(15,8.5)],'cream','_iL'); s.poly(mpts([(11,11),(10,5),(15,8.5)]),'cream','_iR')
    s.ell(24,18.5,13.5,10.5,'fur','head')
    s.poly([(12,19),(3,25),(13,26)],'fur','tuftL'); s.poly(mpts([(12,19),(3,25),(13,26)]),'fur','tuftR')
    s.poly([(5,24),(12,20),(24,22),(36,20),(43,24),(34,29),(24,30),(14,29)],'cream','mask')
    s.rowsF(23,21,["KK"],{'K':'#2A2440'}); s.F(23,21,'#6E6890')
    eyes(s,14,28,14,6,6,expr,'#FFB347',('fur','head'))
    brows(s,15,28,12,6,expr,'#B3561A')
    mouth(s,24,24,expr)
    blush(s,10,36,23,expr)
    # padlock locket
    s.rowsF(21,28,[".GGG.","G...G","GGGGG","GGKGG","GGGGG"],{'G':'#FFC94A','K':'#5B3B8C'})
    if arms=='up': limb(s,17,32,9,24,'fur','armL',2.3); limb(s,30,32,38,24,'fur','armR',2.3)
    elif arms=='wave': limb(s,17,32,9,24,'fur','armL',2.3); s.ell(29,39,2.3,2.3,'fur','pR')
    elif arms=='droop': s.ell(17,41,2.3,2.3,'fur','pL'); s.ell(30,41,2.3,2.3,'fur','pR')
    else: s.ell(17,38,2.3,2.3,'fur','pL'); s.ell(30,38,2.3,2.3,'fur','pR')
    extras(s,expr,top_right=(41,2),top_left=(1,1),cheek=(29,24))
    return s

# ---------------------------------------------------------------- Pip, owl-axolotl (round egg body)
def pip(expr):
    s=Sprite({'body':'#9A6BFF','face':'#E6DBFF','belly':'#D4C2FF','gill':'#FF9FC8','ring':'#FFC94A','beak':'#FF9F43','wing':'#7A4FE0'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    # three chunky gill fronds a side (they sag when Pip is down)
    for side,X in ((0,lambda x:x),(1,lambda x:48-x)):
        tips=[(3,15),(1.5,22),(3,29)] if not droop else [(4,24),(3,29),(5,34)]
        for k,(tx,ty) in enumerate(tips):
            y0=19+k*4
            s.poly([(X(10),y0-2),(X(tx),ty-1.2),(X(tx-0.5),ty+1.2),(X(10),y0+2)],'gill','g%d%d'%(side,k))
            s.F(int(X(tx+0.5)) if side==0 else int(X(tx+0.5))-1,int(ty),'#FFD1E3')
    s.ell(24,27.5,15,17,'body','body')
    s.ell(24,35,9,8,'belly','belly')
    for (x,y) in [(21,32),(24,33),(27,32),(22,36),(26,36),(24,39)]: s.F(x,y,'#B79CFF'); s.F(x+1,y+1,'#B79CFF')
    if not droop:
        s.poly([(12,13),(11,4),(18,11)],'body','tuftL'); s.poly(mpts([(12,13),(11,4),(18,11)]),'body','tuftR')
    s.ell(17.5,22,7,7,'ring','_rL'); s.ell(30.5,22,7,7,'ring','_rR')
    s.ell(17.5,22,5.6,5.6,'face','faceL'); s.ell(30.5,22,5.6,5.6,'face','faceR')
    s.recolor(lambda x,y,v: v[1]=='faceR','face','faceL')
    eyes(s,15,28,19,6,6,expr,'#7A4FE0',('face','faceL'))
    brows(s,15,28,14,6,expr,'#5B2FC0')
    # beak (opens with the mood)
    if expr in ('happy','excited','ecstatic'):
        s.rowsF(22,28,["BBBB","BRRB","BRRB",".BB."],{'B':'#FF9F43','R':'#7A2240'})
    else:
        s.rowsF(22,28,["BBBB",".BB."],{'B':'#FF9F43'})
    blush(s,9,36,29,expr)
    if arms=='up': s.poly([(10,30),(3,18),(12,24)],'wing','wL'); s.poly(mpts([(10,30),(3,18),(12,24)]),'wing','wR')
    elif arms=='wave': s.poly([(10,30),(3,18),(12,24)],'wing','wL'); s.ell(39,33,2.6,5,'wing','wR')
    elif arms=='droop': s.ell(9.5,36,2.6,5,'wing','wL'); s.ell(38.5,36,2.6,5,'wing','wR')
    else: s.ell(9,33,2.6,5,'wing','wL'); s.ell(39,33,2.6,5,'wing','wR')
    s.rowsF(18,44,["BBB...BBB"[:3]+"......"],{'B':'#FF9F43'}); s.rowsF(27,44,["BBB"],{'B':'#FF9F43'})
    extras(s,expr,top_right=(41,3),top_left=(1,3),cheek=(30,30))
    return s

# ---------------------------------------------------------------- Moko, dino peeking out of its egg
def moko(expr):
    s=Sprite({'skin':'#62D68E','mint':'#D9F7C7','spike':'#FF9FB2','shell':'#FFF6DE'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    hy=21 if not droop else 23
    for x,h in [(16,4),(24,5),(32,4)]:
        s.poly([(x-2.6,hy-9),(x,hy-9-h),(x+2.6,hy-9)],'spike','_sp%d'%x)
    s.ell(24,hy,14,12,'skin','head')
    # shell cap with a zigzag rim (not when sad: it slid off)
    if not droop:
        s.ell(24,hy-10,7,3.4,'shell','cap')
        for x in range(17,32):
            if x%2==0 and s.get(x,hy-8) and s.get(x,hy-8)[1]=='cap': s.put(x,hy-8,'skin','head')
    s.ell(24,hy+7,7.5,4,'mint','muzzle')
    s.F(21,hy+4,'#3E9E66'); s.F(26,hy+4,'#3E9E66')
    eyes(s,14,28,hy-5,6,7,expr,'#2FB86B',('skin','head'))
    brows(s,15,28,hy-7,5,expr,'#3E9E66')
    mouth(s,24,hy+7,expr)
    blush(s,10,35,hy+4,expr)
    # egg
    s.ell(24,40.5,18,9,'shell','egg',clip=lambda x,y: y<=46)
    for x in range(6,43):
        top=33 if (x//3)%2==0 else 35
        for y in range(28,top):
            if s.get(x,y) and s.get(x,y)[1]=='egg': s.erase(x,y)
    for x,y in [(12,40),(13,40),(33,38),(34,38),(23,43),(24,43),(29,42)]: s.F(x,y,'#FFB3C7')
    if arms=='up': s.ell(6,25,3,3,'skin','pL'); s.ell(42,25,3,3,'skin','pR')
    elif arms=='wave': s.ell(6,25,3,3,'skin','pL'); s.ell(36,34,3,2.6,'skin','pR')
    elif arms=='droop': pass
    else: s.ell(12,34,3,2.6,'skin','pL'); s.ell(36,34,3,2.6,'skin','pR')
    extras(s,expr,top_right=(42,4),top_left=(1,2),cheek=(30,hy+5))
    return s

# ---------------------------------------------------------------- Brick, bulldog (wide, stocky, flexes)
def brick(expr):
    s=Sprite({'fur':'#D99E68','cream':'#F6E4CB','band':'#E5484D','top':'#3F7BFF','ear':'#9C6640','paw':'#C98A55'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    s.ell(24,39.5,14,7.5,'top','top')
    s.recolor(lambda x,y,v: v[1]=='top' and y==33,'cream','_trim')
    s.rowsF(22,37,[".YY","YY.",".YY","YY."],{'Y':'#FFD447'})
    s.ell(17,46.2,4,1.7,'fur','footL'); s.ell(31,46.2,4,1.7,'fur','footR')
    if arms=='up':
        limb(s,12,35,5,30,'fur','aL',3); limb(s,5,30,8,22,'fur','aL',3); limb(s,36,35,43,30,'fur','aR',3); limb(s,43,30,40,22,'fur','aR',3)
    elif arms=='wave':
        limb(s,12,35,5,30,'fur','aL',3); limb(s,5,30,8,22,'fur','aL',3); s.ell(39,40,3.2,3.2,'fur','aR')
    elif arms=='droop': s.ell(9,42,3.2,3.2,'fur','aL'); s.ell(39,42,3.2,3.2,'fur','aR')
    else: s.ell(9,39,3.2,3.2,'fur','aL'); s.ell(39,39,3.2,3.2,'fur','aR')
    s.ell(14,27,5.5,5,'fur','jowlL'); s.ell(34,27,5.5,5,'fur','jowlR')
    s.ell(24,19,16,13,'fur','head')
    if droop:
        s.poly([(6,12),(1,20),(5,22),(10,15)],'ear','eL'); s.poly(mpts([(6,12),(1,20),(5,22),(10,15)]),'ear','eR')
    else:
        s.poly([(5,11),(8,4),(15,6),(10,12)],'ear','eL'); s.poly(mpts([(5,11),(8,4),(15,6),(10,12)]),'ear','eR')
    s.recolor(lambda x,y,v: v[1]=='head' and y in (9,10,11),'band','band')
    s.ell(24,26,9.5,5.5,'cream','muzzle')
    s.rowsF(20,20,[".KKKKKKK."[:8],"KKKKKKKK",".KKKKKK."],{'K':'#2A2440'}); s.F(21,20,'#7C77A0'); s.F(22,20,'#7C77A0')
    eyes(s,13,30,14,6,6,expr,'#8A5A2E',('fur','head'))
    brows(s,14,30,12,5,expr,'#9C6640')
    mouth(s,24,25,expr)
    if expr in ('content','meh','sleepy'):   # the underbite: two little teeth
        s.F(20,25,'#FFFFFF'); s.F(27,25,'#FFFFFF')
    blush(s,8,37,24,expr)
    extras(s,expr,top_right=(42,1),top_left=(1,0),cheek=(31,24))
    return s

# ---------------------------------------------------------------- Tank, rhino (round, chunky, jersey)
def tank(expr):
    s=Sprite({'skin':'#98A3BE','snout':'#B6BED4','horn':'#FFF1DC','jersey':'#5C6378','trim':'#C8F04A','ear':'#7E89A6'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    s.ell(24,39,13,8,'jersey','body')
    s.recolor(lambda x,y,v: v[1]=='body' and y==32,'trim','_trim')
    s.rowsF(21,36,["TTTTT","...T.","..T..",".T...","TTTTT"],{'T':'#C8F04A'})
    s.ell(17,46.2,4,1.7,'skin','fL'); s.ell(31,46.2,4,1.7,'skin','fR')
    def paw(x,y): s.ell(x,y,3.2,3.2,'skin','p%d'%x); s.rect(x-3,y+2,x+3,y+2,'trim','_wb%d'%x)
    if arms=='up': limb(s,13,35,6,26,'skin','aL',3); limb(s,35,35,42,26,'skin','aR',3); paw(6,25); paw(42,25)
    elif arms=='wave': limb(s,13,35,6,26,'skin','aL',3); paw(6,25); paw(39,39)
    elif arms=='droop': paw(9,42); paw(39,42)
    else: paw(9,38); paw(39,38)
    ey=9 if not droop else 13
    s.ell(9.5,ey,3.4,3.8,'ear','eL'); s.ell(38.5,ey,3.4,3.8,'ear','eR')
    s.F(9,ey,'#C9A0B0'); s.F(38,ey,'#C9A0B0')
    s.ell(24,19.5,15,12,'skin','head')
    s.ell(24,26,9.5,5.5,'snout','snout')
    s.poly([(20.5,23),(24,9),(28,23)],'horn','horn'); s.poly([(26.5,13),(28,9.5),(29.5,14)],'horn','_h2') if False else None
    s.F(19,26,'#2A2440'); s.F(28,26,'#2A2440')
    eyes(s,12,30,14,6,6,expr,'#5C6378',('skin','head'))
    brows(s,12,31,12,5,expr,'#6C7690')
    mouth(s,24,28,expr)
    blush(s,7,38,23,expr)
    extras(s,expr,top_right=(42,1),top_left=(1,0),cheek=(31,27))
    return s

# ---------------------------------------------------------------- Volt, shark (torpedo body, bolt fin)
def volt(expr):
    s=Sprite({'skin':'#4FA8F5','belly':'#EAF5FF','fin':'#3B8FD9'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    s.poly([(36,34),(47,26),(45,35),(47,44),(36,39)],'fin','tail')
    s.ell(24,27,17,16,'skin','body')
    s.ell(24,33,12,10,'belly','belly',clip=lambda x,y: y>=26)
    # lightning fin
    fin=["....YY","...YY.","..YYYY",".YYYY.","...YY.","..YY..",".YY..."] if not droop else ["..YY..",".YYYY.","YY.YY.","..YY..","......","......","......"]
    s.rowsF(21,4 if not droop else 8,fin,{'Y':'#FFD447'})
    for x,y in [(9,24),(9,27),(10,30),(38,24),(38,27),(37,30)]: s.F(x,y,'#2C78C2'); s.F(x+(1 if x<24 else -1),y,'#2C78C2')
    if arms=='up': s.poly([(10,28),(2,16),(13,24)],'fin','aL'); s.poly(mpts([(10,28),(2,16),(13,24)]),'fin','aR')
    elif arms=='wave': s.poly([(10,28),(2,16),(13,24)],'fin','aL'); s.poly(mpts([(10,32),(3,38),(12,36)]),'fin','aR')
    elif arms=='droop': s.poly([(10,34),(4,42),(12,38)],'fin','aL'); s.poly(mpts([(10,34),(4,42),(12,38)]),'fin','aR')
    else: s.poly([(10,32),(3,38),(12,36)],'fin','aL'); s.poly(mpts([(10,32),(3,38),(12,36)]),'fin','aR')
    s.ell(18,44.8,3.2,1.6,'fin','fL'); s.ell(30,44.8,3.2,1.6,'fin','fR')
    eyes(s,13,29,16,6,6,expr,'#1FA2FF',('skin','body'))
    if expr in ('content','happy'):
        for i in range(5): s.F(14+i,15+(1 if i>2 else 0),'#2A4F8C'); s.F(33-i,15+(1 if i>2 else 0),'#2A4F8C')
    brows(s,14,29,14,5,expr,'#2A4F8C')
    if expr in ('happy','excited','ecstatic'):
        mouth(s,24,25,expr)
        w=len(MOUTHS[expr][0]); x0=24-w//2
        for i in range(1,w-1,2): s.F(x0+i,26,'#FFFFFF')
    else:
        mouth(s,24,25,expr)
    blush(s,9,36,24,expr)
    extras(s,expr,top_right=(42,2),top_left=(1,1),cheek=(31,25))
    return s

# ---------------------------------------------------------------- Howl, wolf in a hoodie
def howl(expr):
    s=Sprite({'fur':'#94A0BE','pale':'#EEF0F7','hood':'#4E63B5','lining':'#26305F','pocket':'#33427E'})
    arms=arms_pose(expr); droop=ears_droop(expr)
    s.ell(24,40,13,7.5,'hood','body')
    s.rect(17,40,30,44,'pocket','_pocket'); s.rect(18,40,29,40,'lining','_pl')
    s.ell(17,46.2,4,1.7,'lining','fL'); s.ell(31,46.2,4,1.7,'lining','fR')
    if arms=='up': limb(s,13,36,6,27,'hood','aL',3); limb(s,35,36,42,27,'hood','aR',3); s.ell(6,26,2.6,2.6,'fur','_pL'); s.ell(42,26,2.6,2.6,'fur','_pR')
    elif arms=='wave': limb(s,13,36,6,27,'hood','aL',3); s.ell(6,26,2.6,2.6,'fur','_pL'); s.ell(38,41,2.8,2.8,'fur','_pR')
    elif arms=='droop': s.ell(10,43,2.8,2.8,'fur','_pL'); s.ell(38,43,2.8,2.8,'fur','_pR')
    else: s.ell(10,40,2.8,2.8,'fur','_pL'); s.ell(38,40,2.8,2.8,'fur','_pR')
    if droop:
        s.poly([(9,14),(1,10),(5,6),(12,10)],'fur','eL'); s.poly(mpts([(9,14),(1,10),(5,6),(12,10)]),'fur','eR')
    else:
        s.poly([(9,13),(8,0.5),(17,7)],'fur','eL'); s.poly(mpts([(9,13),(8,0.5),(17,7)]),'fur','eR')
        s.poly([(10,9),(9.5,4),(14,7)],'pale','_iL'); s.poly(mpts([(10,9),(9.5,4),(14,7)]),'pale','_iR')
    s.ell(24,21,17,14,'hood','hoodie')
    s.ell(24,22.5,12.5,10.5,'lining','_lin')
    s.ell(24,23,11.5,9.8,'fur','face')
    for y in (26,29): s.poly([(13,y-2),(9,y),(13,y+1)],'pale','_tl%d'%y); s.poly(mpts([(13,y-2),(9,y),(13,y+1)]),'pale','_tr%d'%y)
    s.ell(24,28,5.5,4,'pale','muzzle')
    s.rowsF(23,25,["KK"],{'K':'#1E2033'})
    for y in range(33,38): s.F(20,y,'#FFFFFF'); s.F(27,y,'#FFFFFF')
    eyes(s,15,27,18,6,6,expr,'#FFC94A',('fur','face'))
    brows(s,16,27,16,5,expr,'#5B6683')
    mouth(s,24,29,expr)
    blush(s,13,32,27,expr)
    extras(s,expr,top_right=(42,1),top_left=(1,0),cheek=(30,28))
    return s

B={'Stash':stash,'Zib':zib,'Lox':lox,'Pip':pip,'Moko':moko,'Brick':brick,'Tank':tank,'Volt':volt,'Howl':howl}
