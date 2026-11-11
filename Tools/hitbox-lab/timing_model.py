"""How much timing each obstacle gives, worked out from the source alone.

A continuous model of one jump or slide against one obstacle, built only from
the numbers `hitbox_source` reads: the jump parabola, the pose each moment of
the arc is drawn in, that pose's box lift, and the obstacle's solid at the
height the game would solve for it. It has no frames and no Box2D skin, so its
windows run a little wider than the Hitbox Lab measures on a simulator; what it
is for is noticing when a change to the source moves them.

Distances are the obstacle's centre ahead of Benny's centre at the moment he
jumps or slides, in points, as the lab uses them.

Standard library only.
"""
import math
from dataclasses import dataclass

DT = 1 / 2000          # seconds between samples inside an overlap
OBSTACLE_SAMPLES = 96  # the game's own sample count in obstacleHeight


@dataclass
class Window:
    lo: float          # nearest lead that clears
    hi: float          # furthest lead that clears
    speed: float

    @property
    def width(self):
        return self.hi - self.lo

    @property
    def ms(self):
        return 1000 * self.width / self.speed


class Model:
    def __init__(self, world):
        self.w = world
        c = world.const
        self.g = world.gravity
        self.v = world.launch
        self.air = world.airtime
        dog_w, dog_h = world.dog_size
        self.dog_w, self.dog_h = dog_w, dog_h
        give = c('DogArt.forgivenessFraction')

        def box(width_f, height_f, offset_f):
            width = dog_w * (width_f - give)
            centre = dog_w * (offset_f - give / 2)
            return centre - width / 2, centre + width / 2, dog_h * height_f
        # Standing and ducked boxes, as makeDogPhysics builds them: x span
        # relative to Benny's centre, and the top above the paw line.
        self.stand = box(c('DogArt.bodyWidthFraction'), c('DogArt.bodyHeightFraction'),
                         c('DogArt.bodyOffsetXFraction'))
        self.duck = box(c('DogArt.slideWidthFraction'), c('DogArt.slideHeightFraction'),
                        c('DogArt.slideOffsetXFraction'))
        self.lifts = c('DogArt.jumpLifts')
        weights = list(world.jump_weights)
        n = world.jump_frames
        shares = [weights[i] if i < len(weights) else 1 / n for i in range(n)]
        whole = sum(shares)
        self.frame_starts = [0.0]
        for s in shares:
            self.frame_starts.append(self.frame_starts[-1] + self.air * s / whole)

    # --- The jump ------------------------------------------------------------------

    def paw(self, t):
        return max(0.0, self.v * t - 0.5 * self.g * t * t)

    def frame(self, t):
        for i in range(len(self.frame_starts) - 1):
            if t < self.frame_starts[i + 1]:
                return i
        return len(self.frame_starts) - 2

    def lift(self, t):
        if t <= 0 or t >= self.air:
            return 0.0
        f = self.frame(t)
        return self.lifts[f] if f < len(self.lifts) else 0.0

    # --- Obstacles -----------------------------------------------------------------

    def solve_height(self, piece, speed):
        """obstacleHeight(_:at:) without the jitter: the same bisection."""
        c = self.w.const
        dog_solid = self.dog_w * c('DogArt.bodyWidthFraction')
        underfoot = piece.sink - c('Layout.dogPlantDepth')
        clearance = c('ObstacleArt.clearance')
        v, g = self.v, self.g

        def reach(h):
            if piece.shape == 'box':
                return h * piece.aspect * piece.solid['width'] / 2 + dog_solid / 2
            return h * piece.solid['radius'] + dog_solid / 2

        def need_at(gap, h):
            if piece.shape == 'box':
                return h * piece.top_per_height()
            r = h * piece.solid['radius']
            rr = max(0.0, abs(gap) - dog_solid / 2)
            return h * piece.solid['centre'] + math.sqrt(max(0.0, r * r - rr * rr))

        def slack(h):
            span = reach(h)
            earliest, latest, touches = -math.inf, math.inf, False
            for step in range(OBSTACLE_SAMPLES + 1):
                gap = -span + 2 * span * step / OBSTACLE_SAMPLES
                need = need_at(gap, h) - underfoot
                if need <= 0:
                    continue
                touches = True
                remaining = v * v - 2 * g * need
                if remaining <= 0:
                    return -1
                rising = (v - math.sqrt(remaining)) / g
                falling = (v + math.sqrt(remaining)) / g
                arrives = -gap / speed
                latest = min(latest, arrives - rising)
                earliest = max(earliest, arrives - falling)
            return latest - earliest if touches else math.inf

        low, high = piece.low, piece.high
        if not slack(low) > clearance:
            return low, slack(low)
        if not slack(high) < clearance:
            return high, slack(high)
        for _ in range(24):
            mid = (low + high) / 2
            if slack(mid) > clearance:
                low = mid
            else:
                high = mid
        return low, slack(low)

    def solid(self, piece, height):
        """The solid relative to the obstacle's centre and Benny's paw line."""
        width = height * piece.aspect
        cx = width * piece.offset_x
        under = piece.sink - self.w.const('Layout.dogPlantDepth')
        s = piece.solid
        if piece.shape == 'box':
            half = width * s['width'] / 2
            return ('box', cx - half, cx + half, height * s['base'] - under,
                    height * (s['base'] + s['height']) - under)
        return ('disc', cx, height * s['centre'] - under, height * s['radius'])

    @staticmethod
    def _overlaps(solid, ox, left, right, floor, top):
        if solid[0] == 'box':
            _, lo, hi, bottom, top_ = solid
            return lo + ox < right and hi + ox > left and bottom < top and top_ > floor
        _, cx, cy, rad = solid
        cx += ox
        nx = min(max(cx, left), right)
        ny = min(max(cy, floor), top)
        return (nx - cx) ** 2 + (ny - cy) ** 2 < rad * rad

    @staticmethod
    def _x_extent(solid):
        if solid[0] == 'box':
            return solid[1], solid[2]
        return solid[1] - solid[3], solid[1] + solid[3]

    def jump_hits(self, solid, speed, d):
        left, right, top_f = self.stand
        lo, hi = self._x_extent(solid)
        # When the solid and the box can overlap sideways at all.
        t0 = max(0.0, (lo + d - right) / speed)
        t1 = (hi + d - left) / speed
        if t1 < 0:
            return False
        t = t0
        while t <= t1:
            y = self.paw(t)
            floor = y + self.lift(t) * self.dog_h
            if self._overlaps(solid, d - speed * t, left, right, floor, y + top_f):
                return True
            t += DT
        y = self.paw(t1)
        return self._overlaps(solid, d - speed * t1, left, right, y + self.lift(t1) * self.dog_h, y + top_f)

    def _edges(self, hits, start, stop, step):
        """Bisect the clear stretch around the first clear lead in [start, stop]."""
        d = start
        while d <= stop and hits(d):
            d += step
        if d > stop:
            return None
        seed = d

        def bisect(clear, hit):
            for _ in range(40):
                mid = (clear + hit) / 2
                if hits(mid):
                    hit = mid
                else:
                    clear = mid
            return clear
        lo = bisect(seed, seed - step) if seed > start else seed
        hi = seed + step
        while hi <= stop + 600 and not hits(hi):
            hi += step
        hi = bisect(hi - step, hi)
        return lo, hi

    def jump_window(self, piece, speed, height=None):
        if height is None:
            height, _ = self.solve_height(piece, speed)
        solid = self.solid(piece, height)
        edges = self._edges(lambda d: self.jump_hits(solid, speed, d), -50, 600, 1.0)
        return None if edges is None else Window(edges[0], edges[1], speed)

    def slide_window(self, piece, speed):
        """A slide fired with the obstacle d ahead: ducked for slideDistance of
        ground, standing either side. Returns the window, or None if even the
        ducked box can't pass under."""
        height = piece.low
        solid = self.solid(piece, height)
        duration = self.w.const('Layout.slideDistance') / speed
        dl, dr, dtop = self.duck
        sl, sr, stop = self.stand
        if self._overlaps(solid, 0, dl, dr, 0, dtop) and solid[0] == 'box' and solid[3] < dtop:
            return None
        lo, hi = self._x_extent(solid)
        # Standing must not touch it before the slide, nor after it ends.
        earliest = sr - lo           # nearest lead: not yet under the standing box
        latest = sl - hi + speed * duration
        return Window(earliest, latest, speed)

    # --- Cliffs and spacing -----------------------------------------------------------

    def cliff_slack(self, speed):
        c = self.w.const
        gap = min(c('Cliff.maxGapWidth'), speed * (self.air - c('Cliff.clearance')))
        return gap, self.air - gap / speed

    def speeds(self, step=10.0):
        """Every speed a run passes through, opening to top, at this step."""
        c = self.w.const
        s, out = c('Layout.openingSpeed'), []
        while s < c('Layout.topSpeed'):
            out.append(s)
            s += step
        out.append(c('Layout.topSpeed'))
        return out


def tier_for(world, speed):
    tiers = world.const('ObstacleArt.sizeTiers')
    below = [t for t in tiers if t <= speed + 1e-9]
    return below[-1] if below else tiers[0]


def report(world):
    """Every number the gate judges, as one dict."""
    from hitbox_source import JUMP_PIECES, DUCK_PIECES
    m = Model(world)
    c = world.const
    out = {'airtime': round(m.air, 4), 'launch': round(m.v, 2), 'jumps': {}, 'slides': {}, 'cliffs': {}}
    for name in JUMP_PIECES:
        piece = world.pieces[name]
        for tier in c('ObstacleArt.sizeTiers'):
            height, slack = m.solve_height(piece, tier)
            w = m.jump_window(piece, tier, height)
            key = f'{name}@{round(tier)}'
            row = {'height': round(height, 2), 'solverSlackMs': round(slack * 1000, 1),
                   'clampedLow': height <= piece.low + 1e-6, 'clampedHigh': height >= piece.high - 1e-6}
            if w:
                row.update(lo=round(w.lo, 2), hi=round(w.hi, 2), ms=round(w.ms, 1))
            else:
                row.update(lo=None, hi=None, ms=0.0)
            # Solved at the tier's own speed, which is also its hardest: the same
            # prop only gets easier as the run speeds up to the next tier.
            out['jumps'][key] = row
    for name in DUCK_PIECES:
        piece = world.pieces[name]
        for speed in (c('Layout.openingSpeed'), c('Layout.topSpeed')):
            w = m.slide_window(piece, speed)
            out['slides'][f'{name}@{round(speed)}'] = (
                {'lo': round(w.lo, 2), 'hi': round(w.hi, 2), 'ms': round(w.ms, 1)} if w else None)
        solid = m.solid(piece, piece.low)
        out['slides'][f'{name}:underside'] = round(solid[3], 2) if solid[0] == 'box' else None
    out['duckedTop'] = round(m.duck[2], 2)
    out['standingTop'] = round(m.stand[2], 2)
    worst = min((m.cliff_slack(s) for s in m.speeds()), key=lambda gs: gs[1])
    out['cliffs'] = {'tightestSlackMs': round(worst[1] * 1000, 1), 'gapThere': round(worst[0], 1)}
    if world.interval:
        out['spawnFloorVsAirtimeMs'] = round((world.interval['floor'] - m.air) * 1000, 1)
    return out


if __name__ == '__main__':
    import json
    import os
    import sys
    from hitbox_source import load_world
    here = os.path.dirname(os.path.abspath(__file__))
    print(json.dumps(report(load_world(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', '..'))), indent=1))
