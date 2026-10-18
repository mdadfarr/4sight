"""Validation of app uploads, no database needed.
  uv run --with 'psycopg[binary]' server/test_store.py"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "api"))
from _store import Invalid, validate  # noqa: E402

NOW = 1_792_332_200.0
GOOD = {"install": "6f1c0a4e-1b2c-4d5e-8f90-123456789abc", "app": "4sight/1.0", "demo": True,
        "started": "2026-10-18T14:02:01Z", "ended": "2026-10-18T14:21:40Z",
        "points": [[1792332121.0, 43.78512, -79.18731, 4.1], [1792332122.0, 43.78515, -79.18735, 4.2]],
        "events": [{"t": 1792332121.4, "lat": 43.78601, "lon": -79.18902, "cls": "car", "level": 2,
                    "side": "L", "gap_m": 0.8, "ttc_s": None, "speed": 4.3}]}


def rejects(change, too_large=False):
    body = {**GOOD, **change}
    try:
        validate(json.dumps(body).encode(), NOW)
    except Invalid as e:
        return e.too_large == too_large
    return False


ok = validate(json.dumps(GOOD).encode(), NOW)
assert ok["demo"] is True and len(ok["points"]) == 2 and ok["events"][0]["ttc_s"] is None
assert rejects({"install": "not-a-uuid"})
assert rejects({"demo": "yes"})
assert rejects({"points": []})
assert rejects({"points": [[1792332121.0, 45.5, -79.18, 4]]}), "outside the GTA"
assert rejects({"points": [[NOW - 8 * 86400, 43.78, -79.18, 4]]}), "older than 7 days"
assert rejects({"points": [[NOW + 3600, 43.78, -79.18, 4]]}), "in the future"
assert rejects({"events": [{**GOOD["events"][0], "level": 1}]})
assert rejects({"events": [{**GOOD["events"][0], "cls": "tram"}]})
assert rejects({"events": [{**GOOD["events"][0], "lat": "43.7"}]})
assert rejects({"points": GOOD["points"] * 10_001}, too_large=True)
assert rejects({"events": GOOD["events"] * 501}, too_large=True)
try:
    validate(b"x" * 1_000_001, NOW)
    raise AssertionError("1 MB limit")
except Invalid as e:
    assert e.too_large
print("store validation: all checks passed")
