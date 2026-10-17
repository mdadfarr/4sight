# 4sight firmware (ESP32-WROOM-32, PlatformIO + Arduino)

BLE protocol and patterns are defined in `../docs/CONTRACTS.md`.

## Wiring

| GPIO | Part |
|---|---|
| 25 | Left motor: 1 kΩ to a 2N2222A base; emitter to GND, collector to the motor's blue wire |
| 26 | Right motor: same as left |
| 18 | Left green LED, 150 Ω, LED to GND |
| 19 | Left red LED, 150 Ω, LED to GND |
| 22 | Right green LED, 150 Ω, LED to GND |
| 23 | Right red LED, 150 Ω, LED to GND |
| 32 | Left merge button, other leg to GND (INPUT_PULLUP, pressed = LOW) |
| 33 | Right merge button, other leg to GND (INPUT_PULLUP, pressed = LOW) |

Each 3 V coin motor (85 mA): red wire to 3V3, blue wire to the transistor's collector, a
1N4007 across the motor with the stripe to 3V3. Power bank → USB-C → the board's 3V3 rail.
Leave RX0, TX0, D2, D5, D12, D15 and D21 free.

Motors are PWM at 200 Hz, duty capped at 80 %, and the two sides never run together.
Green lights only for a clear merge answer. Red lights for a blocked answer (with two
pulses on that grip), for no answer within 1.5 s (blinking), or for a car alert on that
side (steady; flashing at level 3).

## Build / flash / monitor

```sh
pio run
pio run -t upload
pio device monitor
```

In the monitor (115200 baud) type `L1`, `R3`, `X`, `GL`, `NR` etc. + Enter to trigger patterns
without a phone. A button press prints `merge: ML` / `merge: MR`.

`pio run` builds against Arduino-ESP32 core 2.x. `pio run -e esp32dev-core3` builds the same code
against core 3.x (pioarduino), the version the newest Arduino IDE installs.

### Or flash with Arduino IDE 2 (what Mohammad already has working)

Same board setup as Mohammad's web-server guide (data cable, `cu.` port, hold BOOT if it sticks on
"Connecting..."). Two differences:

1. **Library Manager → install `NimBLE-Arduino` by h2zero, version 2.x.** Any esp32 board package
   version works (2.x or 3.x); the motor PWM calls are version-guarded.
2. **File → Open → `firmware/foursight/foursight.ino`** (the repo's own sketch, no copying), board **ESP32 Dev
   Module** (DOIT DEVKIT V1 works), Upload, then Serial Monitor at 115200.

## How the rear phone talks to the ESP32: Bluetooth LE, not Wi-Fi

The ESP32 advertises as `4sight`. The rear phone's app finds it and connects by itself; do **not** pair
it in iOS Settings → Bluetooth (apps connect directly, and a Settings pairing can get in the way).
The rear screen's `BLE` line goes `scanning` → `connected`. Commands flow phone → ESP32 on the command
characteristic, button presses flow back on the event characteristic (docs/CONTRACTS.md).

Why not the Wi-Fi web server: on a bike there is no router, so the rear phone would have to run a
Personal Hotspot for the whole ride (needs a plan that allows it, turns itself off when idle, and the
ESP32 only joins while the hotspot screen is open). The ESP32's address changes on restart, and a
button press would need the phone to poll. BLE needs no network, no address and no hotspot. Both use
the same 2.4 GHz antenna, so the metal-box rule (antenna end outside the box) is the same either way.

A teammate did have the Wi-Fi web server working on an iPhone hotspot; BLE won because it needs no
network join, so the rider never leaves the app.

## Test with nRF Connect

1. Scan and connect to `4sight`.
2. Open service `5db17fa8-6860-4cd4-bd95-50e90510e072`, characteristic `2490e4c3-b5b8-40db-8ab6-8cc856e1fa31`.
3. Write text (UTF-8) `L2`.
4. Expect two left pulses and the left LED on; the LED goes off 2 s later.
5. With no further writes for 0.5 s the board plays the 400 ms "offline" pulse once (left, then right).

## Test the merge flow with nRF Connect

1. Connect to `4sight` and open service `5db17fa8-6860-4cd4-bd95-50e90510e072`.
2. On the event characteristic `0f343fab-5e83-41a9-afb1-07dc42818c5f`, tap the subscribe
   (three arrows) icon to enable notifications.
3. Press the left handlebar button. nRF Connect shows a notify of `ML` (`MR` for the right one).
4. Within 1.5 s, write text (UTF-8) `GL` to the command characteristic
   `2490e4c3-b5b8-40db-8ab6-8cc856e1fa31`. The left green LED goes steady for 3 s, then off.
   Write `NL` instead and the left red LED goes steady for 3 s.
5. Press the button and write nothing. After 1.5 s the left red LED blinks at 4 Hz for 3 s.
   This is the safety default: an unanswered merge check never shows green.
6. Press the button again while an answer is showing and that side restarts from step 3.
