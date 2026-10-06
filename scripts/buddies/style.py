"""Buddy style items (session 15): the shop's cosmetics. Everything here is cosmetic and bought with
coins; nothing changes what a goal or a lock does (CLAUDE.md, spec §5.17).

  * SKINS: eight colourways per buddy, applied at runtime by remapping the buddy's main fur ramp
    (a four-colour table per buddy/skin, so no extra sprites).
  * HATS / EYEWEAR / NECK / BACK: overlays drawn over (or, for BACK, behind) any face, one sprite per
    buddy and item, placed with gear.py's anchors plus NECK below.
  * BACKDROPS: shared 48x48 scenes drawn behind the buddy.
"""
import colorsys
from engine import Sprite, ramp, hx, tohex, N
import gear as G
from gear import ANCHORS, BODY, LOW

# ---------------------------------------------------------------- skins
MAIN_RAMP = {'Stash': 'fur', 'Zib': 'fur', 'Lox': 'fur', 'Pip': 'body', 'Moko': 'skin', 'Brick': 'fur',
             'Tank': 'skin', 'Volt': 'skin', 'Howl': 'fur'}
# name -> (hue degrees, saturation, lightness) of the new base colour
SKINS = {
    'midnight':  (245, 0.45, 0.30),
    'sunset':    (14, 0.85, 0.58),
    'mint':      (158, 0.55, 0.62),
    'bubblegum': (330, 0.80, 0.72),
    'gold':      (44, 0.90, 0.58),
    'ghost':     (230, 0.12, 0.88),
    'lava':      (6, 0.88, 0.42),
    'galaxy':    (276, 0.70, 0.46),
}
SKIN_ORDER = list(SKINS)

def skin_base(skin):
    h, s, l = SKINS[skin]
    r, g, b = colorsys.hls_to_rgb(h / 360, l, s)
    return '#%02X%02X%02X' % (round(r * 255), round(g * 255), round(b * 255))

def desat(c, k=0.4):
    """What engine.Sprite.render does to every colour of a drained face."""
    g = sum(c) / 3
    return tuple(round((c[i] * (1 - k) + g * k) * 0.9) for i in range(3))

def main_base(buddy):
    """The buddy's main body colour, read from its own sprite so the skin table can never drift from the art."""
    import buddies
    r = buddies.B[buddy]('content').R[MAIN_RAMP[buddy]]['b']
    return '#%02X%02X%02X' % r

def skin_table(buddy, base_hex, skin):
    """[(orig, new)] for the four shades of the buddy's main ramp, normal then drained."""
    old, new = ramp(base_hex), ramp(skin_base(skin))
    pairs = [(old[t], new[t]) for t in ('hi', 'b', 'sh', 'dk')]
    return pairs, [(desat(o), desat(n)) for o, n in pairs]

# ---------------------------------------------------------------- overlays
def S():
    return Sprite({})

def F(s, x, y, c, part='_f'):
    s.F(x, y, c, part)

def art(s, x0, y0, rows, key, part='_a'):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch in key:
                s.F(x0 + i, y0 + j, key[ch], part + ch)

HATS = {
    'cap': ([
        "....rrrrr....",
        "..rrrrrrrrr..",
        ".rrrrrwrrrrr.",
        "rrrrrrrrrrrrr",
        "wwwwwwwwwwwww",
        ".bbbbbbbbbbb."], {'r': '#E5484D', 'w': '#F4F6FF', 'b': '#B03238'}),
    'wizard': ([
        ".....pp.....",
        "....pppp....",
        "....ppyp....",
        "...pppppp...",
        "...pypppp...",
        "..pppppppp..",
        "..ppppypp...",
        ".pppppppppp.",
        "gggggggggggg",
        "bbbbbbbbbbbbb"], {'p': '#7A4FE0', 'y': '#FFD447', 'g': '#FFC94A', 'b': '#5B3AB0'}),
    'chef': ([
        "..ww.ww.ww..",
        ".wwwwwwwwwww",
        "wwwwwwwwwwww",
        "wwwwwwwwwwww",
        ".wwwwwwwwww.",
        ".cccccccccc."], {'w': '#FFFFFF', 'c': '#D9DEF0'}),
    'cowboy': ([
        "...bbbbb...",
        "..bbbbbbb..",
        "..bkkkkkb..",
        "..bbbbbbb..",
        "bbbbbbbbbbbbb",
        "bbbbbbbbbbbbb"], {'b': '#A8672B', 'k': '#5C3A18'}),
    'tophat': ([
        "..kkkkkkk..",
        "..kkkkkkk..",
        "..kkkkkkk..",
        "..rrrrrrr..",
        "..kkkkkkk..",
        "kkkkkkkkkkkkk"], {'k': '#2A2D42', 'r': '#E5484D'}),
    'halo': ([
        "..yyyyyy..",
        ".y......y.",
        "..yyyyyy.."], {'y': '#FFE27A'}),
    'headband': ([
        "rrrrrrrrrrrrrrr",
        "wwwwwwwwwwwwwww"], {'r': '#E5484D', 'w': '#FFFFFF'}),
    'santa': ([
        "........ww",
        "......rrww",
        "....rrrrr.",
        "..rrrrrrr.",
        ".rrrrrrrrr",
        "wwwwwwwwwww"], {'r': '#E5484D', 'w': '#FFFFFF'}),
    'pirate': ([
        "....kkkkk....",
        "..kkkwwwkkk..",
        ".kkkkwkwkkkk.",
        "kkkkkkkkkkkkk",
        "rrrrrrrrrrrrr"], {'k': '#23263A', 'w': '#F4F6FF', 'r': '#E5484D'}),
    'flowers': ([
        "p.y.p.y.p",
        "ggggggggg"], {'p': '#FF8FB7', 'y': '#FFD447', 'g': '#4FC46B'}),
}
HAT_ORDER = list(HATS)

def hat_sprite(name, item, low):
    (hx_, hy), _ = ANCHORS[name]
    hy += LOW.get(name, 0) if low else 0
    rows, key = HATS[item]
    w = max(len(r) for r in rows)
    s = S()
    art(s, hx_ - w // 2, hy - len(rows) + 1, rows, key)
    return s

def eye_sprite(name, item, low):
    _, (lx, rx, ey, ew, eh) = ANCHORS[name]
    ey += LOW.get(name, 0) if low else 0
    s = S()
    ink, gold = '#1E1A3A', '#FFC94A'
    for x0 in (lx, rx):
        if item == 'roundGlasses':
            w, h = ew + 2, eh + 2
            for i in range(w):
                for j in range(h):
                    edge = i in (0, w - 1) or j in (0, h - 1)
                    corner = i in (0, w - 1) and j in (0, h - 1)
                    if edge and not corner:
                        s.F(x0 - 1 + i, ey - 1 + j, gold, '_rg')
        elif item == 'heartShades':
            for k, row in enumerate([".XX.XX.", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]):
                for i, ch in enumerate(row):
                    if ch == 'X': s.F(x0 + (ew - 7) // 2 + i, ey - 1 + k, '#FF4F7B', '_hs')
            s.F(x0 + (ew - 7) // 2 + 1, ey, '#FFC2D1', '_hg')
        elif item == 'starShades':
            for k, row in enumerate(["..Y..", ".YYY.", "YYYYY", ".YYY.", "..Y.."]):
                for i, ch in enumerate(row):
                    if ch == 'Y': s.F(x0 + (ew - 5) // 2 + i, ey - 1 + k, '#FFD447', '_ss')
        elif item == 'goggles':
            for i in range(ew + 2):
                for j in range(eh + 2):
                    s.F(x0 - 1 + i, ey - 1 + j, '#8BE9FF' if 0 < i < ew + 1 and 0 < j < eh + 1 else '#3F7BFF', '_gg')
            s.F(x0, ey, '#FFFFFF', '_gl')
    if item == 'goggles':
        for x in range(lx + ew + 1, rx - 1): s.F(x, ey + eh // 2, '#3F7BFF', '_gb')
        for x in range(max(0, lx - 5), lx - 1): s.F(x, ey + eh // 2, '#3F7BFF', '_gs')
        for x in range(rx + ew + 1, min(48, rx + ew + 5)): s.F(x, ey + eh // 2, '#3F7BFF', '_gs')
    elif item == 'roundGlasses':
        for x in range(lx + ew + 1, rx - 1): s.F(x, ey + eh // 2, gold, '_rb')
    return s

# (centre x, row) of the neck line for each buddy: the chin, or just below the mouth on the blobs
NECK = {'Stash': (23, 31), 'Zib': (24, 38), 'Lox': (24, 29), 'Pip': (24, 36), 'Moko': (24, 33),
        'Brick': (24, 31), 'Tank': (24, 31), 'Volt': (24, 37), 'Howl': (24, 33)}
NECKS = {
    'bowtie': ([
        "RR...RR",
        "RRRRRRR",
        "RR.K.RR",
        "RR...RR"], {'R': '#E5484D', 'K': '#8E2A30'}),
    'scarf': ([
        "bbbbbbbbbbbbbbb",
        "wwwwwwwwwwwwwww",
        "...bb..........",
        "...bb..........",
        "...ww..........",
        "...bb.........."], {'b': '#3F7BFF', 'w': '#F4F6FF'}),
    'bandana': ([
        "rrrrrrrrrrrrr",
        "rwrwrwrwrwrwr",
        ".rrrrrrrrrrr.",
        "..rwrwrwrwr..",
        "....rrrrr....",
        ".....rwr.....",
        "......r......"], {'r': '#E5484D', 'w': '#FFE0E0'}),
    'goldChain': ([
        "y.y.y.y.y.y.y.y",
        ".y.y.y.y.y.y.y.",
        "..y.y.y.y.y.y..",
        "....y.y.y.y....",
        ".....yyyyy.....",
        "......ggg......",
        "......ggg......"], {'y': '#FFC94A', 'g': '#5BC8FF'}),
    'collarBell': ([
        "rrrrrrrrrrrrr",
        ".....yyy.....",
        ".....yky.....",
        ".....yyy....."], {'r': '#E5484D', 'y': '#FFD447', 'k': '#8A5A00'}),
    'tie': ([
        "kkk",
        "bbb",
        ".b.",
        "bbb",
        "bbb",
        "bbb",
        ".b."], {'k': '#23263A', 'b': '#3F7BFF'}),
}
NECK_ORDER = list(NECKS)

def neck_sprite(name, item):
    cx, y = NECK[name]
    rows, key = NECKS[item]
    w = max(len(r) for r in rows)
    s = S()
    art(s, cx - w // 2, y, rows, key)
    return s

BACKS = ['angelWings', 'batWings', 'butterflyWings', 'dragonWings', 'leafWings', 'backpack']

def flat(s, x, y, color):
    if 0 <= x < N and 0 <= y < N:
        s.px[(x, y)] = (None, '_w' + color, hx(color))

def tilted(s, cx, cy, rx, ry, deg, color, clip=None):
    """A filled ellipse rotated by `deg`, in a flat colour."""
    import math
    c, sn = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    for y in range(N):
        for x in range(N):
            dx, dy = x + .5 - cx, y + .5 - cy
            u, v = dx * c + dy * sn, -dx * sn + dy * c
            if (u / rx) ** 2 + (v / ry) ** 2 <= 1 and (clip is None or clip(x, y)):
                flat(s, x, y, color)

def back_sprite(name, item):
    s = S()
    cx, sy, hw = BODY[name]
    if item == 'backpack':
        for y in range(sy - 2, sy + 13):
            for x in range(cx - hw - 3, cx + hw + 4):
                edge = y in (sy - 2, sy + 12) and (x < cx - hw - 1 or x > cx + hw + 2)
                if not edge: flat(s, x, y, '#E58F2B')
        for x in range(cx - hw - 3, cx + hw + 4): flat(s, x, sy + 9, '#B96A12')
        for sd in (-1, 1):
            for y in range(sy + 2, sy + 8):
                for x in range(cx + sd * (hw + 1) - 1, cx + sd * (hw + 1) + 2): flat(s, x, y, '#FFE0B0')
        return s
    for side in (-1, 1):
        ox = cx + side * (hw + 5)
        if item == 'angelWings':
            tilted(s, ox, sy - 6, 6.5, 13, side * -25, '#F4F6FF')
            tilted(s, ox + side * 2, sy - 1, 5, 9, side * -25, '#DDE3F5')
            for k in range(4): flat(s, ox + side * (k + 1), sy + 7 - k, '#C0C9E4')
        elif item == 'batWings':
            tilted(s, ox, sy - 7, 8, 11, side * -35, '#6B4AA8')
            for k in (-1, 0, 1):
                tilted(s, ox + side * 4 + k * side * 3, sy + 3, 3, 4.5, 0, '#6B4AA8')
            tilted(s, ox, sy - 7, 3, 7, side * -35, '#8A68C8')
        elif item == 'butterflyWings':
            tilted(s, ox + side * 1, sy - 8, 8, 10, side * -30, '#FF8FB7')
            tilted(s, ox, sy + 2, 6, 6, side * 25, '#FFB3CF')
            tilted(s, ox + side * 2, sy - 9, 2.2, 2.2, 0, '#FFD447')
            tilted(s, ox, sy + 2, 1.8, 1.8, 0, '#FFD447')
        elif item == 'dragonWings':
            tilted(s, ox, sy - 6, 7.5, 12, side * -30, '#4FC46B')
            for k in range(3):
                tilted(s, ox + side * (3 + k * 3), sy + 4, 2.4, 4, 0, '#4FC46B')
            tilted(s, ox, sy - 6, 2.2, 8, side * -30, '#2B8A45')
            flat(s, ox + side * 8, sy - 17, '#2B8A45'); flat(s, ox + side * 9, sy - 18, '#2B8A45')
        elif item == 'leafWings':
            tilted(s, ox, sy - 4, 5.5, 13, side * -28, '#7CC21B')
            tilted(s, ox, sy - 4, 1.0, 11, side * -28, '#4E8A0E')
    return s

# ---------------------------------------------------------------- items
HAT_NAMES = HAT_ORDER
EYE_ORDER = ['roundGlasses', 'heartShades', 'starShades', 'goggles']
ITEMS = ([('hat', i) for i in HAT_ORDER] + [('eyewear', i) for i in EYE_ORDER] +
         [('neck', i) for i in NECK_ORDER] + [('back', i) for i in BACKS])

def overlay(buddy, slot, item, low=False):
    if slot == 'hat': return hat_sprite(buddy, item, low)
    if slot == 'eyewear': return eye_sprite(buddy, item, low)
    if slot == 'neck': return neck_sprite(buddy, item)
    return back_sprite(buddy, item)

# ---------------------------------------------------------------- backdrops (shared 48x48 scenes)
def _bands(s, top, bottom, colors, y0=0):
    n = len(colors); h = bottom - top
    for y in range(top, bottom):
        c = colors[min(n - 1, (y - top) * n // max(1, h))]
        for x in range(N): s.F(x, y, c, '_bd')

def _circle(s, cx, cy, r, c):
    for y in range(N):
        for x in range(N):
            if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r: s.F(x, y, c, '_bd')

def _rect(s, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < N and 0 <= y < N: s.F(x, y, c, '_bd')

def _dots(s, pts, c):
    for x, y in pts: s.F(x, y, c, '_bd')

BACKDROPS = ['sunrise', 'gym', 'forest', 'space', 'beach', 'city', 'snow', 'candy', 'library', 'arcade']

def backdrop(kind):
    s = S()
    if kind == 'sunrise':
        _bands(s, 0, 34, ['#2A2F6B', '#5B4B9A', '#B65F9E', '#F2866B', '#FFB070', '#FFD38A'])
        _circle(s, 24, 34, 11, '#FFE9A8'); _rect(s, 0, 34, 47, 47, '#2D3B63')
        _rect(s, 0, 36, 47, 37, '#3B4B7A'); _dots(s, [(5, 6), (12, 3), (36, 5), (42, 9), (28, 2)], '#FFFFFF')
    elif kind == 'gym':
        _rect(s, 0, 0, 47, 47, '#2B2F4E'); _rect(s, 0, 36, 47, 47, '#6B4A32'); _rect(s, 0, 35, 47, 35, '#8A6445')
        for x in range(0, 48, 6): _rect(s, x, 36, x, 47, '#59392A')
        _rect(s, 4, 10, 20, 11, '#9AA3C2'); _rect(s, 2, 8, 3, 13, '#5A6388'); _rect(s, 21, 8, 22, 13, '#5A6388')
        _rect(s, 30, 14, 44, 30, '#3B4070'); _rect(s, 31, 15, 43, 29, '#232744'); _rect(s, 33, 22, 41, 23, '#B8FF3C')
    elif kind == 'forest':
        _bands(s, 0, 40, ['#8FD3F4', '#B5E3F7', '#D8F1FA'])
        for x0, h in ((2, 20), (14, 26), (30, 22), (41, 28)):
            _rect(s, x0 + 2, 40 - 8, x0 + 3, 40, '#6B4A32')
            for k in range(h // 3):
                w = 2 + k; _rect(s, x0 + 3 - w, 40 - 8 - k * 3 - 2, x0 + 2 + w, 40 - 8 - k * 3, '#2F8F4E' if k % 2 else '#3FAF5E')
        _rect(s, 0, 40, 47, 47, '#4FA44A'); _rect(s, 0, 40, 47, 40, '#6CC25E')
    elif kind == 'space':
        _bands(s, 0, 48, ['#0A0B24', '#14123A', '#1D1650'])
        _dots(s, [(4, 5), (11, 12), (20, 4), (33, 9), (41, 3), (44, 18), (7, 26), (38, 30), (16, 37), (30, 41), (3, 43), (25, 20)], '#FFFFFF')
        _circle(s, 38, 10, 6, '#FF9F5B'); _circle(s, 36, 8, 3, '#FFC48A'); _rect(s, 30, 10, 46, 10, '#FFC48A')
        _circle(s, 8, 40, 5, '#5BC8FF')
    elif kind == 'beach':
        _bands(s, 0, 28, ['#6EC6FF', '#9BDDFF', '#C8EEFF']); _rect(s, 0, 28, 47, 34, '#3FA9F5')
        _rect(s, 0, 28, 47, 28, '#B8E8FF'); _rect(s, 0, 35, 47, 47, '#F4D58D'); _circle(s, 38, 10, 5, '#FFE27A')
        _rect(s, 7, 20, 8, 36, '#8A5A2B'); _rect(s, 3, 18, 12, 19, '#2F9F55'); _rect(s, 5, 16, 10, 17, '#3FBF6B')
    elif kind == 'city':
        _bands(s, 0, 48, ['#14123A', '#2A2158', '#5B3B8C', '#B65F9E'])
        for x0, w, h in ((0, 8, 20), (9, 7, 28), (17, 9, 16), (27, 7, 30), (35, 6, 22), (42, 6, 26)):
            _rect(s, x0, 48 - h, x0 + w - 1, 47, '#1A1B3D')
            for yy in range(48 - h + 2, 46, 4):
                for xx in range(x0 + 1, x0 + w - 1, 3):
                    if (xx + yy) % 2 == 0: _rect(s, xx, yy, xx, yy + 1, '#FFD447')
        _dots(s, [(6, 4), (22, 8), (40, 5)], '#FFFFFF')
    elif kind == 'snow':
        _bands(s, 0, 36, ['#7BA8D8', '#A9C7E8', '#DCEBFA']); _rect(s, 0, 36, 47, 47, '#F4F8FF')
        _rect(s, 0, 36, 47, 36, '#FFFFFF')
        for x0, h in ((6, 8), (38, 10)):
            for k in range(h // 2): _rect(s, x0 - k, 34 - h + k * 2, x0 + k, 35 - h + k * 2, '#2F6F5E')
        _dots(s, [(4, 5), (10, 14), (18, 7), (26, 18), (34, 9), (43, 16), (14, 26), (30, 28), (40, 24)], '#FFFFFF')
    elif kind == 'candy':
        _bands(s, 0, 48, ['#FFD6EC', '#FFC2E0', '#FFB3D6'])
        for i, c in enumerate(['#FF5C8A', '#FFD447', '#5BC8FF', '#7CC21B', '#B36BFF']):
            _circle(s, 6 + i * 9, 10 + (i % 2) * 6, 3, c)
        _rect(s, 0, 38, 47, 47, '#FFF1B8')
        for x in range(0, 48, 4): _rect(s, x, 38, x + 1, 39, '#FF8FB7' if (x // 4) % 2 else '#FFFFFF')
    elif kind == 'library':
        _rect(s, 0, 0, 47, 47, '#4B3326')
        for y0 in (4, 16, 28):
            _rect(s, 0, y0 + 9, 47, y0 + 10, '#2E1F17')
            x = 1
            for k, c in enumerate(['#E5484D', '#3F7BFF', '#FFD447', '#4FC46B', '#B36BFF', '#FF8A2B'] * 3):
                w = 2 + (k % 3); h = 6 + (k % 4)
                if x + w > 46: break
                _rect(s, x, y0 + 9 - h, x + w - 1, y0 + 8, c); x += w + 1
        _rect(s, 0, 40, 47, 47, '#6B4A32')
    elif kind == 'arcade':
        _rect(s, 0, 0, 47, 47, '#12122E')
        for x in range(0, 48, 6): _rect(s, x, 0, x, 47, '#1E1E4A')
        for y in range(0, 48, 6): _rect(s, 0, y, 47, y, '#1E1E4A')
        _rect(s, 5, 8, 15, 18, '#FF4F7B'); _rect(s, 33, 8, 43, 18, '#2DB7F5'); _rect(s, 19, 5, 29, 11, '#B8FF3C')
        _dots(s, [(8, 11), (9, 11), (37, 13), (38, 13), (22, 8), (26, 8)], '#FFFFFF'); _rect(s, 0, 40, 47, 47, '#2A2A5E')
    return s
