"""Run the vehicle detector on a video and save what it sees.

Usage:
    python detect_video.py my_clip.mp4
    python detect_video.py my_clip.mp4 --model yolo11n.pt --conf 0.35

Outputs (next to the video, in a folder called out/):
    <name>_annotated.mp4   the video with boxes and track ids drawn on
    <name>_boxes.csv       one row per vehicle per frame

The CSV is what the time to collision step reads later: for each tracked
vehicle, how wide its box is in every frame.
"""
import argparse
import csv
from pathlib import Path

import cv2
from ultralytics import YOLO

# COCO class ids for the vehicles we care about.
VEHICLE_CLASSES = {2: "car", 3: "motorcycle", 5: "bus", 7: "truck"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video", help="path to a video file")
    parser.add_argument("--model", default="yolo11n.pt", help="weights file")
    parser.add_argument("--conf", type=float, default=0.35, help="min confidence")
    parser.add_argument("--imgsz", type=int, default=640, help="inference size")
    args = parser.parse_args()

    video = Path(args.video)
    out_dir = video.parent / "out"
    out_dir.mkdir(exist_ok=True)

    model = YOLO(args.model)

    # Read the clip's frame rate and size, so later steps can turn frame numbers into seconds.
    cap = cv2.VideoCapture(str(video))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frame_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    frame_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()

    # model.track runs the detector and also follows each vehicle across
    # frames, giving every one a stable id. stream=True keeps memory low.
    results = model.track(
        source=str(video),
        classes=list(VEHICLE_CLASSES),
        conf=args.conf,
        imgsz=args.imgsz,
        persist=True,
        stream=True,
        verbose=False,
    )

    csv_path = out_dir / f"{video.stem}_boxes.csv"
    writer_video = None

    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "frame", "track_id", "class", "conf", "x1", "y1", "x2", "y2",
                "width", "center_x", "time_s", "frame_w", "fps", "frame_h",
            ]
        )
        for frame_idx, result in enumerate(results):
            frame = result.plot()  # frame with boxes drawn on

            if writer_video is None:
                h, w = frame.shape[:2]
                writer_video = cv2.VideoWriter(
                    str(out_dir / f"{video.stem}_annotated.mp4"),
                    cv2.VideoWriter_fourcc(*"mp4v"),
                    fps,
                    (w, h),
                )
            writer_video.write(frame)

            boxes = result.boxes
            if boxes is None or len(boxes) == 0:
                continue
            ids = boxes.id.int().tolist() if boxes.id is not None else [-1] * len(boxes)
            for tid, cls, conf, xyxy in zip(
                ids, boxes.cls.int().tolist(), boxes.conf.tolist(), boxes.xyxy.tolist()
            ):
                x1, y1, x2, y2 = xyxy
                writer.writerow(
                    [
                        frame_idx,
                        tid,
                        VEHICLE_CLASSES.get(cls, cls),
                        round(conf, 3),
                        round(x1, 1),
                        round(y1, 1),
                        round(x2, 1),
                        round(y2, 1),
                        round(x2 - x1, 1),
                        round((x1 + x2) / 2, 1),
                        round(frame_idx / fps, 4),
                        frame_w,
                        round(fps, 3),
                        frame_h,
                    ]
                )

    if writer_video is not None:
        writer_video.release()
    print(f"Done. See {out_dir}")


if __name__ == "__main__":
    main()
