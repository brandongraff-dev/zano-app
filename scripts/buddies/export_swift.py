"""Exports the buddy sprites (buddies.py) to Core as Swift pixel data (and a self-contained copy
for the watch app, Watch/ZANOWatch/Generated), plus the app icon.

Run from the repo root:  python3 scripts/buddies/export_swift.py  [--sprites-only]
Needs Pillow only for the app icon. The Swift file is generated; edit buddies.py / face.py, not the
output. 48x48 pixels, eight faces per buddy (see face.EXPRS).
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import buddies
from engine import N

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(ROOT, 'Core/Sources/Core/UI/Buddy/BuddySprites.swift')
KEYS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-/:;<=>?@[]^_`{|}~'
ORDER = ['stash', 'zib', 'lox', 'pip', 'moko', 'brick', 'tank', 'volt', 'howl']
# Swift case name -> art expression. `idle` is the content face.
POSES = [('idle', 'content'), ('sleepy', 'sleepy'), ('happy', 'happy'), ('drained', 'drained'),
         ('sad', 'sad'), ('meh', 'meh'), ('excited', 'excited'), ('ecstatic', 'ecstatic')] + \
    [(e, e) for e in ('lifting', 'flexing', 'sipping', 'thirsty', 'eating', 'hungry', 'focused', 'yawning', 'proud', 'lovey',
                      'blaze', 'frozen', 'guarding', 'tinkering', 'analyzing')]

def encode(img):
    pal, rows = [], []
    for y in range(N):
        row = ''
        for x in range(N):
            c = img.get((x, y))
            if c is None:
                row += '.'
                continue
            if c not in pal:
                pal.append(c)
            row += KEYS[pal.index(c)]
        rows.append(row)
    assert len(pal) <= len(KEYS), len(pal)
    return pal, rows

def swift_string(row):
    return '"' + row.replace('\\', '\\\\').replace('"', '\\"') + '"'

# Every sprite once, in output order: (identifier, palette, rows). Both generated files (Core's and
# the watch's) are written from these lists, so the watch's copy can never drift from Core's.
import gear as gearlib
import monster as monsterlib

DATA = []           # (ident, palette, rows)
POSE_CASES = []     # (buddy, pose, ident)
GEAR_CASES = {'over': [], 'under': []}   # (buddy, gear, slumpedOnly, ident)
MONSTER_CASES = []  # (state, variant pattern, ident)

for name in ORDER:
    fn = buddies.B[name.capitalize()]
    for case, expr in POSES:
        pal, rows = encode(fn(expr).render())
        ident = f'{name}{case[0].upper()}{case[1:]}'
        POSE_CASES.append((name, case, ident))
        DATA.append((ident, pal, rows))

# Gear overlays: one per buddy and item, plus a slumped-face variant where the head moves (Moko).
# Items in gear.UNDER are drawn behind the buddy (`gearUnderPixels`), the rest over it.
for layer, items in (('over', [g for g in gearlib.GEAR if g not in gearlib.UNDER]),
                     ('under', [g for g in gearlib.GEAR if g in gearlib.UNDER])):
    for name in ORDER:
        for g in items:
            normal = gearlib.overlay(name.capitalize(), g).render()
            low = gearlib.overlay(name.capitalize(), g, low=True).render()
            # The slumped variant first: its `true` case must precede the catch-all `_` case.
            for variant, img in (('Low', low), ('', normal)):
                if variant and img == normal:
                    continue
                pal, rows = encode(img)
                ident = f'{name}Gear{g[0].upper()}{g[1:]}{variant}'
                DATA.append((ident, pal, rows))
                GEAR_CASES[layer].append((name, g, bool(variant), ident))

for st in monsterlib.STATES:
    for v in range(3):
        pal, rows = encode(monsterlib.monster(st, v).render())
        ident = f'monster{st.capitalize()}{v}'
        DATA.append((ident, pal, rows))
        MONSTER_CASES.append((st, str(v) if v < 2 else '_', ident))

import cal as callib
CAL_CASES = []      # (state, ident)
for st in callib.STATES:
    pal, rows = encode(callib.cal(st).render())
    ident = f'cal{st.capitalize()}'
    DATA.append((ident, pal, rows))
    CAL_CASES.append((st, ident))

def data_defs(pixels_type):
    defs = []
    for ident, pal, rows in DATA:
        p = ', '.join('0x%02X%02X%02X' % c for c in pal)
        r = ',\n            '.join(swift_string(row) for row in rows)
        defs.append(f'    static let {ident} = {pixels_type}(\n        palette: [{p}],\n        rows: [\n            {r},\n        ]\n    )')
    return '\n\n'.join(defs)

def gear_lines(fname, layer, doc, gear_type, pixels_type, data_enum):
    lines = [f'    /// {doc}', f'    {"public " if gear_type == "BuddyGear" else ""}func {fname}(_ gear: {gear_type}, slumped: Bool) -> {pixels_type}? {{',
             '        switch (self, gear, slumped) {']
    for name, g, low, ident in GEAR_CASES[layer]:
        lines.append(f'        case (.{name}, .{g}, {"true" if low else "_"}): {data_enum}.{ident}')
    return lines + ['        default: nil', '        }', '    }', '']

GEAR_OVER_DOC = 'The overlay for `gear` drawn over any face (`slumped`: the drained/sad head position); nil for gear worn behind.'
GEAR_UNDER_DOC = 'The layer for `gear` drawn behind the buddy (cape, jetpack); nil for gear worn over.'

# --- Core/Sources/Core/UI/Buddy/BuddySprites.swift ---
out = ['// BuddySprites.swift', '// Core / UI / Buddy', '//',
       '// GENERATED by scripts/buddies/export_swift.py from scripts/buddies/buddies.py. Do not edit by',
       '// hand: change the art there and re-run the script. 48x48 pixels per pose; "." is transparent,',
       '// every other character indexes `palette` (0xRRGGBB) through `BuddyPixels.keys`.', '',
       'extension Buddy {', '    /// The pixel art for `pose`.', '    public func pixels(_ pose: BuddyPose) -> BuddyPixels {',
       '        switch (self, pose) {']
out += [f'        case (.{b}, .{p}): BuddySpriteData.{i}' for b, p, i in POSE_CASES]
out += ['        }', '    }', '']
out += gear_lines('gearPixels', 'over', GEAR_OVER_DOC, 'BuddyGear', 'BuddyPixels', 'BuddySpriteData')
out += gear_lines('gearUnderPixels', 'under', GEAR_UNDER_DOC, 'BuddyGear', 'BuddyPixels', 'BuddySpriteData')
out += ['}', '', 'extension ScrollMonster {', '    /// The boss in `state`; `variant` (0...2) changes its colours week to week.',
        '    public static func pixels(_ state: ScrollMonster.State, variant: Int) -> BuddyPixels {',
        '        switch (state, ((variant % 3) + 3) % 3) {']
out += [f'        case (.{s}, {v}): BuddySpriteData.{i}' for s, v, i in MONSTER_CASES]
out += ['        }', '    }', '}', '', 'extension CalPose {', '    /// The calendar character in this mood.',
        '    public var pixels: BuddyPixels {', '        switch self {']
out += [f'        case .{s}: BuddySpriteData.{i}' for s, i in CAL_CASES]
out += ['        }', '    }', '}', '', 'enum BuddySpriteData {']
out.append(data_defs('BuddyPixels'))
out += ['}', '']
open(OUT, 'w').write('\n'.join(out))
print('wrote', os.path.relpath(OUT, ROOT))
print('keys:', KEYS)

# --- Core/Sources/Core/UI/Buddy/BuddyStyleSprites.swift (the shop's cosmetics; not on the watch) ---
import style as stylelib
STYLE_OUT = os.path.join(ROOT, 'Core/Sources/Core/UI/Buddy/BuddyStyleSprites.swift')

def cap(x):
    return x[0].upper() + x[1:]

SLOT_ITEMS = {'hat': stylelib.HAT_ORDER, 'eyewear': stylelib.EYE_ORDER, 'neck': stylelib.NECK_ORDER,
              'back': stylelib.BACKS, 'backdrop': stylelib.BACKDROPS}
STYLE_CASES = [(slot, item, f'{slot}{cap(item)}') for slot, items in SLOT_ITEMS.items() for item in items]
STYLE_DATA = []      # (ident, palette, rows)
STYLE_SWITCH = []    # (buddy, case, slumped?, ident)
for name in ORDER:
    B = name.capitalize()
    for slot, item, case in STYLE_CASES:
        if slot == 'backdrop':
            continue
        normal = stylelib.overlay(B, slot, item).render()
        variants = [('Low', stylelib.overlay(B, slot, item, low=True).render())] if slot in ('hat', 'eyewear') else []
        for variant, img in variants + [('', normal)]:
            if variant and img == normal:
                continue
            pal, rows = encode(img)
            ident = f'{name}{cap(case)}{variant}'
            STYLE_DATA.append((ident, pal, rows))
            STYLE_SWITCH.append((name, case, bool(variant), ident))
BACKDROP_SWITCH = []
for item in stylelib.BACKDROPS:
    pal, rows = encode(stylelib.backdrop(item).render())
    ident = f'backdrop{cap(item)}'
    STYLE_DATA.append((ident, pal, rows))
    BACKDROP_SWITCH.append((f'backdrop{cap(item)}', ident))

SKIN_SWITCH = []     # (buddy, skin, [16 colours: normal orig,new x4 then drained orig,new x4])
for name in ORDER:
    B = name.capitalize()
    for skin in stylelib.SKIN_ORDER:
        normal, drained = stylelib.skin_table(B, stylelib.main_base(B), skin)
        flat = [c for pair in normal + drained for c in pair]
        SKIN_SWITCH.append((name, skin, flat))

st = ['// BuddyStyleSprites.swift', '// Core / UI / Buddy', '//',
      '// GENERATED by scripts/buddies/export_swift.py from scripts/buddies/style.py. Do not edit by hand:',
      '// change the art there and re-run the script. The Buddy Closet\'s cosmetics (docs/spec.md §5.17):',
      '// skins (a colour table per buddy), hats / eyewear / neckwear / back items (one overlay per buddy)',
      '// and backdrops (shared scenes). Every item is cosmetic: nothing here touches a goal or a lock.', '',
      '/// The eight colourways every buddy can buy. A skin recolours the buddy\'s main body ramp only',
      '/// (`Buddy.skinColours`), so the face, belly and props keep their own colours.',
      'public enum BuddySkin: String, Codable, CaseIterable, Sendable, Identifiable {',
      f'    case {", ".join(stylelib.SKIN_ORDER)}', '', '    public var id: String { rawValue }', '}', '',
      '/// Where an item goes. A buddy wears at most one item per slot (plus a skin and a backdrop).',
      'public enum BuddyStyleSlot: String, CaseIterable, Sendable {',
      '    case hat, eyewear, neck, back, backdrop', '}', '',
      '/// Every hat, pair of glasses, neckwear, back item and backdrop. Bought once, worn by any buddy.',
      'public enum BuddyStyleItem: String, Codable, CaseIterable, Sendable, Identifiable {',
      f'    case {", ".join(c for _, _, c in STYLE_CASES)}', '', '    public var id: String { rawValue }', '',
      '    public var slot: BuddyStyleSlot {', '        switch self {']
for slot in SLOT_ITEMS:
    cs = [c for s_, _, c in STYLE_CASES if s_ == slot]
    st.append(f'        case {", ".join("." + c for c in cs)}: .{slot}')
st += ['        }', '    }', '',
       '    /// The scene drawn behind the buddy (nil unless this is a backdrop).',
       '    public func backdropPixels() -> BuddyPixels? {', '        switch self {']
st += [f'        case .{c}: BuddyStyleSpriteData.{i}' for c, i in BACKDROP_SWITCH]
st += ['        default: nil', '        }', '    }', '}', '',
       'extension Buddy {',
       '    /// The overlay for `item` on this buddy (`slumped`: the drained/sad head position). Nil for backdrops.',
       '    public func stylePixels(_ item: BuddyStyleItem, slumped: Bool) -> BuddyPixels? {',
       '        switch (self, item, slumped) {']
st += [f'        case (.{b}, .{c}, {"true" if low else "_"}): BuddyStyleSpriteData.{i}' for b, c, low, i in STYLE_SWITCH]
st += ['        default: nil', '        }', '    }', '',
       '    /// `[original, new]` colour pairs for `skin`: the four shades of this buddy\'s main body colour, then',
       '    /// the same four as the drained face draws them (washed out). Flattened: 16 numbers.',
       '    public func skinColours(_ skin: BuddySkin) -> [UInt32] {', '        switch (self, skin) {']
st += [f'        case (.{b}, .{k}): [{", ".join("0x%02X%02X%02X" % c for c in flat)}]' for b, k, flat in SKIN_SWITCH]
st += ['        }', '    }', '}', '', 'enum BuddyStyleSpriteData {', data_defs('BuddyPixels'), '}', '']
# data_defs() reads DATA; swap in the style data for this write
_saved = list(DATA); DATA[:] = STYLE_DATA
st[-3] = data_defs('BuddyPixels')
DATA[:] = _saved
open(STYLE_OUT, 'w').write('\n'.join(st))
print('wrote', os.path.relpath(STYLE_OUT, ROOT), len(STYLE_DATA), 'sprites')

# --- Watch/ZANOWatch/Generated/WatchBuddySprites.swift ---
# The watch can't import Core (iOS-only), so it gets its own self-contained copy: mirror enums with
# the same raw values the phone sends over WatchConnectivity, the same pixel data, and a copy of
# `BuddyPixels`' decoder (`WatchPixels`).
WATCH_OUT = os.path.join(ROOT, 'Watch/ZANOWatch/Generated/WatchBuddySprites.swift')

def swift_enum(name, doc, cases):
    return [f'/// {doc}', f'enum {name}: String, CaseIterable, Sendable {{', f'    case {", ".join(cases)}', '}', '']

w = ['// WatchBuddySprites.swift', '// Watch / ZANOWatch / Generated', '//',
     '// GENERATED by scripts/buddies/export_swift.py, do not edit by hand: change the art in',
     '// scripts/buddies and re-run the script. A self-contained copy of Core\'s buddy art for the watch,',
     '// which cannot import Core. The enums mirror Core\'s `Buddy`, `BuddyPose`, `BuddyGear` and',
     '// `ScrollMonster.State` with identical raw values (the phone sends raw values to the watch).',
     '// 48x48 pixels per sprite; "." is transparent, every other character indexes `palette`',
     '// (0xRRGGBB) through `WatchPixels.keys`.', '',
     'import CoreGraphics', 'import Foundation', '']
w += swift_enum('WatchBuddy', 'Mirrors Core\'s `Buddy`.', ORDER)
w[-2:-2] = ['', '    static let `default`: WatchBuddy = .stash']
w += swift_enum('WatchBuddyPose', 'Mirrors Core\'s `BuddyPose`.', [c for c, _ in POSES])
w += swift_enum('WatchBuddyGear', 'Mirrors Core\'s `BuddyGear` (`bare`: nothing worn).', ['bare'] + list(gearlib.GEAR))
w += swift_enum('WatchMonsterState', 'Mirrors Core\'s `ScrollMonster.State`.', list(monsterlib.STATES))
w += ['/// One sprite\'s pixels, decoded exactly like Core\'s `BuddyPixels`.',
      'struct WatchPixels: Sendable {',
      '    static let size = 48',
      '    let palette: [UInt32]',
      '    let rows: [String]',
      '',
      '    static let keys: [Character: Int] = {',
      f'        let chars = Array("{KEYS}")',
      '        return Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, $0) })',
      '    }()',
      '',
      '    /// A 48x48 RGBA image (draw it with `.interpolation(.none)` to keep it crisp).',
      '    func cgImage() -> CGImage? {',
      '        Self.image(layers: [self])',
      '    }',
      '',
      '    /// The layers drawn bottom to top into one 48x48 image (a face, then its gear).',
      '    static func image(layers: [WatchPixels]) -> CGImage? {',
      '        let n = size',
      '        var bytes = [UInt8](repeating: 0, count: n * n * 4)',
      '        for layer in layers {',
      '            for (y, row) in layer.rows.enumerated() where y < n {',
      '                for (x, ch) in row.enumerated() where x < n {',
      '                    guard let i = keys[ch], i < layer.palette.count else { continue }',
      '                    let c = layer.palette[i]',
      '                    let o = (y * n + x) * 4',
      '                    bytes[o] = UInt8((c >> 16) & 0xFF)',
      '                    bytes[o + 1] = UInt8((c >> 8) & 0xFF)',
      '                    bytes[o + 2] = UInt8(c & 0xFF)',
      '                    bytes[o + 3] = 0xFF',
      '                }',
      '            }',
      '        }',
      '        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }',
      '        return CGImage(',
      '            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,',
      '            space: CGColorSpaceCreateDeviceRGB(),',
      '            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),',
      '            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent',
      '        )',
      '    }',
      '}', '',
      'extension WatchBuddy {',
      '    /// The buddy in `pose` wearing `gear`, as one image (gear behind, face, gear over).',
      '    func image(pose: WatchBuddyPose, gear: WatchBuddyGear = .bare) -> CGImage? {',
      '        let slumped = pose == .drained || pose == .sad',
      '        let layers = [gearUnderPixels(gear, slumped: slumped), pixels(pose), gearPixels(gear, slumped: slumped)].compactMap { $0 }',
      '        return WatchPixels.image(layers: layers)',
      '    }', '',
      '    /// The pixel art for `pose`.',
      '    func pixels(_ pose: WatchBuddyPose) -> WatchPixels {',
      '        switch (self, pose) {']
w += [f'        case (.{b}, .{p}): WatchSpriteData.{i}' for b, p, i in POSE_CASES]
w += ['        }', '    }', '']
w += gear_lines('gearPixels', 'over', GEAR_OVER_DOC, 'WatchBuddyGear', 'WatchPixels', 'WatchSpriteData')
w += gear_lines('gearUnderPixels', 'under', GEAR_UNDER_DOC, 'WatchBuddyGear', 'WatchPixels', 'WatchSpriteData')
w += ['}', '', '/// The weekly boss (Core\'s `ScrollMonster` art).', 'enum WatchMonster {',
      '    /// The boss in `state`; `variant` (0...2) changes its colours week to week.',
      '    static func pixels(_ state: WatchMonsterState, variant: Int) -> WatchPixels {',
      '        switch (state, ((variant % 3) + 3) % 3) {']
w += [f'        case (.{s}, {v}): WatchSpriteData.{i}' for s, v, i in MONSTER_CASES]
w += ['        }', '    }', '}', '', 'enum WatchSpriteData {']
w.append(data_defs('WatchPixels'))
w += ['}', '']
os.makedirs(os.path.dirname(WATCH_OUT), exist_ok=True)
open(WATCH_OUT, 'w').write('\n'.join(w))
print('wrote', os.path.relpath(WATCH_OUT, ROOT))

# `--sprites-only`: stop here (skip the app icons, wordmark and launch images below).
if '--sprites-only' in sys.argv:
    sys.exit(0)

# App icons: one per buddy, each beaming on the ink canvas over a soft glow in its signature colour.
# Stash (the default) is the primary `AppIcon`; the others are alternate icons `AppIcon-<Name>`
# (listed in project.yml's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES), switched by the app when
# the user teams up with a buddy.
try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit(0)
import json
SIGNATURE = {'stash': (43, 181, 160), 'zib': (63, 123, 255), 'lox': (255, 138, 61), 'pip': (143, 91, 255),
             'moko': (47, 184, 107), 'brick': (229, 72, 77), 'tank': (200, 240, 74), 'volt': (31, 162, 255),
             'howl': (91, 123, 255)}
ASSETS = os.path.join(ROOT, 'App/ZANO/Assets.xcassets')

def icon_for(name):
    S = 1024
    ink = (11, 14, 36)
    glow = Image.new('RGB', (S, S), ink)
    sig = SIGNATURE[name]
    tint = tuple(round(ink[i] * 0.55 + sig[i] * 0.45) for i in range(3))
    ImageDraw.Draw(glow).ellipse((170, 190, 854, 874), fill=tint)
    icon = glow.filter(ImageFilter.GaussianBlur(130))
    img = buddies.B[name.capitalize()]('happy').render()
    cell = 18
    ox = (S - N * cell) // 2
    oy = (S - N * cell) // 2 + 10
    d = ImageDraw.Draw(icon)
    for (x, y), c in img.items():
        d.rectangle((ox + x * cell, oy + y * cell, ox + (x + 1) * cell - 1, oy + (y + 1) * cell - 1), fill=c)
    return icon

for name in ORDER:
    folder = 'AppIcon' if name == 'stash' else f'AppIcon-{name.capitalize()}'
    path = os.path.join(ASSETS, f'{folder}.appiconset')
    os.makedirs(path, exist_ok=True)
    icon_for(name).save(os.path.join(path, 'AppIcon-1024.png'))
    json.dump({'images': [{'filename': 'AppIcon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
               'info': {'author': 'xcode', 'version': 1}}, open(os.path.join(path, 'Contents.json'), 'w'), indent=2)
    print('wrote', os.path.relpath(path, ROOT))

# The friendly wordmark (2026-10-04): lowercase "zano" in Nunito Black (fonts/, SIL OFL), pearl
# letters with the "o" in Stash teal. The app draws the same thing with SF Rounded (`ZanoWordmark`),
# where the "o" takes the user's buddy colour; images use Nunito because there's no SF Rounded here.
from PIL import ImageFont
FONT = os.path.join(HERE, 'fonts', 'Nunito.ttf')
PEARL = (242, 244, 255)
TEAL = (43, 181, 160)

def wordmark(width, ink=PEARL, accent=TEAL):
    """'zano', tight-cropped, `width` pixels wide, transparent background."""
    size = 400
    font = ImageFont.truetype(FONT, size)
    font.set_variation_by_name('Black')
    big = Image.new('RGBA', (size * 4, size * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    x = size // 4
    for ch in 'zano':
        d.text((x, size // 4), ch, font=font, fill=(accent if ch == 'o' else ink) + (255,))
        x += d.textlength(ch, font=font) - size * 0.025
    big = big.crop(big.getbbox())
    return big.resize((width, round(big.size[1] * width / big.size[0])), Image.LANCZOS)

wordmark(1200).save(os.path.join(ROOT, 'docs/brand/zano-wordmark-friendly.png'))
wordmark(1200, ink=(19, 20, 43)).save(os.path.join(ROOT, 'docs/brand/zano-wordmark-friendly-light.png'))
print('wrote docs/brand/zano-wordmark-friendly(.png, -light.png)')

# Launch screen (buddy everywhere, 2026-10-03): Stash (the default buddy; a launch screen is static,
# so it can't show the user's own pick), beaming, above the friendly wordmark, on the
# `LaunchBackground` ink. 120pt wide: the sprite is 96pt (whole-pixel scaling at every scale), a
# 20pt gap, then the wordmark 110pt wide.
LAUNCH_W, SPRITE_PT, GAP_PT, WORD_PT = 120, 96, 20, 110
launch_path = os.path.join(ASSETS, 'LaunchLogo.imageset')
stash_img = buddies.B['Stash']('happy').render()
files = []
for scale in (1, 2, 3):
    width = LAUNCH_W * scale
    word = wordmark(WORD_PT * scale)
    sprite_px = SPRITE_PT * scale
    height = sprite_px + GAP_PT * scale + word.size[1]
    canvas = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    cell = sprite_px // N
    ox = (width - N * cell) // 2
    d = ImageDraw.Draw(canvas)
    for (x, y), c in stash_img.items():
        d.rectangle((ox + x * cell, y * cell, ox + (x + 1) * cell - 1, (y + 1) * cell - 1), fill=c)
    canvas.alpha_composite(word, ((width - word.size[0]) // 2, sprite_px + GAP_PT * scale))
    name = f'LaunchLogo@{scale}x.png'
    canvas.save(os.path.join(launch_path, name))
    files.append({'filename': name, 'idiom': 'universal', 'scale': f'{scale}x'})
json.dump({'images': files, 'info': {'author': 'xcode', 'version': 1}},
          open(os.path.join(launch_path, 'Contents.json'), 'w'), indent=2)
print('wrote', os.path.relpath(launch_path, ROOT))
