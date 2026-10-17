"""Danger logic for the bike rear camera.

Feed it the vehicles seen in each frame (from the detector and tracker) and it
says how strongly to vibrate the left and right handles.

Levels:
    0  nothing
    1  gentle:  a vehicle is very close and still creeping toward the bike
    2  warning: time to collision under ttc_warn_s
    3  urgent:  time to collision under ttc_urgent_s

Filters applied before a detection is used:
    - too small: boxes narrower than min_width_frac of the frame are too far
      away and too jittery to measure
    - exclusion zones: rectangles where the bike's own parts appear
    - large and unsure: a huge box with low confidence is usually the bike's own
      parts or the car interior, not a vehicle
    - sudden jump: if a box changes size abnormally between two frames (a video
      cut, or the tracker swapping ids), its history is thrown away

How it decides, per tracked vehicle:
    1. Keep the vehicle's box width (as a fraction of the frame width) for the
       last window_s seconds.
    2. Fit a straight line through those widths. The slope is the growth rate.
       A line through several frames smooths out frame to frame jitter.
    3. Time to collision = width / growth rate (only if it is growing). It is
       computed from a line through 1 / width, which is exact for a vehicle
       closing at constant speed.
    4. If the vehicle is also very wide (close_frac of the frame) and growing
       even slowly, give the gentle level. This covers cars creeping in traffic.
    5. Passing check: measure how far the vehicle sits off the camera's centre
       line, in units of its own width. A vehicle dead behind the bike is at
       about 0. A car in the next lane is at about 2 or more. Beyond
       max_lateral_widths the vehicle will pass by, not hit the bike, so no alert.
    6. Pick a side from where the box sits in the frame. The camera faces
       backward, so the picture is flipped: image left is the rider's right.

Everything is measured in fractions of the frame, so it works at any camera
resolution.
"""
from collections import deque
from dataclasses import dataclass, field

LEVEL_NONE = 0
LEVEL_GENTLE = 1
LEVEL_WARN = 2
LEVEL_URGENT = 3


@dataclass
class DangerConfig:
    frame_width: float = 640.0      # pixels, used to turn pixel widths into fractions
    frame_height: float = 360.0     # only needed for exclusion zones
    window_s: float = 0.5           # how far back the trend line looks
    min_samples: int = 5            # frames needed inside the window before we trust it
    min_span_s: float = 0.1         # and they must cover at least this much time
    ttc_warn_s: float = 3.0
    ttc_urgent_s: float = 2.0
    close_frac: float = 0.6         # box wider than this fraction of the frame = very close
    min_growth_per_s: float = 0.01  # growth below 1% of frame width per second counts as not growing
    hold_s: float = 1.0             # keep an alert on this long after the danger passes
    drop_track_after_s: float = 1.0 # forget a vehicle not seen for this long
    mirror: bool = True             # rear facing camera: image left is the rider's right

    min_width_frac: float = 0.04        # ignore boxes narrower than this fraction of the frame
    large_frac: float = 0.5             # a box at least this wide counts as "large"...
    large_min_confidence: float = 0.5   # ...and is ignored unless the detector is at least this sure
    jump_ratio: float = 1.6             # box size change between two frames beyond this = reset
    max_lateral_widths: float = 1.0     # off-centre by more than this many vehicle widths = passing by
    # Exclusion zones: list of (x1, y1, x2, y2) as fractions of the frame, 0 to 1.
    # A detection whose centre is inside one is ignored. Needs Detection.center_y.
    exclude_zones: list = field(default_factory=list)


@dataclass
class Detection:
    track_id: int
    center_x: float                  # pixels
    width: float                     # pixels
    center_y: float | None = None    # pixels, only needed for exclusion zones
    confidence: float = 1.0          # detector confidence, 0 to 1


@dataclass
class Assessment:
    track_id: int
    level: int
    ttc_s: float | None   # None when the vehicle is not approaching
    growth_per_s: float   # fraction of frame width per second
    width_frac: float
    side: str             # "left", "right" or "both" from the rider's point of view


@dataclass
class DangerOutput:
    left: int = 0
    right: int = 0
    vehicles: list = field(default_factory=list)  # list[Assessment], only those with level > 0


def fit_line(samples):
    """Least squares line through (time, value, ...) samples.

    Only the first two entries of each sample are used.
    Returns (slope, fitted value at the latest sample).
    """
    n = len(samples)
    t0 = samples[0][0]
    ts = [s[0] - t0 for s in samples]
    ws = [s[1] for s in samples]
    mean_t = sum(ts) / n
    mean_w = sum(ws) / n
    sxx = sum((t - mean_t) ** 2 for t in ts)
    if sxx == 0:
        return 0.0, ws[-1]
    slope = sum((t - mean_t) * (w - mean_w) for t, w in zip(ts, ws)) / sxx
    return slope, mean_w + slope * (ts[-1] - mean_t)


class DangerEngine:
    def __init__(self, config: DangerConfig | None = None):
        self.cfg = config or DangerConfig()
        self._samples = {}    # track_id -> deque of (time, width_frac, center_x_frac)
        self._last_seen = {}  # track_id -> time
        self._held = {"left": (0, -1.0), "right": (0, -1.0)}  # side -> (level, hold until)

    def update(self, t: float, detections) -> DangerOutput:
        """Process one frame. Call it every frame, even when nothing was detected."""
        cfg = self.cfg
        inst = {"left": 0, "right": 0}
        vehicles = []

        for det in detections:
            if det.track_id is None or det.track_id < 0:
                continue  # the tracker has not given this vehicle an id yet
            if self._ignored(det):
                continue
            width_frac = det.width / cfg.frame_width
            buf = self._samples.setdefault(det.track_id, deque())
            if buf and buf[-1][1] > 0:
                ratio = width_frac / buf[-1][1]
                if ratio > cfg.jump_ratio or ratio < 1 / cfg.jump_ratio:
                    buf.clear()  # video cut or id swap: start this vehicle's history again
            buf.append((t, width_frac, det.center_x / cfg.frame_width))
            self._last_seen[det.track_id] = t
            while buf and buf[0][0] < t - 1.0:
                buf.popleft()

            assessment = self._assess(det, buf, t)
            if assessment.level > 0:
                vehicles.append(assessment)
                if assessment.side in ("left", "both"):
                    inst["left"] = max(inst["left"], assessment.level)
                if assessment.side in ("right", "both"):
                    inst["right"] = max(inst["right"], assessment.level)

        # forget vehicles we have not seen for a while
        for tid in [k for k, seen in self._last_seen.items() if t - seen > cfg.drop_track_after_s]:
            self._samples.pop(tid, None)
            self._last_seen.pop(tid, None)

        out = {}
        for side in ("left", "right"):
            held_level, until = self._held[side]
            if t >= until:
                held_level = 0
            if inst[side] > 0 and inst[side] >= held_level:
                held_level, until = inst[side], t + cfg.hold_s  # refresh the hold
                self._held[side] = (held_level, until)
            out[side] = max(inst[side], held_level)

        return DangerOutput(left=out["left"], right=out["right"], vehicles=vehicles)

    def _ignored(self, det) -> bool:
        cfg = self.cfg
        width_frac = det.width / cfg.frame_width
        if width_frac < cfg.min_width_frac:
            return True   # too small and far to measure
        if width_frac >= cfg.large_frac and det.confidence < cfg.large_min_confidence:
            return True   # huge but unsure: probably the bike's own parts
        if det.center_y is not None:
            fx = det.center_x / cfg.frame_width
            fy = det.center_y / cfg.frame_height
            for x1, y1, x2, y2 in cfg.exclude_zones:
                if x1 <= fx <= x2 and y1 <= fy <= y2:
                    return True
        return False

    def _assess(self, det, buf, t) -> Assessment:
        cfg = self.cfg
        window = [s for s in buf if s[0] >= t - cfg.window_s - 1e-9]
        width_frac = window[-1][1]
        side = self._side(det.center_x)

        if len(window) < cfg.min_samples or window[-1][0] - window[0][0] < cfg.min_span_s:
            return Assessment(det.track_id, LEVEL_NONE, None, 0.0, width_frac, side)

        slope, fitted = fit_line(window)
        growing = slope >= cfg.min_growth_per_s and fitted > 0

        # Time to collision. For a vehicle closing at constant speed, 1 / width
        # falls in a straight line, so a line through the inverse width gives an
        # unbiased estimate. (A line through the width itself overestimates the
        # time by about half the window, because width grows faster and faster.)
        ttc = None
        if growing and all(s[1] > 0 for s in window):
            inv_slope, inv_fitted = fit_line([(s[0], 1.0 / s[1]) for s in window])
            if inv_slope < 0 and inv_fitted > 0:
                ttc = inv_fitted / -inv_slope

        level = LEVEL_NONE
        if ttc is not None:
            if ttc < cfg.ttc_urgent_s:
                level = LEVEL_URGENT
            elif ttc < cfg.ttc_warn_s:
                level = LEVEL_WARN
        if level == LEVEL_NONE and growing and fitted >= cfg.close_frac:
            level = LEVEL_GENTLE

        # Passing check: a vehicle far off to the side, measured in its own widths,
        # will go past the bike, not into it.
        # Uses the latest position, not an average, so a car sliding sideways is caught quickly.
        lateral_widths = abs(window[-1][2] - 0.5) / max(fitted, 1e-6)
        if lateral_widths > cfg.max_lateral_widths:
            level = LEVEL_NONE

        return Assessment(det.track_id, level, ttc, slope, fitted, side)

    def _side(self, center_x: float) -> str:
        frac = center_x / self.cfg.frame_width
        if frac < 1 / 3:
            zone = "image_left"
        elif frac > 2 / 3:
            zone = "image_right"
        else:
            return "both"  # directly behind the rider
        flip = self.cfg.mirror
        if zone == "image_left":
            return "right" if flip else "left"
        return "left" if flip else "right"
