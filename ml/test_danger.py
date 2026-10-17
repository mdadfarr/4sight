"""Tests for danger.py. Run with:  python test_danger.py   (or pytest)

Approaching vehicles are generated from a simple physical model: a vehicle
closing at constant speed, whose box width is proportional to 1 / distance.
That way the expected time to collision is known independently of the code.
"""
from danger import (
    DangerConfig, DangerEngine, Detection,
    LEVEL_NONE, LEVEL_GENTLE, LEVEL_WARN, LEVEL_URGENT,
)

DT = 0.1  # 10 frames per second


def closing_widths(ttc_end, n=6, speed=8.0, k=2000.0):
    """Box widths (px) of a vehicle closing at `speed` m/s, one per frame.

    The last frame is exactly `ttc_end` seconds before it reaches the bike.
    Width = k / distance, so 20 m away gives 100 px with the default k.
    """
    end_distance = ttc_end * speed
    return [k / (end_distance + speed * (n - 1 - i) * DT) for i in range(n)]


def feed(engine, widths, cx=320.0, track_id=1, start=0.0, lateral=None, **det_kw):
    """Feed one vehicle's box widths, one per frame. Returns the last output.

    `lateral` places the vehicle off the camera's centre line, in units of its own
    width (negative = left of the picture). The box centre then moves outward as
    the vehicle grows, exactly as it would for a real vehicle in a fixed lane.
    """
    out = None
    for i, w in enumerate(widths):
        lat = lateral[i] if isinstance(lateral, (list, tuple)) else lateral
        x = 320.0 + lat * w if lat is not None else cx
        out = engine.update(start + i * DT, [Detection(track_id, x, w, **det_kw)])
    return out


def fresh(**kw):
    return DangerEngine(DangerConfig(frame_width=640.0, **kw))


# ---- approaching vehicles -------------------------------------------------

def test_time_to_collision_matches_the_true_value():
    for true_ttc in (1.2, 2.0, 2.5, 4.0):
        out = feed(fresh(), closing_widths(true_ttc))
        # sees nothing when it is far (4 s), otherwise the estimate must be close
        if true_ttc < 3.0:
            assert abs(out.vehicles[0].ttc_s - true_ttc) < 0.1, (true_ttc, out.vehicles[0].ttc_s)


def test_warning_between_two_and_three_seconds():
    out = feed(fresh(), closing_widths(2.5))
    assert out.left == LEVEL_WARN and out.right == LEVEL_WARN  # centre = both handles


def test_urgent_under_two_seconds():
    out = feed(fresh(), closing_widths(1.5))
    assert out.left == LEVEL_URGENT


def test_no_alert_while_still_far():
    out = feed(fresh(), closing_widths(4.0))
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


def test_alert_starts_near_three_seconds_and_gets_stronger():
    # Walk a vehicle in from 40 m at 8 m/s. It reaches the bike at t = 5 s.
    eng = fresh()
    first_warn = first_urgent = None
    for i in range(50):
        t = i * DT
        true_ttc = (40 - 8 * t) / 8
        out = eng.update(t, [Detection(1, 320, 2000 / (40 - 8 * t))])
        if out.left >= LEVEL_WARN and first_warn is None:
            first_warn = true_ttc
        if out.left >= LEVEL_URGENT and first_urgent is None:
            first_urgent = true_ttc
    assert 2.6 < first_warn <= 3.0, first_warn      # warns just under 3 s before impact
    assert 1.6 < first_urgent <= 2.0, first_urgent  # urgent just under 2 s before impact


def test_jittery_widths_use_the_trend_not_the_last_two_frames():
    # Noisy widths from the plan. The last two frames alone (70 to 76) would say
    # 1.3 s; the trend through all six frames says about 2 s.
    out = feed(fresh(), [60, 63, 59, 66, 70, 76])
    v = out.vehicles[0]
    assert 1.8 < v.ttc_s < 2.3, v.ttc_s
    assert out.left >= LEVEL_WARN


# ---- slow and still vehicles ----------------------------------------------

def test_car_creeping_close_gets_the_gentle_level():
    out = feed(fresh(), [390, 392, 394, 396, 398, 400])  # 20 px/s, 62% of the frame
    v = out.vehicles[0]
    assert v.ttc_s > 15                        # time to collision alone would not fire
    assert out.left == LEVEL_GENTLE and out.right == LEVEL_GENTLE


def test_far_creeping_car_gets_nothing():
    out = feed(fresh(), [90, 92, 94, 96, 98, 100])  # 20 px/s but only 16% of the frame
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


def test_stopped_close_car_gets_nothing():
    out = feed(fresh(), [400] * 8)  # red light, not growing
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


def test_receding_car_gets_nothing():
    out = feed(fresh(), [400, 390, 380, 370, 360, 350])
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


# ---- robustness -----------------------------------------------------------

def test_needs_enough_frames_before_alerting():
    out = feed(fresh(), closing_widths(1.5)[:3])  # urgent, but only 3 frames seen
    assert out.left == LEVEL_NONE


def test_untracked_detections_are_ignored():
    eng = fresh()
    out = None
    for i, w in enumerate(closing_widths(1.5)):
        out = eng.update(i * DT, [Detection(-1, 320, w)])
    assert out.left == LEVEL_NONE


def test_resolution_does_not_matter():
    wide = DangerEngine(DangerConfig(frame_width=1280.0))
    out = feed(wide, [2 * w for w in closing_widths(1.5)], cx=640)
    assert out.left == LEVEL_URGENT


# ---- sides ----------------------------------------------------------------

def test_sides_are_flipped_for_a_rear_camera():
    fast = closing_widths(1.5)
    out = feed(fresh(), fast, lateral=-0.8)   # left of the picture = rider's right
    assert out.right == LEVEL_URGENT and out.left == LEVEL_NONE
    out = feed(fresh(), fast, lateral=0.8)    # right of the picture = rider's left
    assert out.left == LEVEL_URGENT and out.right == LEVEL_NONE
    out = feed(fresh(), fast, lateral=0.0)    # middle = directly behind
    assert out.left == LEVEL_URGENT and out.right == LEVEL_URGENT


def test_mirror_can_be_turned_off():
    out = feed(fresh(mirror=False), closing_widths(1.5), lateral=-0.8)
    assert out.left == LEVEL_URGENT and out.right == LEVEL_NONE


def test_two_vehicles_on_opposite_sides_use_both_handles():
    eng = fresh()
    out = None
    for i, w in enumerate(closing_widths(1.5)):
        out = eng.update(i * DT, [Detection(1, 320 - 0.8 * w, w), Detection(2, 320 + 0.8 * w, w)])
    assert out.left == LEVEL_URGENT and out.right == LEVEL_URGENT


# ---- the four filters ------------------------------------------------------

def test_car_in_the_next_lane_is_a_pass_not_a_collision():
    # Same urgent growth, but 1.5 vehicle widths off to the side: it will go past.
    out = feed(fresh(), closing_widths(1.5), lateral=1.5)
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


def test_car_sliding_sideways_across_the_picture_is_ignored():
    # Seen in a real clip: a box that grows fast while sliding from the middle
    # to far off to one side is crossing or passing, not coming at the bike.
    slide = [0.3, 0.5, 0.7, 0.9, 1.2, 1.5]   # off-centre distance in vehicle widths, per frame
    out = feed(fresh(), closing_widths(1.5), lateral=slide)
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


def test_car_close_to_the_centre_line_still_alerts():
    out = feed(fresh(), closing_widths(1.5), lateral=0.5)
    assert out.left == LEVEL_URGENT or out.right == LEVEL_URGENT


def test_tiny_far_boxes_are_ignored():
    tiny = [w * 0.1 for w in closing_widths(1.5)]   # 10 to 17 px on a 640 px frame
    out = feed(fresh(), tiny)
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


def test_a_video_cut_does_not_cause_an_alert():
    # A steady small box, then the picture cuts and the box is suddenly 5 times wider.
    eng = fresh()
    feed(eng, [60.0] * 8)
    out = feed(eng, [300.0] * 3, start=8 * DT)   # only 3 frames after the cut
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE


def test_the_cut_rule_is_what_prevents_that_alert():
    # Guard for the test above: switch the reset rule off and the same video cut
    # does produce an alert. So the test passes because of the rule, not by luck.
    eng = DangerEngine(DangerConfig(frame_width=640.0, jump_ratio=1e9))
    feed(eng, [60.0] * 8)
    out = feed(eng, [300.0] * 3, start=8 * DT)
    assert out.left >= LEVEL_WARN or out.right >= LEVEL_WARN


def test_detections_in_an_exclusion_zone_are_ignored():
    big = closing_widths(1.5, k=4000.0)   # ends at 333 px, about half the frame
    zone = DangerConfig(frame_width=640.0, frame_height=360.0, exclude_zones=[(0.0, 0.5, 1.0, 1.0)])
    # centre of the box at the bottom of the picture, inside the zone
    out = feed(DangerEngine(zone), big, cx=320.0, center_y=300.0)
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE
    # same box, higher up in the picture, outside the zone
    out = feed(DangerEngine(zone), big, cx=320.0, center_y=100.0)
    assert out.left == LEVEL_URGENT


def test_huge_unsure_boxes_are_ignored_but_huge_sure_ones_are_not():
    big = closing_widths(1.5, k=6000.0)   # 375 to 500 px, 59% to 78% of the frame in every frame
    out = feed(fresh(), big, confidence=0.35)
    assert out.left == LEVEL_NONE and out.right == LEVEL_NONE
    out = feed(fresh(), big, confidence=0.9)
    assert out.left == LEVEL_URGENT


# ---- timing ---------------------------------------------------------------

def test_alert_is_held_for_a_second_then_released():
    eng = fresh()
    feed(eng, closing_widths(1.5), lateral=-0.8)       # alert on the right at t = 0.5
    assert eng.update(1.0, []).right == LEVEL_URGENT   # vehicle gone, still held
    assert eng.update(1.4, []).right == LEVEL_URGENT
    assert eng.update(1.6, []).right == LEVEL_NONE     # hold of 1 s is over


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
