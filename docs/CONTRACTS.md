# 4sight contracts (frozen)

Change nothing here without telling the whole team. Everything downstream (rear app, front UI, firmware, Python harness) is built against this file.

## Rider frame

- `x`: metres sideways, negative = rider's LEFT, positive = rider's RIGHT.
- `z`: metres BEHIND the bike (z = 0 is the rear wheel, larger = further back).
- Perception un-mirrors the camera image. No other module deals with mirroring.
  (In the raw rear-camera image a car on the rider's left appears on the image RIGHT.)

## Rear → front message (`FrameMessage`)

Transport: Network.framework peer-to-peer TCP, Bonjour type `_foursight._tcp`, front phone listens, rear phone connects. One JSON object per line (`\n`-terminated), 10–20 Hz. No video, ever.

```json
{"t":1712.43,"fps":24,"temp":"nominal","speed":5.3,"heading":182.0,"demo":false,
 "tracks":[{"id":7,"cls":"car","x":-1.4,"z":18.2,"inv_ttc":0.21,
            "gap_pred":0.8,"level":2,"grip":"L","turn_r":false}]}
```

| field | type | meaning |
|---|---|---|
| `t` | double | seconds, monotonic, rear phone clock |
| `fps` | int | detection fps on the rear phone |
| `temp` | string | `nominal` \| `fair` \| `serious` \| `critical` (ProcessInfo.thermalState) |
| `speed` | double | bike ground speed, m/s, from GPS (0 if unknown) |
| `heading` | double | degrees true, 0–360, from GPS (−1 if unknown) |
| `demo` | bool | demo mode on (bicycles and people count as threats) |
| `tracks[].id` | int | stable track id, reused only after 60 s |
| `tracks[].cls` | string | `car` \| `truck` \| `bus` \| `motorcycle` \| `bicycle` \| `person` |
| `tracks[].x` | double | rider frame, metres |
| `tracks[].z` | double | rider frame, metres |
| `tracks[].inv_ttc` | double | 1/TTC in 1/s; > 0 closing, ≈ 0 pacing, < 0 falling behind |
| `tracks[].gap_pred` | double | predicted sideways passing gap, metres (absolute value) |
| `tracks[].level` | int | 0 map only, 1 caution, 2 threat, 3 imminent |
| `tracks[].grip` | string | `L` \| `R` \| `-` which grip (if any) this track is alerting |
| `tracks[].turn_r` | bool | vehicle's right turn signal detected (right-hook risk) |

Rules for the front UI: draw every track; colour by `level`; only the camera's field of view (±35°, 0–40 m behind) is ever drawn.

## Rear → ESP32 (BLE)

- ESP32 is a NimBLE peripheral advertising name `4sight`.
- Service UUID: `5db17fa8-6860-4cd4-bd95-50e90510e072`
- Command characteristic UUID: `2490e4c3-b5b8-40db-8ab6-8cc856e1fa31`, properties: write-without-response, max 4 bytes.
- The rear phone is a CoreBluetooth central. It writes ASCII strings, no terminator:

| command | meaning |
|---|---|
| `L1` `L2` `L3` | left side, level 1/2/3 |
| `R1` `R2` `R3` | right side, level 1/2/3 |
| `X` | clear both sides immediately |
| `H` | heartbeat, sent every 200 ms whenever connected |

- The ESP32 owns all patterns (motors and LEDs). Level mapping per side:
  - 1: LED steady, one 150 ms motor pulse
  - 2: LED steady, two 120 ms pulses, 100 ms apart
  - 3: LED flashing 4 Hz, motor 100 ms on / 80 ms off × 4, restarted on each new `3` command
  - LED turns off 2 s after the last command for that side.
- No message of any kind for 0.5 s → "offline" pattern once (400 ms both motors), then everything off.
- Never both motor pairs on at the same time (3V3 rail budget); if both sides are commanded, left wins and right is queued.

## ThreatEngine I/O (Swift, pure)

Input per frame: `[TrackState]` + `bikeSpeed` (m/s) + `demoMode` (Bool).
`TrackState`: `id`, `cls`, `z`, `gap` (signed, metres, negative = left), `gapVelocity` (m/s), `invTTC`, `turnR`, `framesSeen`.
Output: `[Decision]`: `id`, `level`, `grip`. Engine keeps per-id memory for alert-once and the 3 s right-hook hold.

Thresholds (constants, tune later): gap alert 1.0 m (1.5 m for bus/truck), caution 1.5 m, a_req imminent 3.0 m/s², debounce 4 frames, slow-vehicle 2.8 m/s (10 km/h), right-hook hold 3.0 s.
