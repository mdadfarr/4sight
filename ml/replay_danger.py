"""Replay a clip's detections through the danger logic.

Usage:
    python detect_video.py my_clip.mp4          (makes out/my_clip_boxes.csv)
    python replay_danger.py out/my_clip_boxes.csv
    python replay_danger.py out/my_clip_boxes.csv --exclude 0.4,0,1,1

Prints a line each time the alert level changes, and writes
out/my_clip_alerts.csv with the left and right level for every frame.
Use it to tune the thresholds in danger.py on your own footage.

--exclude x1,y1,x2,y2   an exclusion zone as fractions of the frame (0 to 1),
                        where the bike's own parts appear. Detections whose
                        centre is inside are ignored. Can be repeated.
"""
import argparse
import csv
from collections import defaultdict
from pathlib import Path

from danger import DangerConfig, DangerEngine, Detection

NAMES = {0: "none", 1: "gentle", 2: "WARNING", 3: "URGENT"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("boxes_csv")
    parser.add_argument("--no-mirror", action="store_true", help="camera is not rear facing")
    parser.add_argument("--exclude", action="append", default=[], metavar="x1,y1,x2,y2")
    args = parser.parse_args()

    zones = [tuple(float(v) for v in z.split(",")) for z in args.exclude]

    path = Path(args.boxes_csv)
    by_frame = defaultdict(list)
    fps = frame_w = frame_h = None
    last_frame = 0
    with open(path) as f:
        for row in csv.DictReader(f):
            fps = float(row["fps"])
            frame_w = float(row["frame_w"])
            # older CSVs have no frame_h; assume a 16:9 picture
            frame_h = float(row.get("frame_h") or frame_w * 9 / 16)
            n = int(row["frame"])
            last_frame = max(last_frame, n)
            by_frame[n].append(Detection(
                int(row["track_id"]),
                float(row["center_x"]),
                float(row["width"]),
                center_y=(float(row["y1"]) + float(row["y2"])) / 2,
                confidence=float(row["conf"]),
            ))

    if fps is None:
        print("No vehicles detected in this clip.")
        return

    engine = DangerEngine(DangerConfig(
        frame_width=frame_w, frame_height=frame_h, mirror=not args.no_mirror, exclude_zones=zones,
    ))
    out_path = path.with_name(path.name.replace("_boxes", "_alerts"))
    prev = (0, 0)
    events = 0
    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["frame", "time_s", "left", "right", "ttc_s", "track_id"])
        # run a little past the last frame so the final hold plays out
        for n in range(last_frame + int(fps * 1.5) + 1):
            t = n / fps
            result = engine.update(t, by_frame.get(n, []))
            worst = max(result.vehicles, key=lambda v: v.level, default=None)
            ttc = round(worst.ttc_s, 2) if worst and worst.ttc_s else ""
            writer.writerow([n, round(t, 3), result.left, result.right, ttc, worst.track_id if worst else ""])
            now = (result.left, result.right)
            if now != prev:
                if prev == (0, 0):
                    events += 1
                print(f"t={t:6.2f}s  left={NAMES[result.left]:8s} right={NAMES[result.right]:8s}"
                      + (f"  ttc={ttc}s  vehicle #{worst.track_id}" if worst else ""))
                prev = now
    print(f"{events} alert episode(s). Wrote {out_path}")


if __name__ == "__main__":
    main()
