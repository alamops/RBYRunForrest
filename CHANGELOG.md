# Changelog

## [0.1.0] - 2026-08-16

First release.

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
