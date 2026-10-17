# 4sight firmware (ESP32-WROOM-32, PlatformIO + Arduino)

BLE protocol and patterns are defined in `../docs/CONTRACTS.md`.

## Wiring

| GPIO | Part |
|---|---|
| 25 | Left motor 1 (via NPN/MOSFET low-side switch) |
| 26 | Left motor 2 (via NPN/MOSFET low-side switch) |
| 32 | Right motor 1 (via NPN/MOSFET low-side switch) |
| 33 | Right motor 2 (via NPN/MOSFET low-side switch) |
| 27 | Left amber LED, 220 Ω to GND |
| 14 | Right amber LED, 220 Ω to GND |

Motors are PWM at 200 Hz, duty capped at 80 %. Left and right pairs never run together.

## Build / flash / monitor

```sh
pio run
pio run -t upload
pio device monitor
```

In the monitor (115200 baud) type `L1`, `R3`, `X` etc. + Enter to trigger patterns without a phone.

## Test with nRF Connect

1. Scan and connect to `4sight`.
2. Open service `5db17fa8-6860-4cd4-bd95-50e90510e072`, characteristic `2490e4c3-b5b8-40db-8ab6-8cc856e1fa31`.
3. Write text (UTF-8) `L2`.
4. Expect two left pulses and the left LED on; the LED goes off 2 s later.
5. With no further writes for 0.5 s the board plays the 400 ms "offline" pulse once (left, then right).
