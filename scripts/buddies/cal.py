"""Cal: the calendar character (session 29). A friendly page-a-day calendar with a face, binder rings
for horns and stubby legs. Four moods: idle (a plain day), happy (everything done), sleepy (nothing
planned), alarm (something overdue). Same 48x48 pixel family as the buddies."""
from engine import Sprite
from face import eye, mouth, blush, place, INKC

STATES = ['idle', 'happy', 'sleepy', 'alarm']
GREEN = '#35C98B'

def cal(state):
    s = Sprite({'page': '#F4F6FF', 'band': '#FF5C7A', 'ring': '#9FB0FF', 'leg': '#9FB0FF'})
    for x in (18, 30):
        s.ell(x, 44, 3.2, 2.2, 'leg', f'leg{x}')
    # arms: down for calm moods, up for happy and alarmed
    up = state in ('happy', 'alarm')
    ay = 22 if up else 31
    s.ell(7, ay, 2.6, 3.4, 'page', 'aL'); s.ell(41, ay, 2.6, 3.4, 'page', 'aR')
    # page with softly rounded corners, red header band
    s.rect(9, 9, 38, 42, 'page', 'body')
    for (x, y) in [(9, 9), (38, 9), (9, 42), (38, 42), (10, 9), (9, 10), (37, 9), (38, 10), (9, 41), (10, 42), (38, 41), (37, 42)]:
        s.erase(x, y)
    s.rect(10, 9, 37, 16, 'band', 'band')
    # binder rings
    for x in (17, 30):
        s.rect(x, 5, x + 1, 11, 'ring', f'ring{x}')
    # faint date dots along the bottom
    for x in range(13, 36, 4):
        s.F(x, 38, '#D5DBEE', '_dot'); s.F(x, 40, '#D5DBEE', '_dot')
    skin = ('page', 'body')
    if state == 'happy':
        eye(s, 14, 21, 5, 5, 'ecstatic', None, -1, skin); eye(s, 28, 21, 5, 5, 'ecstatic', None, 1, skin)
        mouth(s, 24, 30, 'happy')
        blush(s, 11, 33, 29, 'happy')
        # a green check badge on the band
        s.rowsF(29, 10, ["........G", ".......GG", "G.....GG.", "GG...GG..", ".GG.GG...", "..GGG....", "...G....."], {'G': '#FFFFFF'})
    elif state == 'sleepy':
        eye(s, 14, 21, 5, 5, 'sleepy', None, -1, skin); eye(s, 28, 21, 5, 5, 'sleepy', None, 1, skin)
        mouth(s, 24, 30, 'sleepy')
        blush(s, 11, 33, 29, 'sleepy')
        s.rowsF(40, 4, ["ZZZZ", "..Z.", ".Z..", "ZZZZ"], {'Z': '#9FB0FF'})
    elif state == 'alarm':
        eye(s, 14, 21, 5, 6, 'hungry', '#3F7BFF', -1, skin)       # wide, wet, worried eyes
        eye(s, 28, 21, 5, 6, 'hungry', '#3F7BFF', 1, skin)
        for i in range(4):                                       # brows slanting up toward the middle
            s.F(14 + i, 19 - (i * 2) // 3, INKC); s.F(32 - i, 19 - (i * 2) // 3, INKC)
        mouth(s, 24, 30, 'sad')
        s.rowsF(41, 6, [".D.", "DDD", "DWD", ".D."], {'D': '#7FD3FF', 'W': '#FFFFFF'})
        s.rowsF(31, 10, ["..W..", "..W..", "..W..", ".....", "..W.."], {'W': '#FFFFFF'})   # a "!" on the band
    else:
        eye(s, 14, 21, 5, 5, 'content', None, -1, skin); eye(s, 28, 21, 5, 5, 'content', None, 1, skin)
        mouth(s, 24, 30, 'content')
        blush(s, 11, 33, 29, 'content')
    return s
