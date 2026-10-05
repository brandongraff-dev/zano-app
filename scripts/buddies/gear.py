"""Buddy gear: earned (never sold) accessories drawn as overlays on top of any face.

Each buddy has its own anchors: where a hat sits (centre x, the row its brim rests on) and where its
eyes are (for the shades). `low` is the head position in the slumped faces (drained, sad), which only
moves Moko's head.
"""
from engine import Sprite

GEAR = ['partyHat', 'shades', 'beanie', 'crown', 'cape', 'jetpack', 'diamond']
# Gear drawn BEHIND the buddy (the rest is drawn over it).
UNDER = {'cape', 'jetpack'}

# name -> hat (cx, base_y), eyes (left x, right x, y, w, h); low-variant tweaks in LOW.
ANCHORS = {
    'Stash': ((24, 9), (14, 29, 17, 5, 6)),
    'Zib':   ((24, 22), (15, 29, 27, 4, 6)),
    'Lox':   ((24, 10), (15, 28, 15, 6, 4)),
    'Pip':   ((24, 12), (15, 28, 19, 6, 6)),
    'Moko':  ((24, 11), (15, 28, 17, 5, 6)),
    'Brick': ((24, 9), (14, 30, 15, 5, 5)),
    'Tank':  ((24, 9), (12, 31, 15, 5, 5)),
    'Volt':  ((15, 15), (14, 29, 17, 5, 5)),
    'Howl':  ((24, 9), (16, 27, 19, 5, 5)),
}
LOW = {'Moko': 2}   # rows the head drops in the slumped faces

# name -> body (centre x, shoulder row, half width) for gear worn on the body (cape, jetpack).
BODY = {
    'Stash': (22, 31, 10), 'Zib': (24, 25, 15), 'Lox': (23, 28, 8), 'Pip': (24, 24, 13),
    'Moko': (24, 31, 15), 'Brick': (24, 33, 13), 'Tank': (24, 32, 12), 'Volt': (24, 24, 15),
    'Howl': (24, 33, 12),
}

def rowsR(s, x0, y0, rows, key):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch in key:
                r, part = key[ch]
                s.put(x0 + i, y0 + j, r, part)

PARTY = ["....w....", "...www...", "....p....", "...pyp...", "...ypy...", "..pypyp..", "..ypypy..", ".pypypyp.", "bbbbbbbbb"]
BEANIE = ["......www......", ".....wwwww.....", "....bbbbbbb....", "..bbbbbbbbbbb..", ".bbbbbbbbbbbbb.",
          "bbbbbbbbbbbbbbb", "ccccccccccccccc", "ccccccccccccccc"]
DIAMOND = ["..ddddd..", ".dwwdddd.", "dwdddddde", ".ddddddde", "..dddde..", "...dde...", "....e...."]
CROWN = ["g.....g.....g", "gg...ggg...gg", "ggg.ggggg.ggg", "ggggggggggggg", "ggrgggbgggrgg", "ggggggggggggg"]

def overlay(name, gear, low=False):
    s = Sprite({'white': '#F4F6FF', 'pink': '#FF6F91', 'sun': '#FFD447', 'band': '#3F7BFF',
                'beanie': '#3F7BFF', 'cuff': '#7FA6FF', 'gold': '#FFC94A', 'ruby': '#FF5C7A',
                'gem': '#5BC8FF', 'lens': '#1E1A3A', 'cape': '#E5484D', 'capeIn': '#9C2F4E',
                'metal': '#B9C2D6', 'flame': '#FF8A3D'})
    (hx, hy), (lx, rx, ey, ew, eh) = ANCHORS[name]
    d = LOW.get(name, 0) if low else 0
    hy += d
    ey += d
    if gear == 'partyHat':
        rowsR(s, hx - 4, hy - len(PARTY) + 1, PARTY,
              {'w': ('white', '_pom'), 'p': ('pink', '_p'), 'y': ('sun', '_y'), 'b': ('band', '_band')})
    elif gear == 'beanie':
        rowsR(s, hx - 7, hy - len(BEANIE) + 1, BEANIE,
              {'w': ('white', '_pom'), 'b': ('beanie', 'beanie'), 'c': ('cuff', 'cuff')})
    elif gear == 'crown':
        rowsR(s, hx - 6, hy - len(CROWN) + 1, CROWN,
              {'g': ('gold', 'crown'), 'r': ('ruby', '_r'), 'b': ('gem', '_g')})
    elif gear == 'diamond':
        rowsR(s, hx - 4, hy - len(DIAMOND) - 1, DIAMOND,
              {'d': ('gem', 'diamond'), 'w': ('white', '_shine'), 'e': ('lens', '_edge')})
    elif gear == 'cape':
        cx, sy, hw = BODY[name]
        s.poly([(cx - hw + 1, sy), (cx + hw - 1, sy), (cx + hw + 6, 47), (cx - hw - 6, 47)], 'cape', 'cape')
        s.poly([(cx - hw + 3, sy + 3), (cx + hw - 3, sy + 3), (cx + hw + 3, 47), (cx - hw - 3, 47)], 'capeIn', '_in')
    elif gear == 'jetpack':
        cx, sy, hw = BODY[name]
        for tx in (cx - hw - 5, cx + hw):
            rowsR(s, tx, sy - 4, [".rrr.", "rrrrr", "mmmmm", "mmwmm", "mmwmm", "mmmmm", "mmmmm", "mmmmm", "mmmmm", "mmmmm", ".kkk."],
                  {'r': ('band', '_cap'), 'm': ('metal', 'tank'), 'w': ('white', '_glint'), 'k': ('lens', '_nozzle')})
            rowsR(s, tx, sy + 7, [".fff.", "ffyff", ".fyf.", ".fyf.", "..f.."], {'f': ('flame', '_fl'), 'y': ('sun', '_fy')})
    elif gear == 'shades':
        lh = max(4, eh - 1)
        for x0 in (lx - 1, rx - 1):
            for j in range(lh):
                for i in range(ew + 2):
                    if j == lh - 1 and i in (0, ew + 1):
                        continue
                    s.put(x0 + i, ey + j, None, '_lens', (30, 26, 58))
            s.put(x0 + 1, ey + 1, None, '_glint', (255, 255, 255))
            s.put(x0 + 2, ey + 1, None, '_glint', (255, 255, 255))
            s.put(x0 + 1, ey + 2, None, '_glint', (200, 210, 255))
        for x in range(lx + ew + 1, rx - 1):
            s.put(x, ey + 1, None, '_bridge', (30, 26, 58))
    return s
