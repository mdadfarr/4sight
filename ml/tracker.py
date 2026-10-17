"""A very small vehicle tracker.

The detector only says "there are boxes in this frame". The danger logic needs
to know that a box in this frame is the same car as a box in the last frame.
This matches boxes between consecutive frames by how much they overlap
(intersection over union), and gives each car an id that stays the same.

A car approaching the camera grows, but its new box still contains most of the
old one, so the overlap stays high and the id holds.
"""
from dataclasses import dataclass


@dataclass
class Box:
    x1: float
    y1: float
    x2: float
    y2: float

    @property
    def width(self) -> float:
        return self.x2 - self.x1

    @property
    def center_x(self) -> float:
        return (self.x1 + self.x2) / 2


def iou(a: Box, b: Box) -> float:
    iw = max(0.0, min(a.x2, b.x2) - max(a.x1, b.x1))
    ih = max(0.0, min(a.y2, b.y2) - max(a.y1, b.y1))
    inter = iw * ih
    union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter
    return inter / union if union > 0 else 0.0


class SimpleTracker:
    def __init__(self, iou_threshold: float = 0.3, max_missed: int = 5):
        self.iou_threshold = iou_threshold
        self.max_missed = max_missed      # frames a car may vanish and still keep its id
        self._tracks = {}                 # id -> [last box, frames missed]
        self._next_id = 1

    def update(self, boxes):
        """Takes this frame's boxes, returns one id per box (same order)."""
        pairs = sorted(
            ((iou(box, track[0]), bi, tid)
             for bi, box in enumerate(boxes)
             for tid, track in self._tracks.items()),
            reverse=True,
        )
        ids = [None] * len(boxes)
        used = set()
        for score, bi, tid in pairs:   # best overlaps first
            if score < self.iou_threshold:
                break
            if ids[bi] is None and tid not in used:
                ids[bi] = tid
                used.add(tid)

        for tid in list(self._tracks):  # age tracks nobody claimed
            if tid not in used:
                self._tracks[tid][1] += 1
                if self._tracks[tid][1] > self.max_missed:
                    del self._tracks[tid]

        for bi, box in enumerate(boxes):
            if ids[bi] is None:
                ids[bi] = self._next_id
                self._next_id += 1
            self._tracks[ids[bi]] = [box, 0]
        return ids
