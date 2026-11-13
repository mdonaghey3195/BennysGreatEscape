"""Read every number that shapes a collision straight from the Swift source.

No build, no simulator: this is what lets the Linux CI gate reason about the
hitbox. It reads `static let` constants (keyed by the innermost type they sit
in, so `ObstacleArt.clearance` and `Cliff.clearance` stay apart), evaluates
their arithmetic, reads the obstacle `Piece` definitions, and takes image
aspects from the PNG headers in Assets.xcassets.

    from hitbox_source import load_world
    world = load_world('/path/to/repo')
    world.const('Layout.openingSpeed')    # 250.44...
    world.pieces['log']                   # Piece(...)

Standard library only.
"""
import ast
import math
import os
import re
import struct
from dataclasses import dataclass, field

APP = 'BennysGreatEscape'
SOURCES = ['GameLayout.swift', 'GameArt.swift', 'ObstacleArt.swift', 'GameScene.swift']

# The constants the gate and the timing model use. Reading only these keeps a
# failure specific: a renamed or reshaped constant is named, not guessed at.
CONSTANTS = [
    'Layout.worldScale', 'Layout.speedScale', 'Layout.openingSpeed', 'Layout.topSpeed',
    'Layout.jumpHeight', 'Layout.dogWidth', 'Layout.dogX', 'Layout.dogPlantDepth',
    'Layout.duckClearance', 'Layout.obstacleSink', 'Layout.slideDistance',
    'DogArt.bodyWidthFraction', 'DogArt.bodyHeightFraction', 'DogArt.bodyOffsetXFraction',
    'DogArt.forgivenessFraction', 'DogArt.slideWidthFraction', 'DogArt.slideHeightFraction',
    'DogArt.slideOffsetXFraction', 'DogArt.jumpLifts',
    'ObstacleArt.clearance', 'ObstacleArt.sizeTiers', 'ObstacleArt.heightJitter',
    'ObstacleArt.pairRecovery', 'ObstacleArt.benchUnderseat', 'ObstacleArt.benchSink',
    'ObstacleArt.benchHeight', 'ObstacleArt.swingsetUnderbar', 'ObstacleArt.swingsetSink',
    'ObstacleArt.swingsetHeight',
    'Cliff.clearance', 'Cliff.maxGapWidth',
]
PIECES = ['bush', 'hedge', 'log', 'logStack', 'stump', 'bench', 'occupiedBench', 'swingset']
JUMP_PIECES = ['bush', 'hedge', 'log', 'logStack', 'stump']
DUCK_PIECES = ['bench', 'occupiedBench', 'swingset']


class SourceError(Exception):
    """The source no longer looks the way this reader expects."""


@dataclass
class Piece:
    name: str
    image: str
    low: float
    high: float
    shape: str             # 'box' or 'disc'
    solid: dict            # box: width, height, base; disc: radius, centre (fractions)
    offset_x: float
    sink: float
    aspect: float          # image width / height

    def size(self, height):
        return height * self.aspect, height

    def top_per_height(self):
        """The solid's top, as a fraction of the drawn height."""
        if self.shape == 'box':
            return self.solid['base'] + self.solid['height']
        return self.solid['centre'] + self.solid['radius']

    def as_dict(self):
        return {'image': self.image, 'heightRange': [round(self.low, 4), round(self.high, 4)],
                'shape': self.shape, 'solid': {k: round(v, 4) for k, v in self.solid.items()},
                'offsetXFraction': self.offset_x, 'sink': round(self.sink, 4),
                'aspect': round(self.aspect, 4)}


@dataclass
class World:
    consts: dict
    pieces: dict
    gravity: float               # pt/s²
    jump_weights: list
    jump_frames: int
    dog_aspect: float
    interval: dict = field(default_factory=dict)

    def const(self, name):
        if name not in self.consts:
            raise SourceError(f'{name} was not found in the source')
        return self.consts[name]

    # Derived, exactly as the game derives them.
    @property
    def launch(self):
        return math.sqrt(2 * self.gravity * self.const('Layout.jumpHeight'))

    @property
    def airtime(self):
        return 2 * self.launch / self.gravity

    @property
    def dog_size(self):
        w = self.const('Layout.dogWidth')
        return w, w / self.dog_aspect

    def as_dict(self):
        """Everything the baseline records, rounded so float noise never shows."""
        def r(v):
            return [round(x, 4) for x in v] if isinstance(v, list) else round(v, 4)
        return {
            'constants': {k: r(self.consts[k]) for k in CONSTANTS},
            'pieces': {k: self.pieces[k].as_dict() for k in PIECES},
            'gravity': round(self.gravity, 4),
            'jumpWeights': self.jump_weights,
            'jumpFrames': self.jump_frames,
            'dogAspect': round(self.dog_aspect, 4),
            'spawnInterval': self.interval,
        }


# --- Reading declarations ---------------------------------------------------------

DECL = re.compile(r'^\s*(?:(?:private|fileprivate|internal|public)\s+)?static\s+(?:let|var)\s+(\w+)\s*(?::\s*[^=]+?)?\s*=\s*(.*)$')
TYPE = re.compile(r'\b(?:enum|struct|class|extension)\s+(\w+)')


def strip_comment(line):
    """A line without its // comment (no strings with // in these files)."""
    i = line.find('//')
    return line if i < 0 else line[:i]


def declarations(text):
    """{'Type.name': 'expression text'} for every static let/var, by innermost type."""
    found = {}
    stack = []      # (type name, brace depth at which it opened)
    depth = 0
    lines = text.split('\n')
    i = 0
    while i < len(lines):
        raw = strip_comment(lines[i])
        m_type = TYPE.search(raw)
        m = DECL.match(raw)
        if m and stack:
            name, expr = m.group(1), m.group(2).strip()
            j = i
            # Gather continuation lines: unbalanced brackets, a trailing operator,
            # or nothing after the = yet.
            while (expr == '' or expr.count('(') > expr.count(')') or expr.count('[') > expr.count(']')
                   or re.search(r'[-+*/=,]\s*$', expr)) and j + 1 < len(lines):
                j += 1
                expr += ' ' + strip_comment(lines[j]).strip()
            key = f'{stack[-1][0]}.{name}'
            found.setdefault(key, expr.strip())
            # Count braces across the whole declaration.
            for k in range(i, j + 1):
                line = strip_comment(lines[k])
                depth += line.count('{') - line.count('}')
            while stack and depth < stack[-1][1]:
                stack.pop()
            i = j + 1
            continue
        if m_type and '{' in raw:
            stack.append((m_type.group(1), depth + 1))
        depth += raw.count('{') - raw.count('}')
        while stack and depth < stack[-1][1]:
            stack.pop()
        i += 1
    return found


# --- Evaluating them --------------------------------------------------------------

class Evaluator:
    def __init__(self, decls):
        self.decls = decls
        self.values = {}
        self.busy = set()

    def value(self, key):
        if key in self.values:
            return self.values[key]
        if key not in self.decls:
            raise SourceError(f'{key} was not found in the source')
        if key in self.busy:
            raise SourceError(f'{key} refers to itself')
        self.busy.add(key)
        scope = key.split('.')[0]
        self.values[key] = self.evaluate(self.decls[key], scope)
        self.busy.discard(key)
        return self.values[key]

    def evaluate(self, expr, scope):
        py = expr.replace('CGFloat(', '(').replace('TimeInterval(', '(')
        try:
            tree = ast.parse(py, mode='eval')
        except SyntaxError as e:
            raise SourceError(f'cannot read {scope} expression {expr!r}: {e}')
        return self._eval(tree.body, scope, expr)

    def _eval(self, node, scope, expr):
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return float(node.value)
        if isinstance(node, ast.List):
            return [self._eval(e, scope, expr) for e in node.elts]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            return -self._eval(node.operand, scope, expr)
        if isinstance(node, ast.BinOp):
            a, b = self._eval(node.left, scope, expr), self._eval(node.right, scope, expr)
            if isinstance(node.op, ast.Add): return a + b
            if isinstance(node.op, ast.Sub): return a - b
            if isinstance(node.op, ast.Mult): return a * b
            if isinstance(node.op, ast.Div): return a / b
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in ('sqrt', 'min', 'max'):
            args = [self._eval(a, scope, expr) for a in node.args]
            return {'sqrt': lambda: math.sqrt(args[0]), 'min': lambda: min(args), 'max': lambda: max(args)}[node.func.id]()
        if isinstance(node, ast.Name):
            return self.value(f'{scope}.{node.id}')
        if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
            return self.value(f'{node.value.id}.{node.attr}')
        raise SourceError(f'cannot evaluate {ast.dump(node)[:60]} in {expr!r}')


# --- Pieces and images ------------------------------------------------------------

def png_aspect(path):
    with open(path, 'rb') as fh:
        head = fh.read(24)
    if head[:8] != b'\x89PNG\r\n\x1a\n':
        raise SourceError(f'{path} is not a PNG')
    w, h = struct.unpack('>II', head[16:24])
    return w / h


def imagesets(root):
    """Every .imageset in the catalog, by name, wherever it's filed."""
    found = {}
    for dirpath, dirnames, _ in os.walk(os.path.join(root, APP, 'Assets.xcassets')):
        for d in dirnames:
            if d.endswith('.imageset'):
                found[d[:-len('.imageset')]] = os.path.join(dirpath, d)
    return found


def image_aspect(root, name):
    folder = imagesets(root).get(name, '')
    pngs = sorted(f for f in os.listdir(folder) if f.endswith('.png')) if os.path.isdir(folder) else []
    if not pngs:
        raise SourceError(f'no PNG for image {name}')
    return png_aspect(os.path.join(folder, pngs[0]))


def read_piece(name, expr, ev, root, done):
    def arg(label):
        m = re.search(rf'\b{label}:\s*', expr)
        if not m:
            return None
        rest, level, out = expr[m.end():], 0, ''
        for ch in rest:
            if ch in '([':
                level += 1
            elif ch in ')]':
                if level == 0:
                    break
                level -= 1
            elif ch == ',' and level == 0:
                break
            out += ch
        return out.strip()

    texture = arg('texture')
    solid_text = arg('solid')
    if texture and texture.endswith('.texture'):
        base = done[texture.split('.')[0]]
        image, aspect = base.image, base.aspect
    else:
        m = re.match(r'load\("(\w+)"\)', texture or '')
        if not m:
            raise SourceError(f'ObstacleArt.{name}: unexpected texture {texture!r}')
        image = m.group(1)
        aspect = image_aspect(root, image)

    range_text = arg('heightRange')
    if range_text and range_text.endswith('.heightRange'):
        b = done[range_text.split('.')[0]]
        low, high = b.low, b.high
    else:
        if not range_text or '...' not in range_text:
            raise SourceError(f'ObstacleArt.{name}: unexpected heightRange {range_text!r}')
        lo, hi = range_text.split('...')
        low, high = ev.evaluate(lo, 'ObstacleArt'), ev.evaluate(hi, 'ObstacleArt')

    if solid_text and solid_text.endswith('.solid'):
        b = done[solid_text.split('.')[0]]
        shape, solid = b.shape, dict(b.solid)
    else:
        m = re.match(r'\.(box|disc)\((.*)\)$', solid_text or '')
        if not m:
            raise SourceError(f'ObstacleArt.{name}: unexpected solid {solid_text!r}')
        shape = m.group(1)
        solid = {}
        for part in m.group(2).split(','):
            k, v = part.split(':')
            solid[k.strip()] = ev.evaluate(v.strip(), 'ObstacleArt')

    off = arg('offsetXFraction')
    offset = 0.0 if off is None else (done[off.split('.')[0]].offset_x if off.endswith('.offsetXFraction')
                                      else ev.evaluate(off, 'ObstacleArt'))
    sink_text = arg('sink')
    if sink_text is None:
        sink = ev.value('Layout.obstacleSink')
    elif sink_text.endswith('.sink'):
        sink = done[sink_text.split('.')[0]].sink
    else:
        sink = ev.evaluate(sink_text, 'ObstacleArt')
    return Piece(name, image, low, high, shape, solid, offset, sink, aspect)


def load_world(root, edit=None):
    """Read the world from the repository at `root`. `edit(file, text)`, if
    given, may rewrite a source file's text first (the tests use it)."""
    text = {}
    for f in SOURCES:
        path = os.path.join(root, APP, f)
        with open(path) as fh:
            text[f] = fh.read()
        if edit:
            text[f] = edit(f, text[f])
    decls = {}
    for f in SOURCES:
        for k, v in declarations(text[f]).items():
            decls.setdefault(k, v)
    ev = Evaluator(decls)
    consts = {k: ev.value(k) for k in CONSTANTS}

    done = {}
    for name in PIECES:
        key = f'ObstacleArt.{name}'
        if key not in decls:
            raise SourceError(f'{key} was not found in the source')
        done[name] = read_piece(name, decls[key], ev, root, done)

    scene = text['GameScene.swift']
    m = re.search(r'physicsWorld\.gravity\s*=\s*CGVector\(dx:\s*0,\s*dy:\s*(-?[\d.]+)\)', scene)
    if not m:
        raise SourceError('physicsWorld.gravity was not found in GameScene.swift')
    gravity = abs(float(m.group(1))) * 150    # SpriteKit: m/s² against 150 pt per metre
    m = re.search(r'let weights: \[CGFloat\] = \[([^\]]*)\]', scene)
    if not m:
        raise SourceError("jumpArc's weights were not found in GameScene.swift")
    weights = [float(x) for x in m.group(1).split(',') if x.strip()]
    interval = {}
    m = re.search(r'private var obstacleInterval: TimeInterval = ([\d.]+)', scene)
    n = re.search(r'obstacleInterval = max\(([\d.]+), obstacleInterval - ([\d.]+)\)', scene)
    s = re.search(r'gameSpeed = min\(Layout\.topSpeed, gameSpeed \+ ([\d.]+)\)', scene)
    if m and n and s:
        interval = {'start': float(m.group(1)), 'floor': float(n.group(1)), 'step': float(n.group(2)),
                    'speedStep': float(s.group(1))}

    frames = len([n for n in imagesets(root) if re.fullmatch(r'benny_jump_\d+', n)])
    return World(consts, done, gravity, weights, frames, image_aspect(root, 'benny_run_0'), interval)


if __name__ == '__main__':
    import json
    import sys
    here = os.path.dirname(os.path.abspath(__file__))
    world = load_world(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', '..'))
    print(json.dumps(world.as_dict(), indent=1))
