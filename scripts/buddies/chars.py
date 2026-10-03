from eng import *
def recolor(s,cond,r,part):
    for (x,y),v in list(s.px.items()):
        if cond(x,y,v): s.px[(x,y)]=(r,part,None)
def m(cx): return 32-cx          # mirror a continuous x
def mp(pts): return [(32-x,y) for x,y in pts]
def pair(s,fn): fn(lambda x:x,'L'); fn(lambda x:32-x,'R')
def eyes(s,mood,lx,y,w=3,h=4,iris=None):
    eye(s,lx,y,mood,w,h,iris); eye(s,31-lx-w+1,y,mood,w,h,iris)
def F(s,x,y,c,part='_f'): s.put(x,y,None,part,hx(c))
def rowsF(s,x0,y0,rows,key):
    for j,row in enumerate(rows):
        for i,ch in enumerate(row):
            if ch in key: F(s,x0+i,y0+j,key[ch])
MOUTH='#2A2238'; TONGUE='#E8566F'
def sweat(s):
    for x,y,col in [(25,6,'#BFE8FF'),(24,7,'#7FD0FF'),(25,7,'#FFFFFF'),(24,8,'#7FD0FF'),(25,8,'#7FD0FF')]: F(s,x,y,col,'_sweat')
def smile(s,mood,cx=16,y=18):
    if mood=='grin':
        rowsF(s,cx-3,y,["KKKKKK","KWWWWK",".KKKK."],{'K':MOUTH,'W':'#FFFFFF'})
    elif mood=='meh':
        rowsF(s,cx-2,y,["KKKK"],{'K':MOUTH})
    elif mood=='tired':
        rowsF(s,cx-1,y,[".K.","K.K",".K."][0:0]+["KK","KK"],{'K':MOUTH})
    elif mood=='happy':
        rowsF(s,cx-3,y,["KKKKKK",".KTTK.","..KK.."],{'K':MOUTH,'T':TONGUE})
    elif mood=='sleepy':
        rowsF(s,cx-1,y,["KK"],{'K':MOUTH})
    else:
        rowsF(s,cx-2,y,["K..K",".KK."],{'K':MOUTH})
def zzz(s):
    for x,y in [(25,1),(26,1),(27,1),(26,2),(25,3),(26,3),(27,3),(29,4),(30,4),(30,5),(29,6),(30,6)]: F(s,x,y,'#9AA6C8')
def spark(s,c='#FFD447'):
    for x,y in [(28,1),(27,2),(28,2),(29,2),(28,3),(2,5),(1,6),(3,6),(2,7)]: F(s,x,y,c)

def brick(mood):
    s=Sprite({'fur':'#D99E68','cream':'#F6E4CB','band':'#E5484D','top':'#3F7BFF','ear':'#9C6640','nose':'#2A2238'})
    s.ell(16,26.5,9.5,6,'top','top')
    pair(s,lambda X,k: s.ell(X(6),26.5,2.6,2.9,'fur','arm'+k))
    pair(s,lambda X,k: s.ell(X(11.5),30.3,3,1.6,'fur','foot'+k))
    pair(s,lambda X,k: s.ell(X(9),19.5,4.2,3.4,'fur','jowl'+k))
    s.ell(16,13.5,12.5,8.5,'fur','head')
    pair(s,lambda X,k: s.poly([(X(3),8),(X(6),3.5),(X(11),4.5),(X(7),9.5)] if k=='L' else mp([(3,8),(6,3.5),(11,4.5),(7,9.5)]),'ear','ear'+k))
    recolor(s,lambda x,y,v:v[1]=='head' and y in (6,7),'band','band')
    s.ell(16,18,7.5,4.2,'cream','muzzle')
    rowsF(s,13,14,[".NNNN.","NHNNNN",".NNNN."],{'N':'#2A2238','H':'#7C77A0'})
    eyes(s,mood,9,10,3,4,'#C98A4A')
    if mood=='happy':
        rowsF(s,11,18,["KKKKKKKKKK",".KTTTTTTK.","..KKKKKK.."],{'K':MOUTH,'T':TONGUE})
    elif mood=='grin':
        rowsF(s,11,18,["KKKKKKKKKK",".KWWWWWWK.","..KKKKKK.."],{'K':MOUTH,'W':'#FFFFFF'})
    elif mood in ('meh','tired'):
        rowsF(s,12,19,["KKKKKKKK"],{'K':MOUTH})
        F(s,12,18,'#FFFFFF'); F(s,19,18,'#FFFFFF')
    else:
        rowsF(s,11,19,["KK......KK","..KKKKKK.."],{'K':MOUTH})
        F(s,12,18,'#FFFFFF'); F(s,19,18,'#FFFFFF')
    rowsF(s,15,23,[".Y","YY","Y."],{'Y':'#FFD447'})
    blush(s,7,15); blush(s,23,15)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s)
    return s

def stash(mood):
    s=Sprite({'fur':'#9AA2B8','pale':'#EEF0F7','mask':'#3E4361','ring':'#4A4F6E','phone':'#2BB5A0','case':'#2A2D42'})
    s.ell(25.5,23,4,7,'fur','tail')
    recolor(s,lambda x,y,v:v[1]=='tail' and y%4 in (0,1),'ring','ring')
    s.ell(16,25.5,8,6,'fur','body')
    s.ell(16,26.5,5,4.2,'pale','belly')
    pair(s,lambda X,k: s.ell(X(12),30.3,2.6,1.5,'mask','foot'+k))
    s.ell(16,13,11.5,8.5,'fur','head')
    s.poly([(4,8),(6,1.5),(11,5.5)],'fur','earL'); s.poly(mp([(4,8),(6,1.5),(11,5.5)]),'fur','earR')
    s.poly([(5.5,6.5),(6.5,3.5),(9,5.5)],'pale','_eiL'); s.poly(mp([(5.5,6.5),(6.5,3.5),(9,5.5)]),'pale','_eiR')
    s.ell(10.5,12.5,5,3.2,'mask','maskL'); s.ell(21.5,12.5,5,3.2,'mask','maskR')
    s.rect(14,11,17,12,'mask','_bridge')
    s.ell(16,17.5,6,3.5,'pale','muzzle')
    s.ell(16,7,3.2,1.6,'pale','_brow')
    rowsF(s,15,15,["NN"],{'N':'#1E2033'})
    eyes(s,mood,9,11,3,4,'#2BB5A0')
    smile(s,mood,16,17)
    s.rect(13,21,18,26,'case','phone'); s.rect(14,22,17,25,'phone','_screen')
    rowsF(s,15,23,["WW"],{'W':'#FFFFFF'})
    s.ell(12.2,24,2,1.8,'fur','pawL'); s.ell(19.8,24,2,1.8,'fur','pawR')
    blush(s,6,16); blush(s,24,16)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s)
    return s

def zib(mood):
    s=Sprite({'fur':'#E3EAFF','pink':'#FFB3C7','scarf':'#3F7BFF','star':'#FFD447','stalk':'#8C97C8'})
    pair(s,lambda X,k: s.ell(X(10),8,2.8,6.5,'fur','ear'+k))
    pair(s,lambda X,k: s.ell(X(10),8.5,1.2,4.5,'pink','_ein'+k))
    s.ell(16,26,8.5,5.5,'fur','body')
    pair(s,lambda X,k: s.ell(X(11.5),30.3,3,1.6,'fur','foot'+k))
    s.ell(16,16,11.5,8,'fur','head')
    s.rect(15,5,16,8,'stalk','_stalk')
    rowsF(s,13,0,["..YY..","YYYYYY",".YWYY.","YY..YY"],{'Y':'#FFD447','W':'#FFF3B0'})
    s.ell(16,23.3,8,1.8,'scarf','scarf')
    s.rect(19,23,21,27,'scarf','tail')
    eyes(s,mood,9,13,3,4,'#3F7BFF')
    smile(s,mood,16,19)
    blush(s,7,18); blush(s,23,18)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s,'#FF9FC8')
    return s

def lox(mood):
    s=Sprite({'fur':'#FF8A3D','cream':'#FFF1DC','tip':'#5B3B8C','key':'#5B3B8C'})
    s.poly([(20,26),(31,13),(31,22),(26,29)],'fur','tail')
    recolor(s,lambda x,y,v:v[1]=='tail' and y<=16,'cream','_tailtip')
    s.ell(16,25.5,8,6,'fur','body')
    s.ell(16,26,5,4.5,'cream','belly')
    rowsF(s,14,23,[".KK.","KKKK","KKKK",".KK.",".KK.","KKKK"],{'K':'#5B3B8C'})
    F(s,15,24,'#8A68C0')
    pair(s,lambda X,k: s.ell(X(12),30.3,2.6,1.5,'fur','foot'+k))
    s.poly([(3,11),(5,1),(12,6)],'fur','earL'); s.poly(mp([(3,11),(5,1),(12,6)]),'fur','earR')
    s.poly([(5,7),(5.5,2.5),(8,4.5)],'tip','_etL'); s.poly(mp([(5,7),(5.5,2.5),(8,4.5)]),'tip','_etR')
    s.ell(16,14,11.5,8,'fur','head')
    s.poly([(4,15),(1,19),(7,19.5)],'fur','cheekL'); s.poly(mp([(4,15),(1,19),(7,19.5)]),'fur','cheekR')
    s.poly([(3,16.5),(10,15.5),(16,15),(22,15.5),(29,16.5),(24,21.5),(16,22.5),(8,21.5)],'cream','mask')
    rowsF(s,15,15,["NN"],{'N':'#2A2238'})
    eyes(s,mood,9,11,3,4,'#FF8A3D')
    smile(s,mood,16,17)
    blush(s,7,16); blush(s,23,16)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s)
    return s

def pip(mood):
    s=Sprite({'fur':'#9A6BFF','belly':'#D9C9FF','gill':'#FF9FC8','ring':'#FFC94A','wing':'#7A4FE0'})
    for X in (lambda x:x, lambda x:32-x):
        for (a,b) in [((5,9),(0.5,5)),((4.5,13),(0,12)),((5,17),(0.5,19))]:
            s.poly([(X(a[0]),a[1]-1.2),(X(b[0]),b[1]),(X(a[0]),a[1]+1.2)],'gill','gill%s%s'%(a,X(0)))
    s.ell(16,26,8.5,5.5,'fur','body')
    s.ell(16,26.5,5,4,'belly','belly')
    for y in (24,27):
        for x in (14,15,16,17): 
            if (x+y)%2==0: F(s,x,y,'#B79CFF')
    pair(s,lambda X,k: s.ell(X(7.5),25,2,3.5,'wing','wing'+k))
    pair(s,lambda X,k: s.ell(X(12),30.3,2.6,1.4,'ring','foot'+k))
    s.ell(16,14,11,8.5,'fur','head')
    pair(s,lambda X,k: s.poly([(X(6),7),(X(7),2.5),(X(10.5),6)] if k=='L' else mp([(6,7),(7,2.5),(10.5,6)]),'fur','tuft'+k))
    pair(s,lambda X,k: s.ell(X(11.5),13.5,4.2,4.2,'ring','_ring'+k))
    pair(s,lambda X,k: s.ell(X(11.5),13.5,3.2,3.2,'belly','_ri'+k))
    if mood in ('idle','grin'):
        for lx in (10,19): 
            rowsF(s,lx,12,["WKK","KKK","KKI"],{'W':'#FFFFFF','K':'#141836','I':'#B9C6FF'})
    else: eyes(s,mood,10,11,3,4)
    rowsF(s,15,17,["BB",".B"[0:0]+"BB"],{'B':'#FF9F43'})
    rowsF(s,15,18,["BB"],{'B':'#E07A20'})
    blush(s,6,18); blush(s,24,18)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s)
    return s

def moko(mood):
    s=Sprite({'skin':'#5FD38A','belly':'#D9F7C7','spike':'#FF9FB2','shell':'#FFF6DE','spot':'#FFB3C7'})
    s.ell(16,15,10.5,9,'skin','head')
    s.ell(16,26,9,5,'skin','body')
    for x,y in [(16,4),(11,5),(21,5)]:
        s.poly([(x-1.8,y+1.8),(x,y-2.5),(x+1.8,y+1.8)],'spike','_sp%d'%x)

    s.ell(16,20,6,3.4,'belly','muzzle')
    eyes(s,mood,10,12,3,4,'#2FB86B')
    smile(s,mood,16,19)
    # eggshell base with zigzag rim
    s.ell(16,28,12,6,'shell','egg')
    for x in range(4,29):
        top=22 + (0 if x%4 in (0,1) else 2) if False else None
    zig=[(x, 23 if (x//2)%2==0 else 25) for x in range(4,29)]
    for x,yt in zig:
        for y in range(18,yt): s.px.pop((x,y),None) if s.px.get((x,y),(0,'x'))[1]=='egg' else None
    for x,y in [(8,27),(9,27),(22,26),(23,26),(15,29),(16,29)]: F(s,x,y,'#FFB3C7')
    pair(s,lambda X,k: s.ell(X(7),23,2,1.8,'skin','paw'+k))
    blush(s,7,17); blush(s,23,17)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s,'#FF9FB2')
    return s

def tank(mood):
    s=Sprite({'skin':'#98A3BE','horn':'#FFF1DC','jersey':'#5C6378','trim':'#C8F04A','ear':'#7E89A6','snout':'#B3BCD3'})
    s.ell(16,26.5,9.5,6,'jersey','body')
    for x in range(8,25):
        if s.px.get((x,21),(0,''))[1]=='body': s.px[(x,21)]=('trim','trim',None)
    rowsF(s,14,24,["N.NN","N..N","NNNN"][0:0]+["TTTT","..T.",".T..","TTTT"],{'T':'#C8F04A'})
    pair(s,lambda X,k: s.ell(X(6),26.5,2.7,3,'skin','arm'+k))
    pair(s,lambda X,k: s.rect(4 if k=='L' else 25,28,7 if k=='L' else 28,28,'trim','_wb'+k))
    pair(s,lambda X,k: s.ell(X(11.5),30.3,2.9,1.5,'skin','foot'+k))
    pair(s,lambda X,k: s.ell(X(6.5),7,2.4,3,'ear','ear'+k))
    s.ell(16,13.5,11.5,8.5,'skin','head')
    s.ell(16,17.5,7,4.2,'snout','snout')
    s.poly([(13.5,15.5),(16,6.5),(19,15.5)],'horn','horn')
    s.poly([(17.5,11),(19.5,7),(20.5,11.5)],'horn','_horn2') if False else None
    rowsF(s,12,18,["N......N"],{'N':'#2A2238'})
    for y in (7,8): F(s,7 if y==7 else 8,y,'#C9A0B0'); F(s,24 if y==7 else 23,y,'#C9A0B0')
    eyes(s,mood,7,11,3,4,'#5C6378')
    if mood!='sleepy': rowsF(s,6,10,["KKK"],{'K':'#55607C'}); rowsF(s,23,10,["KKK"],{'K':'#55607C'})
    if mood=='happy': rowsF(s,12,19,["KKKKKKKK",".KTTTTK."],{'K':MOUTH,'T':TONGUE})
    elif mood=='grin': rowsF(s,12,19,["KKKKKKKK","KWWWWWWK",".KKKKKK."],{'K':MOUTH,'W':'#FFFFFF'})
    elif mood=='meh': rowsF(s,14,20,["KKKK"],{'K':MOUTH})
    elif mood=='tired': rowsF(s,15,19,["KK","KK"],{'K':MOUTH})
    elif mood=='idle': rowsF(s,13,20,["K....K",".KKKK."],{'K':MOUTH})
    else: rowsF(s,15,20,["KK"],{'K':MOUTH})
    blush(s,5,16); blush(s,25,16)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s,'#C8F04A')
    return s

def volt(mood):
    s=Sprite({'skin':'#4FA8F5','belly':'#EAF5FF','fin':'#FFD447','side':'#3B8FD9'})
    s.poly([(24,24),(31,18),(30,25),(31,30),(24,28)],'side','tailfin')
    s.ell(16,15,12,9.5,'skin','head')
    s.ell(16,26,9,5.5,'skin','body')
    s.ell(16,21,9,6,'belly','belly')
    recolor(s,lambda x,y,v:v[1]=='belly' and y<17,'skin','head')
    rowsF(s,13,0,["...YY.","..YY..",".YYYY.","...YY.","..YY..","..Y..."],{'Y':'#FFD447'})
    pair(s,lambda X,k: s.poly([(X(6),23),(X(1),28),(X(8),27)] if k=='L' else mp([(6,23),(1,28),(8,27)]),'side','pec'+k))
    for x,y in [(5,15),(5,17),(26,15),(26,17)]: F(s,x,y,'#2C78C2'); F(s,x+(1 if x<16 else -1),y,'#2C78C2')
    eyes(s,mood,9,11,3,4,'#1FA2FF')
    if mood!='sleepy':
        F(s,8,10,'#2A4F8C'); F(s,9,9,'#2A4F8C'); F(s,23,10,'#2A4F8C'); F(s,22,9,'#2A4F8C')
    if mood in ('sleepy','meh'): rowsF(s,13,18,["KKKKKK"],{'K':'#2A4F8C'})
    elif mood=='tired': rowsF(s,13,17,["KKKKKK","KWKWKK"],{'K':'#1D2B55','W':'#FFFFFF'})
    elif mood=='idle': rowsF(s,11,17,["K........K",".KKKKKKKK."],{'K':'#1D2B55'})
    else:
        rowsF(s,11,17,["KKKKKKKKKK","KWKWKWKWKK" if mood=='idle' else "KWKWKWKWKK",".KTTTTTTK."[0:10] if mood=='happy' else ".KKKKKKKK."],{'K':'#1D2B55','W':'#FFFFFF','T':TONGUE})
    pair(s,lambda X,k: s.ell(X(12),30.3,2.6,1.4,'side','foot'+k))
    blush(s,7,16); blush(s,23,16)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s)
    return s

def howl(mood):
    s=Sprite({'fur':'#8E9BB8','muzzle':'#EEF0F7','hood':'#3A4A8C','lining':'#2A3466','string':'#FFFFFF','pocket':'#33427E'})
    s.ell(16,26.5,9.5,5.8,'hood','body')
    s.rect(11,26,20,28,'pocket','_pocket')
    pair(s,lambda X,k: s.ell(X(11.5),30.3,2.8,1.5,'lining','foot'+k))
    s.poly([(3,11),(6,1),(12,6)],'fur','earL'); s.poly(mp([(3,11),(6,1),(12,6)]),'fur','earR')
    s.poly([(5.5,7.5),(6.5,3.5),(9,5.5)],'muzzle','_eiL'); s.poly(mp([(5.5,7.5),(6.5,3.5),(9,5.5)]),'muzzle','_eiR')
    s.ell(16,14.5,12.5,9.5,'hood','hoodie')
    s.ell(16,15,9.5,7.5,'lining','_lin')
    s.ell(16,15,8.8,7,'fur','head')
    s.ell(16,18.5,5,3.2,'muzzle','muzzle')
    rowsF(s,15,16,["NN"],{'N':'#1E2033'})
    pair(s,lambda X,k: [F(s,int(X(12.5)) if k=='L' else 19,y,'#FFFFFF') for y in range(23,27)])
    eyes(s,mood,10,12,3,4,'#FFC94A')
    if mood!='sleepy':
        rowsF(s,9,11,["KK"],{'K':'#4A5675'}); rowsF(s,21,11,["KK"],{'K':'#4A5675'})
    smile(s,mood,16,18)
    blush(s,8,17); blush(s,22,17)
    if mood=='tired': sweat(s)
    if mood=='sleepy': zzz(s)
    if mood=='happy': spark(s)
    return s

CHARS={'Zib':zib,'Lox':lox,'Pip':pip,'Stash':stash,'Moko':moko,'Brick':brick,'Tank':tank,'Volt':volt,'Howl':howl}
