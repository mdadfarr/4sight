#!/usr/bin/env python3
"""Turn a ROS 2 .mcap bag into 4sight ride footage: mp4 + GPS jsonl + camera intrinsics.

Usage:
    uv run tools/mcap_to_ride.py bag.mcap --camera ss --out out/ [--start S --duration S] [--fps 20]

Outputs ride-<bagname>.mp4, ride-<bagname>.jsonl (same fields RideLogger.swift writes, with t
measured from the first video frame instead of systemUptime) and ride-<bagname>.camera.json.
Streams the bag; never loads it whole.

Drop all three next to each other on the phone or in the Simulator and pick the .mp4 with
"Replay file…" in RearView: FileSource reads the two sidecars by name, so the pipeline gets the
real focal length and lens height instead of f ≈ 0.9 × width, and the recorded speed and heading
instead of zero. Renaming the .mp4 alone breaks that link.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from mcap_ros2.reader import read_ros2_messages

MAX_WIDTH = 1280


def open_writer(path, fps, size):
    for codec in ("avc1", "mp4v"):
        w = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*codec), fps, size)
        if w.isOpened():
            print(f"video codec: {codec}")
            return w
    raise SystemExit("no usable mp4 codec in this OpenCV build")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bag", type=Path)
    ap.add_argument("--camera", default="ss", help="pano camera suffix (ss = rear)")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--start", type=float, default=0.0, help="seconds into the bag")
    ap.add_argument("--duration", type=float, default=None, help="seconds to extract")
    ap.add_argument("--fps", type=float, default=None, help="override output fps (default: measured)")
    ap.add_argument("--camera-height", type=float, default=1.0,
                    help="lens height above the road in metres (bike mount 1.0, car roof rig ~1.4). "
                         "GapEstimator's ground-plane range scales with it")
    args = ap.parse_args()

    img_topic = f"/camera_pano_{args.camera}/image_rect_compressed"
    info_topic = f"/camera_pano_{args.camera}/camera_info"
    gps_topic = "/novatel/oem7/gps"
    args.out.mkdir(parents=True, exist_ok=True)
    base = args.out / f"ride-{args.bag.stem}"

    # One pass to learn the bag's first timestamp: the summary index is cheap to read.
    first_ns = next(read_ros2_messages(str(args.bag), topics=[img_topic])).log_time_ns
    t0_ns = first_ns + int(args.start * 1e9)
    t1_ns = t0_ns + int(args.duration * 1e9) if args.duration else None

    frames, stamps, gps_lines = [], [], []  # frames buffered only until fps is known
    writer, scale, size = None, 1.0, None
    intr = None
    video_t0 = None
    n_frames = 0

    for m in read_ros2_messages(str(args.bag), topics=[img_topic, info_topic, gps_topic],
                                start_time=t0_ns, end_time=t1_ns):
        msg, t = m.ros_msg, m.log_time_ns / 1e9
        if m.channel.topic == info_topic:
            if intr is None:
                k = msg.k
                intr = {"f": k[0], "u0": k[2], "v0": k[5], "width": msg.width, "height": msg.height}
            continue
        if m.channel.topic == gps_topic:
            if video_t0 is None:
                continue  # jsonl t is relative to the first video frame
            heading = msg.track if getattr(msg, "track", None) is not None else -1
            gps_lines.append({"t": round(t - video_t0, 3), "lat": msg.latitude, "lon": msg.longitude,
                              "speed": msg.speed, "heading": heading})
            continue

        img = cv2.imdecode(np.frombuffer(msg.data, np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            continue
        if video_t0 is None:
            video_t0 = t
            h, w = img.shape[:2]
            scale = min(1.0, MAX_WIDTH / w)
            size = (int(round(w * scale)), int(round(h * scale)))
        if scale < 1.0:
            img = cv2.resize(img, size, interpolation=cv2.INTER_AREA)
        stamps.append(t)
        if writer is None:
            frames.append(img)
            # Measure the camera's real rate from the first 40 stamps, then open the writer.
            if args.fps or len(frames) >= 40:
                fps = args.fps or (len(stamps) - 1) / (stamps[-1] - stamps[0])
                writer = open_writer(base.with_suffix(".mp4"), fps, size)
                for f in frames:
                    writer.write(f)
                n_frames += len(frames)
                frames = []
            continue
        writer.write(img)
        n_frames += 1

    if writer is None:  # short clip: fewer than 40 frames
        if not frames:
            raise SystemExit(f"no frames on {img_topic} in the requested window")
        fps = args.fps or (len(stamps) - 1) / max(stamps[-1] - stamps[0], 1e-6)
        writer = open_writer(base.with_suffix(".mp4"), fps, size)
        for f in frames:
            writer.write(f)
        n_frames = len(frames)
    writer.release()
    # Self-check: a silently failed codec writes a file OpenCV cannot read back.
    assert int(cv2.VideoCapture(str(base.with_suffix(".mp4"))).get(cv2.CAP_PROP_FRAME_COUNT)) == n_frames, "mp4 unreadable"

    duration = stamps[-1] - stamps[0]
    with open(base.with_suffix(".jsonl"), "w") as f:
        for line in gps_lines:
            f.write(json.dumps(line) + "\n")

    if intr is None:
        print(f"warning: no {info_topic} in window; camera.json has no intrinsics")
        intr = {}
    else:
        intr = {k: (v * scale if k in ("f", "u0", "v0") else int(round(v * scale))) for k, v in intr.items()}
    cam = {**intr, "camera_height": args.camera_height, "frames": n_frames, "fps": fps,
           "duration": round(duration, 3), "source": args.bag.name}
    with open(base.parent / f"{base.name}.camera.json", "w") as f:
        json.dump(cam, f, indent=2)

    print(f"frames: {n_frames}  fps: {fps:.2f}  duration: {duration:.1f}s  gps fixes: {len(gps_lines)}")
    print(f"intrinsics: {intr}")
    print(f"wrote {base}.mp4 / .jsonl / .camera.json")


if __name__ == "__main__":
    main()
