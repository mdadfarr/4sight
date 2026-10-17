"""Tests for tracker.py. Run with:  python test_tracker.py   (or pytest)"""
from tracker import Box, SimpleTracker, iou


def car(cx, half):
    return Box(cx - half, 100, cx + half, 100 + half)


def test_iou_basics():
    assert iou(Box(0, 0, 10, 10), Box(0, 0, 10, 10)) == 1.0
    assert iou(Box(0, 0, 10, 10), Box(20, 20, 30, 30)) == 0.0
    assert abs(iou(Box(0, 0, 10, 10), Box(5, 0, 15, 10)) - 1 / 3) < 1e-9


def test_a_growing_car_keeps_its_id():
    tr = SimpleTracker()
    ids = [tr.update([car(300, 30 + 4 * i)])[0] for i in range(10)]
    assert len(set(ids)) == 1


def test_two_cars_keep_separate_ids():
    tr = SimpleTracker()
    first = tr.update([car(100, 30), car(500, 30)])
    for i in range(1, 6):
        ids = tr.update([car(100 + 2 * i, 30 + i), car(500 - 2 * i, 30 + i)])
    assert ids == first and first[0] != first[1]


def test_a_new_car_gets_a_new_id():
    tr = SimpleTracker()
    a = tr.update([car(100, 30)])[0]
    ids = tr.update([car(102, 31), car(500, 30)])
    assert ids[0] == a and ids[1] != a


def test_a_car_can_vanish_briefly_and_keep_its_id():
    tr = SimpleTracker(max_missed=5)
    a = tr.update([car(300, 40)])[0]
    for _ in range(3):
        tr.update([])
    assert tr.update([car(302, 41)])[0] == a


def test_a_car_gone_too_long_gets_a_new_id():
    tr = SimpleTracker(max_missed=5)
    a = tr.update([car(300, 40)])[0]
    for _ in range(7):
        tr.update([])
    assert tr.update([car(302, 41)])[0] != a


if __name__ == "__main__":
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_")]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print("ok   ", name)
        except AssertionError as e:
            failed += 1
            print("FAIL ", name, e)
    print(f"\n{len(tests) - failed} of {len(tests)} passed")
    raise SystemExit(1 if failed else 0)
