# 4sight contracts

The formats every part is built against: rear app, front UI, firmware and the Python harness.

## Rider frame

- `x`: metres sideways, negative = rider's LEFT, positive = rider's RIGHT.
- `z`: metres BEHIND the bike (z = 0 is the rear wheel, larger = further back).
- Perception un-mirrors the camera image. No other module deals with mirroring.
  (In the raw rear-camera image a car on the rider's left appears on the image RIGHT.)

## Rear → front message (`FrameMessage`)

Transport: Network.framework peer-to-peer TCP, Bonjour type `_foursight._tcp`, front phone listens, rear phone connects. One JSON object per line (`\n`-terminated), 10–20 Hz. No video, ever.

```json
{"t":1712.43,"fps":24,"temp":"nominal","speed":5.3,"heading":182.0,"demo":false,
 "merge":{"side":"L","clear":false,"blocked_by":7,"t":1712.40},
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
| `merge` | object \| absent | the most recent merge answer, absent until the rider presses a bar button |
| `merge.side` | string | `L` \| `R`, the lane the rider asked about |
| `merge.clear` | bool | true = safe to move into that lane, false = blocked |
| `merge.blocked_by` | int \| absent | the track id that blocked it, absent when clear |
| `merge.t` | double | rear-phone time the answer was computed |
| `grips` | string \| absent | `connected` \| `searching`: the rear phone's BLE link to the grips (absent from older rear builds) |
| `battery` | double \| absent | rear phone battery 0–1, absent when iOS does not report it |
| `wheel_blocks_view` | bool \| absent | `true` when the bike's own wheel hides over 20% of the camera's view (EgoMask); the front then asks the rider to remount, never mid-ride. Absent otherwise |

The front must show `merge` for 3 s from `merge.t` and then drop it, and must render it
differently from the level colours (a banner on the side asked about, green or red, matching
that handlebar's button LED). An absent `merge` means no answer is current. The field is
optional: a front build that does not know it ignores it.

Rules for the front UI: draw every track; colour by `level`; only the camera's field of view (±35°, 0–40 m behind) is ever drawn.

## Rear ↔ ESP32 (BLE)

- ESP32 is a NimBLE peripheral advertising name `4sight`.
- Service UUID: `5db17fa8-6860-4cd4-bd95-50e90510e072`
- Command characteristic UUID: `2490e4c3-b5b8-40db-8ab6-8cc856e1fa31`, properties: write-without-response, max 4 bytes.
- Event characteristic UUID: `0f343fab-5e83-41a9-afb1-07dc42818c5f`, properties: notify, max 4 bytes. ESP32 → phone.
- The rear phone is a CoreBluetooth central. It writes ASCII strings, no terminator:

| command | meaning |
|---|---|
| `L1` `L2` `L3` | left side, level 1/2/3 |
| `R1` `R2` `R3` | right side, level 1/2/3 |
| `X` | clear both sides immediately |
| `H` | heartbeat, sent every 200 ms whenever connected |
| `GL` `GR` | merge answer: that lane is CLEAR, light the green button LED on that side |
| `NL` `NR` | merge answer: that lane is BLOCKED, light the red button LED on that side |

- The ESP32 owns all patterns (motors and LEDs). Level mapping per side:
  - 1: LED steady, one 300 ms motor pulse
  - 2: LED steady, two 350 ms pulses, 150 ms apart
  - 3: LED flashing 4 Hz, motor 250 ms on / 100 ms off × 4, restarted on each new `3` command
  - LED turns off 2 s after the last command for that side.
- No message of any kind for 0.5 s → "offline" pattern once (400 ms both motors), then everything off.
### Merge check (ESP32 → phone)

Each handlebar has a button with a green and a red LED. Pressing it asks "may I move into the
lane on this side?".

| notify | meaning |
|---|---|
| `ML` | rider pressed the LEFT button, asking about the left lane |
| `MR` | rider pressed the RIGHT button |

- The phone answers with `GL`/`NL` (or `GR`/`NR`) from the most recent frame's tracks.
- The ESP32 lights that side's green or red LED steady for 3 s, then off.
- **No answer within 1.5 s → the ESP32 blinks that side's RED LED at 4 Hz for 3 s.** Unknown is
  never shown as green: a dead phone link, a backgrounded app or a thermal stall must read as
  "do not merge". The red blink is visibly different from a steady red answer.
- Button debounce 25 ms; a press while an answer is already showing on that side restarts it.
- **An answer that arrives after that side's 1.5 s window, or with no press pending, is ignored.**
  The tracks behind a late answer are at least 1.5 s old, about 12 m of closing at city speed, so a
  late `GL` must never replace a red blink with green. The rider presses again for a fresh answer.
- `X` does not touch the merge LEDs, and neither does the offline pattern. Clearing them on a dead
  link would hide the blink that exists precisely to signal a dead link.
- The two sides are independent and may show answers at the same time.
- One red and one green LED per side. Red is shared: a car alert on that side lights it too, and
  cancels a green.

- Never both motor pairs on at the same time (3V3 rail budget); if both sides are commanded, left wins and right is queued.

## ThreatEngine I/O (Swift, pure)

Input per frame: `[TrackState]` + `bikeSpeed` (m/s) + `demoMode` (Bool).
`TrackState`: `id`, `cls`, `z`, `gap` (signed, metres, negative = left), `gapVelocity` (m/s), `invTTC`, `turnR`, `framesSeen`.
Output: `[Decision]`: `id`, `level`, `grip`. Engine keeps per-id memory for alert-once and the 3 s right-hook hold.

Thresholds (constants, tune later): gap alert 1.0 m (1.5 m for bus/truck), caution 1.5 m, a_req imminent 3.0 m/s², debounce 4 frames, slow-vehicle 2.8 m/s (10 km/h), right-hook hold 3.0 s.
