---
name: 4sight-front
description: Build and iterate the 4sight front-phone SwiftUI display (rear surround view + bike nav HUD) via screenshot-verified PRs
---

# 4sight front-phone UI

You build ONE thing: the SwiftUI screen on the phone in the handlebar mount. It shows what is
behind the bike plus cycling navigation. You ship one small PR at a time with simulator
screenshots, and a human approves each one. Nothing else is your job.

Read `docs/CONTRACTS.md` first. The `FrameMessage` JSON there is what you render. It is frozen.

## Data you consume

Swift types live in the local package `FourSightKit`, target `Protocol`: `FrameMessage`,
`TrackMessage`, `VehicleClass`. Another agent writes it. At session start run
`grep -rn "struct FrameMessage\|struct TrackMessage\|enum VehicleClass\|PeerLink" FourSightKit/Sources`
and use the exact names and property spellings you find. If the package is missing, stop and tell the human.

Rider frame: `x` metres sideways (negative = rider's LEFT), `z` metres BEHIND the bike.
Screen mapping: bike glyph at bottom centre, +z goes UP the screen, +x goes RIGHT.

Fields that drive drawing: `tracks[].cls`, `x`, `z`, `level` (0–3), `turn_r`. Status strip
uses `fps`, `temp`, `speed` (m/s, show km/h), plus link state. Ignore `inv_ttc`, `gap_pred`,
`grip`, `heading`, `demo` on screen.

## Design brief

**Source of truth: `docs/mock/front.html`.** Open it in a browser and scrub, or render stills
with `node docs/mock/shot.mjs <t...>` (see `docs/mock/README.md`). It is Canvas2D on purpose:
every call maps to SwiftUI `GraphicsContext`, so port it, do not reinterpret it. When this text
and the mock disagree, the mock wins. Constants to copy exactly: `CAM`, `FOV`, `ROAD`, `BAND`,
the colour table `C`, and the scenario `CUES`.

Decided with the owner on 2026-10-17, after several rejected passes:

- **Camera: a real pinhole following the rider**, 26 m up, 8 m behind, tilted 20° forward,
  pinned so the rider sits at y=430 and the road 20 m behind lands at y=752. It shows ~25 m
  ahead (the route and the next turn) while a car 20 m back is drawn only ~1.34x true size.
  More tilt (the Apple Maps look) oversizes rear traffic 1.6-2x: rejected. Do NOT use a fake
  projection (separate x and y curves); it shears. Everything goes through one `pt(x, z, h)`.
- **Screen up = the way you are going; screen down = the road behind; rider centred left-right.**
- **Light world, Tesla clay style**: light ground, grey extruded vehicles (body box + greenhouse).
  Map data (streets, crossings, low blocks, park, labels) is drawn everywhere.
- **Detections only inside the rear camera's wedge** (±35°, 0-40 m behind, CONTRACTS.md).
  Nothing is ever drawn beside or ahead of the rider. The wedge is lightened, not the rest dimmed.
- **The vehicles carry the alert**: grey, amber fill at level 2, red fill + glow at level 3.
- **Pedestrians and cyclists are upright figures** (Tesla style), 1.6x scale, white halo,
  ground ring at level 3. Grey unless `demo` is true, matching ThreatEngine.
- **You are a nav puck** (white-collared blue disc, chevron up), not a bike drawing.
- **Blue route ribbon** (Apple Maps): solid ahead and turning where you turn, fading behind.
- **Screen-edge alert, drawn last over everything**, on the side of the grip that is buzzing,
  flashing the grip's own beat from CONTRACTS.md: one 150 ms pulse at level 1, two 120 ms pulses
  100 ms apart at level 2, 4 Hz sustained at level 3. Band width 46 / 88 / 150 pt. A track
  within 0.8 m of centre (straight behind) lights all four edges.
- **Nav chrome**: black manoeuvre banner, flat bottom edge, 190 pt: arrow, distance (36 pt bold),
  street, then a `Then` row with the step after. Speed badge and route/mute buttons float over
  the map. White arrival bar: arrival / min / km.

Rules: SF Symbols for icons where one exists, system fonts, no image assets, no third-party
packages. Tap targets ≥ 44 pt.

## Architecture

All files under `4sight/Front/` (synchronized folder: files appear in the build automatically).
Never edit `project.pbxproj`. Keep every file under 300 lines. SwiftUI only. iOS 26 target.

Views:
- `FrontRootView` composes the banner, the map and the arrival bar, and picks the feed from
  launch arguments.
- `SurroundView` is a `Canvas` inside a `TimelineView(.periodic(from: .now, by: 1/20))`. Keep the
  vehicle rendering: the follow view needs it. Port the projection and drawing from the mock.
- `NavHUDView`, `StatusStripView`, `DestinationPickerView` (search field + results list).

Data:
- `FrontModel: ObservableObject`. Holds the latest `FrameMessage`, per-id interpolated positions
  (previous, target, target time), link state, nav state. Interpolation: fraction =
  clamp((now − targetTime + 0.1) / 0.1, 0, 1).
- `protocol TrackFeed { var frames: AsyncStream<FrameMessage> { get }; func start(); func stop() }`.
- `PeerFeed` wraps the package's front-side `PeerLink`. Do not modify the package; if its API
  does not fit, adapt in `PeerFeed`.
- `SyntheticFeed` emits 20 Hz scripted frames from a clock `t`. Scenario 0 (default), looping:
  1. t 0–6 s: car at x = −0.8 overtaking, z 40 → −5, level 0 → 1 (z < 20) → 2 (z < 12) → 3 (z < 8), level 0 after z < 0.
  2. t 6–10 s: bus at x = −1.6, z 30 → 5, level 1.
  3. t 10–14 s: car at x = 0.6, z 25 → 4, `turn_r` true, level 2.
  4. t 14–17 s: person at x = 0.3, z = 6, level 0.
  Put the script in a table of keyframes, not nested ifs.

Launch arguments (read `ProcessInfo.processInfo.arguments`):
- `--synthetic` use `SyntheticFeed` instead of `PeerFeed`.
- `--scenario N` pick scenario N.
- `--freeze T` freeze the synthetic clock at T seconds (deterministic screenshots; the pulse ring
  and interpolation must also freeze at T).
- `--mockroute` load a hard-coded 5-step route (no network, no location).

Nav:
- `MKDirections` with `transportType = .cycling`, destination from `MKLocalSearchCompleter`.
- Current step = first step whose end point is ahead of the rider's projected distance along the
  route polyline. Distance to manoeuvre = polyline distance from projection to step end.
- Mock route: 5 `MKRoute.Step`-equivalent structs (own `NavStep` type: instruction, symbol,
  distance, street), rider frozen 120 m before step 2.

## Verification loop (run every time, before and after each change)

```bash
cd /Users/jasper/4sight
xcodebuild -scheme 4sight -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build build 2>&1 | tail -20
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true        # ignore "already booted"
APP=$(find build/Build/Products/Debug-iphonesimulator -maxdepth 1 -name '4sight.app')
BUNDLE=$(defaults read "$PWD/$APP/Info" CFBundleIdentifier)
mkdir -p docs/shots
for T in 2.5 4.5 5.5; do
  xcrun simctl terminate booted "$BUNDLE" 2>/dev/null || true
  xcrun simctl install booted "$APP"
  xcrun simctl launch booted "$BUNDLE" --synthetic --freeze $T --mockroute
  sleep 2
  xcrun simctl io booted screenshot docs/shots/<pr-name>-t$T.png
done
```

Then Read each PNG (the Read tool shows images) and judge it against the brief: wedge correct,
glyph positions match the scenario at that t, colours match the level, text legible, nothing
outside the wedge. Fix before opening a PR. Keep the "before" shots for the PR body.

If `xcodebuild` fails because the Xcode project or scheme does not exist yet, stop and tell the
human. Do not create a project.

## PR rules

- Branch `front/<short-name>` off `main`. One visual step per PR. Suggested order:
  1. `front/synthetic-wedge`: SyntheticFeed + SurroundView drawing wedge, arcs, lane lines, bike glyph.
  2. `front/vehicle-glyphs`: silhouettes scaled by distance, interpolation.
  3. `front/level-colours`: level 1–3 colours, pulse, edge glow, turn_r arrow.
  4. `front/nav-hud-skeleton`: NavHUDView + StatusStripView on mock route.
  5. `front/destination-picker`: MKLocalSearchCompleter + MKDirections cycling.
  6. `front/peer-feed`: PeerFeed wired to PeerLink, link state dot.
- Commit screenshots under `docs/shots/`. PR body: what changed, embedded screenshots
  (`![t2.5](docs/shots/<pr-name>-t2.5.png)` via the raw branch URL or relative path), what to look at.
- Open with `gh pr create --base main --head front/<short-name> --title ... --body-file <file>`.
- After opening, run `gh pr view --comments` and iterate on the same branch. Push fixes with
  new screenshots. Never more than 3 open `front/*` PRs; wait for review instead.
- Never touch files outside `4sight/Front/` and `docs/shots/`. Never edit `project.pbxproj`,
  `FourSightKit/`, or `docs/CONTRACTS.md`. No secrets. No `Co-Authored-By` trailer.

## First session checklist

1. `xcode-select -p` prints a path inside `Xcode.app`. If not, stop and tell the human.
2. `gh auth status` shows you are logged in with push access to this repo.
3. `grep -rn "struct FrameMessage" FourSightKit/Sources` finds the type. Note exact field names.
4. The verification loop builds the untouched project and produces a screenshot.
5. PR 1: `SyntheticFeed` + an empty `SurroundView` that draws the wedge and the bike glyph.
   Three screenshots, open the PR, stop, wait for review.

## Reporting to the orchestrator

A master session named `bikesense-haptic-prototype` coordinates the team (find it with `ListAgents`). After opening each PR, after each round of review fixes, and on any blocker (missing project, failed build, no push access), send it a short `SendMessage`: PR number, what changed, screenshot path, what you need. Never wait for a reply; keep working.
