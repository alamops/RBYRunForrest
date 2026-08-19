-- Every tunable this mod has, and why each number is the number it is.

local M = {}

-- Running: hold B on foot and a tile takes half as long.
--
-- A divisor rather than a frame count, because the walk speed it divides is
-- not ours to know: 16 is vanilla on both generations, but a data pack may
-- say otherwise, and hardcoding 8 here would quietly *slow a modded runner
-- down*.  Two is the Gen 3+ figure -- running is bike-fast, which is what
-- keeps the bike worth getting on for its own reasons rather than for its
-- speed.
M.RUN_DIVISOR = 2

-- The bike, held to the same shape for the same reason.
--
-- The engine hands over the BIKE's step, not the walk's, so this divides a
-- number that is already half a walk: two here makes a boosted bike twice
-- the bike and four times a walk, which is the ordering the feature is for
-- -- a cyclist who holds B has to end up ahead of a runner who holds B, and
-- on both generations the bike's own step is exactly a runner's.
--
-- A divisor rather than a frame count again, and this is where that pays for
-- itself twice: Gold's Cycling Road hands DIFFERENT frames to a step down
-- the slope and a step across it (Bike.stepFrames' DOWNHILL exception, which
-- gives every direction but DOWN the walking duration back).  Dividing both
-- keeps Gold's own "across is slower than down" intact instead of flattening
-- the slope into one speed, which a fixed frame count here would do.
M.BIKE_DIVISOR = 2

-- A hop covers two cells, so it is given two steps' worth of frames.  This
-- is the multiplier both engines already apply to their own ledge hops
-- (OverworldState:checkLedgeHop's `* 2`, World:tryLedgeJump's
-- `Player.STEP_FRAMES * 2`), restated here only so the reverse hop cannot
-- drift away from the forward one when either engine tunes its arc.
M.HOP_STEP_MULTIPLIER = 2

-- The walk speed to fall back on when neither the player nor the engine can
-- be asked -- both engines' own STEP_FRAMES, and the value every ledge
-- routine in both trees already falls back to.
M.FALLBACK_STEP_FRAMES = 16

-- SFX_JUMP_OVER_LEDGE.  Gold names its cues in data.audio.sfxOrder and the
-- name is what World:playSfxNamed matches on; this index is the fallback for
-- a dataset whose order table is missing or renamed, and it is the same
-- constant src/world/gen2/World.lua carries for its own hop.
M.GEN2_LEDGE_SFX = "Sfx_JumpOverLedge"
M.GEN2_LEDGE_SFX_ID = 0x16

-- Gen 1 names its cues in data.field/audio by string; "Ledge" is the one
-- OverworldState:checkLedgeHop plays.
M.GEN1_LEDGE_SFX = "Ledge"

-- The direction a reverse hop reads a ledge row against.  A ledge that drops
-- you SOUTH is the ledge you climb by pressing NORTH, and the same inversion
-- turns Gen 1's left/right rows and Gold's HOP_LEFT / HOP_RIGHT nybbles into
-- their climbs.  Kanto and Johto both have far more left/right ledges than
-- the up-only reading would ever reach.
M.OPPOSITE = {
  up = "down", down = "up", left = "right", right = "left",
}

-- The four cell deltas, in the y-down screen frame both engines use.
-- Restated rather than required from src.world.Collision so that the two
-- detection arms below can run in a headless test with no engine tree on the
-- path; the values are asserted against Collision.DELTA in the suite.
M.DELTA = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}

-- The tileset a ledge row with no tileset of its own applies to.  Gen 1's
-- vanilla rows are all OVERWORLD and carry the key implicitly; a data pack
-- may add rows that name one.
M.DEFAULT_LEDGE_TILESET = "OVERWORLD"

return M
