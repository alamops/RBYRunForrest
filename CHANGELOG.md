# Changelog

## [1.1.0] - 2026-08-18

### Added

- **The bike has a pace of its own now.** Holding B on the bike halves the
  bike's step the way holding it on foot halves the walk, so a boosted bike is
  twice the bike and four times a walk — a cyclist who holds B ends up ahead
  of a runner who holds B, which is the ordering the row is for. Under
  `B TO RUN`, like the on-foot half.
- A divisor again, not a frame count, and it pays for itself twice here: the
  engine hands over the *bike's* step rather than the walk's, and Gold's
  Cycling Road hands over different frames for a step down the slope and a
  step across it. Dividing both keeps Gold's own "across is slower than down"
  intact instead of flattening the slope to one speed.
- Cycling Road's held-B brake is still out of reach on both generations,
  because the brake is not a step: the forced downhill roll is the branch
  taken when nothing is held and nothing is braking, and it stands down before
  any move is made. Held B there still stops the player dead; a direction held
  *with* it now costs less.

- `ALWAYS RUN`, a third row under START > OPTIONS, **default off**. Turned on,
  neither half asks for B any more: you run at the same bike-speed pace with
  nothing held, and pressing back into a ledge climbs it without a button or a
  second press — the Gen 3+ Running Shoes, once you own them.
- It defaults off on purpose. Holding B is what the mod is named after, so an
  install keeps the controls it advertised until the player says otherwise.

### Unchanged by it

- The row moves the gate rather than widening it. `B TO RUN` off is still no
  running and `B TO CLIMB` off is still no climb — it says how you ask, not
  whether it happens, and either half can be left on the button while the
  other runs buttonless.
- Surfing still passes through at its own pace, and a climb still has to pass
  the same geometry: a real ledge, a refused gap, free ground to land on.
  Holding B anyway is neither faster nor slower. The bike is boosted with
  nothing held exactly as it is with B held, which on Cycling Road means the
  slope's own downhill roll coasts at the boosted pace too.

### Tests

- The headless suite asserts the third row and its **off** default, drives the
  `movement.speed` closure at all four paces and under the row (nothing held
  runs and the bike is boosted; the water and `B TO RUN` off are unmoved), and
  drives a real Gold `World` through a buttonless climb, a wall it still
  refuses, and `B TO CLIMB` off.
- Both live drivers gained a case: on Route 4, UP alone climbs and both paces
  with nothing held match their B-held selves; on Route 29, the same climb the
  case above it drives with B held.
- The Route 4 driver measures the four paces over a 32-frame window, sized by
  the fastest of them so every run stays inside the flat stretch, and compares
  them by ordering with a one-cell tolerance — no window divides evenly into
  every pace, so an exact-equality check there measures a tile boundary rather
  than the feature.
- Its two measuring cases now stand down with a named `SKIP` when another
  loaded mod also wraps `movement.speed`. With two mods on that seam the
  measured pace is the chain's answer rather than this mod's, which is exactly
  what had case H reporting a failure against a second running-shoes mod
  installed alongside it.

## [1.0.0] - 2026-08-16

First release. Shipped at 1.0.0 rather than 0.x because the feature is
finished rather than started: both halves work on both generations, both are
verified in live runs against real map data, and the vanilla behaviour they
sit next to is unchanged. There is no half of this waiting on a later version.

### Running

- Hold **B** on foot and a tile takes half as long — bike speed, the Gen 3+
  Running Shoes figure. Wraps `movement.speed`, which both engines raise once
  per committed step, so one arm serves Gen 1 and Gold with no generation test
  anywhere in the file.
- The arithmetic is a divisor, not a frame count. The engine hands over this
  game's walk speed and the mod halves whatever it was handed, so a data pack
  that says a tile is 24 frames gets a 12-frame run instead of being quietly
  slowed to the vanilla 8.
- The bike and surfing pass through untouched. The bike is already this fast,
  and holding B there is Cycling Road's brake.

### Climbing

- Hold **B** and press back into a ledge to climb it. Every one-way hop in
  both games becomes two-way while B is held: south ledges climb with UP, west
  ledges with RIGHT, east ledges with LEFT.
- Works on the bike as well as on foot. B is the gate in both cases, which
  cannot reach Cycling Road's held-B brake — the brake is the branch the engine
  takes when no direction is held, and a climb needs one held.
- Refused while surfing, into a mountain-wall face, onto blocked or occupied
  ground, across a gap you could simply have walked, and off the edge of the
  map.
- Decided on `input.step`, before the pad's edges are promoted and before the
  overworld reads the d-pad, so the engine's own `if player.moving then return`
  stands down of its own accord. No vanilla path is patched out.
- Each generation's climb is executed by mirroring that generation's own
  forward hop — Gen 1 queues the two script steps and sets the cosmetic arc,
  Gold writes the two-cell target — so there is never a second notion of "a
  hop" for the follower, the camera and the save to disagree about.

### Options

- `B TO RUN` and `B TO CLIMB`, both under START > OPTIONS, both default on and
  independently switchable.

### Known limitation

- Yellow's Pikachu does not arc with you on a climb. The follower recognises a
  ledge by matching the forward row inside a local the mod cannot reach, so on
  a climb it walks to the cell you took off from and follows a step later. It
  self-corrects and never gets stuck.

### Tests

- `tests/rby_run_forrest_test.lua` — drives the real headless loader on both
  generations, asserts the two seams and two options rows are installed, drives
  the registered `movement.speed` closure directly, unit-tests both reverse-hop
  arms against fixture maps, and drives a **real Gold `World`** through a full
  climb plus the round trip back down.
- `tests/drivers/route4_climb_test.lua` — a live LOVE run on real ROUTE_4 tile
  data. Its three positive cases are the exact inverses of the three control
  cases in the engine's own `tests/drivers/route4_ledge_bug223_test.lua`, so
  every cell asserted is one the engine's ledge test already vouches for.
