-- Running shoes: hold B and a tile takes half as long -- on foot and on the
-- bike, each halving its own pace -- or, with ALWAYS RUN on, just move and it
-- already does.
--
-- One hook, `movement.speed`, which both engines raise once per COMMITTED
-- step and never per frame (src/world/Player.lua's tryMove under Gen 1,
-- World:movePlayer under Gold).  Both floor the result to at least 1 and both
-- hand over the same ctx keys, so there is one arm here and no generation
-- test anywhere in this file.

local need, mod = ...
local Config = need("Config")

local M = {}

-- One-shot latch for the failure warn below.  A step's speed is asked for
-- several times a second, and everything that can make runSpeed throw -- an
-- options table that no longer answers, a ctx of an unexpected shape -- is a
-- standing condition rather than a blip, so an unlatched warn would say the
-- same sentence a few times a second for as long as the game is open.  Once
-- is the whole message; the fallback keeps working either way.
local warned = false

-- What a step should cost in frames.
--
-- Declared out here rather than inside the wrap so the hot path can pcall it
-- by name and allocate nothing per step.  The arithmetic is deliberately
-- relative: the engine hands us this game's walk speed, and dividing it is
-- the only way that stays true on a data pack that says a tile is not 16
-- frames.  `frames` is frames-per-tile, so lower is faster.
--
-- On foot and on the bike alike, each divided by its own figure: the engine
-- hands over whichever pace this step was going to cost, so one line of
-- arithmetic serves both and a boosted bike lands ahead of a runner without
-- either number being written down here.
--
-- Surfing is the one exclusion left -- a sprint across water is not a thing
-- either generation has -- and it holds under ALWAYS RUN too.
--
-- Holding B on the bike cannot reach Cycling Road's brake, on either
-- generation, because the brake is not a step: OverworldController's forced
-- downhill roll is the branch taken when nothing is held AND nothing is
-- braking, and it stands down before any move is made.  Held B there still
-- stops the player dead; what is new is that a direction held WITH it now
-- costs less.  (With ALWAYS RUN on the roll itself is boosted, because the
-- roll is a step like any other and the row says every step is fast.)
--
-- This is the SPEED only.  The ledge climb in Ledge.lua reads held B for
-- itself and deliberately does not consult this.
local function runSpeed(frames, ctx)
  if mod.options:get("run") == false then return frames end
  if type(frames) ~= "number" then return frames end
  if not ctx or ctx.surfing then return frames end
  -- ALWAYS RUN moves the gate rather than widening it: every refusal above
  -- still stands (the row can still be turned off, the water is still left
  -- alone), and the only thing it drops is the button.  `== true` rather
  -- than `~= false` because this is the one row that defaults OFF, and
  -- options:get answers nil until something is stored.
  if mod.options:get("always") ~= true then
    local input = ctx.input
    if not (input and input.isDown and input:isDown("b")) then return frames end
  end
  local divisor = ctx.onBike and Config.BIKE_DIVISOR or Config.RUN_DIVISOR
  return math.max(1, math.floor(frames / divisor))
end

function M.install()
  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    local ok, speed = pcall(runSpeed, frames, ctx)
    if not ok then
      -- pcall has put the error where the speed would have been.  Whatever
      -- went wrong, the step still has to happen at *some* speed, and the
      -- honest one is the speed we were handed.
      if not warned then
        warned = true
        mod.log:warn("could not work out a running speed (%s); walking this "
          .. "step -- turn B TO RUN off under START > OPTIONS if it repeats",
          tostring(speed))
      end
      return next(frames, ctx)
    end
    return next(speed, ctx)
  end)
end

-- exposed for the suite: the pure arithmetic, with no hook around it
M.speedFor = runSpeed

return M
