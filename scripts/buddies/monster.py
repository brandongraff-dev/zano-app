"""The Scroll Monster: the weekly boss. A grumpy phone-shaped blob with a face on its screen and
notification bubbles for horns. Three states (healthy, hurt, defeated) x three colour variants,
one variant per week so the boss changes."""
from engine import Sprite

VARIANTS = [
    {'case': '#7A4FE0', 'screen': '#2A1F4D', 'glow': '#B8F06A'},   # violet
    {'case': '#2FA36B', 'screen': '#16302A', 'glow': '#FFD447'},   # green
    {'case': '#E2603A', 'screen': '#3A1A22', 'glow': '#7FD3FF'},   # orange
]
STATES = ['healthy', 'hurt', 'defeated']

def monster(state, variant=0):
    v = VARIANTS[variant]
    s = Sprite({'case': v['case'], 'leg': v['case'], 'screen': v['screen'], 'bubble': '#FF5C7A', 'white': '#F4F6FF'})
    # stubby legs and arms
    for x in (15, 29):
        s.ell(x + 2, 44.5, 3.2, 2.2, 'leg', f'leg{x}')
    if state == 'defeated':
        s.ell(5, 34, 2.6, 2.6, 'leg', 'aL'); s.ell(43, 34, 2.6, 2.6, 'leg', 'aR')
    else:
        s.ell(6, 24, 2.8, 2.8, 'leg', 'aL'); s.ell(42, 24, 2.8, 2.8, 'leg', 'aR')
        s.rect(7, 25, 10, 27, 'leg', 'aL'); s.rect(38, 25, 41, 27, 'leg', 'aR')
    # phone body
    s.rect(10, 6, 38, 43, 'case', 'body')
    for (x, y) in [(10, 6), (38, 6), (10, 43), (38, 43), (11, 6), (10, 7), (37, 6), (38, 7), (10, 42), (11, 43), (38, 42), (37, 43)]:
        s.erase(x, y)
    s.rect(13, 10, 35, 38, 'screen', 'screen')
    s.rect(21, 7, 27, 8, 'screen', '_speaker')
    s.ell(24, 41, 1.6, 1.2, 'screen', '_home')
    # notification-bubble horns
    if state != 'defeated':
        for x in (11, 35):
            s.ell(x + 1, 4.5, 3.4, 3.2, 'bubble', f'h{x}')
            s.F(x + 1, 3, '#FFFFFF'); s.F(x + 1, 4, '#FFFFFF'); s.F(x + 1, 6, '#FFFFFF')
    glow = v['glow']
    if state == 'healthy':   # angry eyes, toothy grin
        s.rowsF(15, 15, ["G.....", "GG....", "GGGG..", ".GGGG."], {'G': glow})
        s.rowsF(27, 15, [".....G", "....GG", "..GGGG", ".GGGG."], {'G': glow})
        s.rowsF(16, 26, ["GGGGGGGGGGGGGGGG", "G.G.G.G.G.G.G.GG", "GGGGGGGGGGGGGGGG"][0:0] + ["GGGGGGGGGGGGGGG", "GWGWGWGWGWGWGWG", ".GGGGGGGGGGGGG."], {'G': glow, 'W': '#FFFFFF'})
    elif state == 'hurt':    # one eye squeezed, wobbly mouth, cracked screen, sweat
        s.rowsF(15, 16, ["GGGG..", ".GGGG.", "..GG.."], {'G': glow})
        s.rowsF(27, 16, ["G....G", ".G..G.", "..GG..", ".G..G."], {'G': glow})
        s.rowsF(17, 28, [".GG..GG..GG..", "G..GG..GG..G."], {'G': glow})
        for (x, y) in [(30, 11), (29, 12), (29, 13), (28, 14), (31, 13), (32, 14)]:
            s.F(x, y, '#D9E2FF')
        s.rowsF(40, 10, [".D.", "DDD", "DWD", ".D."], {'D': '#7FD3FF', 'W': '#FFFFFF'})
    else:                    # X eyes, tongue out, cracked screen, dizzy stars
        for (x0) in (16, 27):
            s.rowsF(x0, 15, ["G...G", ".G.G.", "..G..", ".G.G.", "G...G"], {'G': glow})
        s.rowsF(19, 27, ["GGGGGGGGGG", "....TTT...", "....TTT...", ".....T...."], {'G': glow, 'T': '#FF7A93'})
        for (x, y) in [(14, 12), (15, 13), (16, 13), (17, 14), (33, 30), (32, 31), (31, 31), (30, 32), (31, 33)]:
            s.F(x, y, '#D9E2FF')
        for (x, y) in [(9, 2), (24, 1), (39, 2)]:
            s.rowsF(x - 1, y, [".Y.", "YWY", ".Y."], {'Y': '#FFD447', 'W': '#FFFFFF'})
    return s
