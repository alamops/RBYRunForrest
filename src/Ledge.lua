-- Climbing a ledge instead of only falling off it.
--
-- Both generations ship the same one-way shortcut and neither ships the way
-- back.  Gen 1 matches a (standing tile, ledge tile, direction) row out of
-- data.field.ledges and script-moves the player two cells; Gold reads a
-- HI_NYBBLE_LEDGES nybble off the tile the player is STANDING on and jumps
-- two cells itself.  Different data, different execution -- but the same
-- geometry, and that is what makes one reverse rule serve both:
--
--     a hop starts on cell A, passes over cell B, lands on cell C
--     ==> the climb starts on C, passes over B, lands on A
--
-- so a climb is always "two cells forward, over a cell you may not walk
-- into", and the only thing that differs per generation is where the ledge's
-- own marking lives.  Under Gen 1 the marking is on B, the tile between:
-- ledge tiles ARE the cliff face, and the row names the tile you jump from
-- and the tile you jump over.  Under Gold the marking is on A, the far side:
-- the ledge tile is walkable land you stand on to jump off, and the cell
-- between is the wall that makes it one-way.  So the Gen 1 arm reads the
-- cell one ahead and the Gold arm reads the cell two ahead, and both then
-- ask the same two questions -- is the gap refused, is the landing free.
--
-- Detection is pure and takes its map as a duck-typed argument, so the suite
-- drives both arms with a table and no engine tree on the path.  Only
-- M.begin below touches the live world.

local need, mod = ...
local Config = need("Config")

local M = {}

local DELTA = Config.DELTA
local OPPOSITE = Config.OPPOSITE

-- src.world.Collision's own rule, restated rather than required so
-- detection stays headless: an entity blocks the cell it stands on AND the
-- cell it is stepping into, `ignore` is the mover itself, and a `passable`
-- entity never blocks (Yellow's companion Pikachu, which the player walks
-- straight through).
local function occupied(entities, cx, cy, ignore)
  for _, e in ipairs(entities or {}) do
    if e ~= ignore and not e.passable then
      if (e.cellX == cx and e.cellY == cy)
         or (e.targetX == cx and e.targetY == cy) then
        return true
      end
    end
  end
  return false
end

-- The two cells a climb in `dir` needs: the gap it passes over and the
-- landing it ends on.  nil when either falls off the map -- unlike the
-- forward hop, which pokered lets run onto a connected map, a climb that
-- leaves the map is refused outright.  Landing a player on a connection
-- seam is the forward hop's business and it already owns the whole
-- crossConnection dance; there is no vanilla shortcut being restored by
-- doing it here, only a new way to end up somewhere unloaded.
local function cellsFor(map, cx, cy, dir)
  local d = DELTA[dir]
  if not d then return nil end
  local gx, gy = cx + d[1], cy + d[2]
  local lx, ly = cx + d[1] * 2, cy + d[2] * 2
  if not (map:inBounds(gx, gy) and map:inBounds(lx, ly)) then return nil end
  return gx, gy, lx, ly
end

-- ------- Gen 1: data.field.ledges, matched in reverse
--
-- A row says "standing on standingTile, facing `facing`, with ledgeTile in
-- front -> hop two cells".  Read backwards, the cell ONE ahead of a climber
-- carries that row's ledgeTile and the row's facing is the opposite of the
-- climber's.
--
-- standingTile is deliberately NOT required of the landing.  It constrains
-- the cell a jumper takes off from, and the tile above a cliff is scenery
-- the ledge rows never speak for -- Route 4's plaza and the Route 1 hedges
-- put several different walkables above the same ledgeTile.  Requiring it
-- would refuse most of the climbs the feature exists for, and it buys
-- nothing the walkable test below does not already buy.
function M.gen1Landing(map, rows, tileset, cx, cy, dir, entities, mover)
  if type(rows) ~= "table" then return nil end
  local gx, gy, lx, ly = cellsFor(map, cx, cy, dir)
  if not gx then return nil end

  -- The gap must be refused.  This is the whole one-way-ness test, and it is
  -- what keeps the climb from becoming a two-cell teleport across open
  -- ground: if the player could simply walk there, they should walk there.
  -- It also settles the ordering question with the engine's own input pass,
  -- which runs after ours -- a cell we refuse to jump into is a cell the
  -- vanilla step was never going to take either.
  if map:isWalkableCell(gx, gy) then return nil end
  if not map:isWalkableCell(lx, ly) then return nil end
  if occupied(entities, lx, ly, mover) then return nil end

  local front = map:cellTile(gx, gy)
  local back = OPPOSITE[dir]
  for _, ledge in ipairs(rows) do
    if (ledge.tileset or Config.DEFAULT_LEDGE_TILESET) == tileset
       and ledge.facing == back and ledge.input == back
       and ledge.ledgeTile == front then
      return lx, ly
    end
  end
  return nil
end

-- ------- Gen 2: the HI_NYBBLE_LEDGES nybble, read two cells ahead
--
-- Gold marks the tile a jumper stands ON, so a climber's target IS that
-- tile: land on it and the next press hops back down, which is exactly the
-- two-way seam this feature is for.  `ledgeFacings` is passed in rather than
-- required so this stays testable; it is
-- src.world.gen2.Permissions.ledgeFacings, whose answer is a set of the
-- directions that tile can be jumped in.
function M.gen2Landing(map, ledgeFacings, cx, cy, dir, entities, mover)
  if type(ledgeFacings) ~= "function" then return nil end
  local gx, gy, lx, ly = cellsFor(map, cx, cy, dir)
  if not gx then return nil end

  if map:isWalkable(gx, gy) then return nil end
  if not map:isWalkable(lx, ly) then return nil end
  if occupied(entities, lx, ly, mover) then return nil end

  local ok, facings = pcall(ledgeFacings, map:cellCollision(lx, ly))
  if not (ok and type(facings) == "table") then return nil end
  if not facings[OPPOSITE[dir]] then return nil end
  return lx, ly
end

-- ------- the live arms

-- Which generation's overworld this is, asked of the object rather than of
-- the dataset.  mod.world:overworld() hands back the Gen 1 OverworldState
-- singleton or the Gold World instance, and each one carries its own ledge
-- routine under its own name -- so the object that has to be driven is the
-- object that says how.  A version sniff would answer the same thing one
-- indirection further from the code that cares.
local function generationOf(world)
  if type(world.tryLedgeJump) == "function" then return 2 end
  if type(world.checkLedgeHop) == "function" then return 1 end
  return nil
end

local requireWarned = {}

-- engine_internals reaches, each behind its own latch: a module that is not
-- there is a standing condition, and this is asked once per candidate climb.
local function engine(path)
  local ok, module = pcall(require, path)
  if ok and type(module) == "table" then return module end
  if not requireWarned[path] then
    requireWarned[path] = true
    mod.log:warn("could not load %s (%s); ledge climbing is off for this "
      .. "game -- running is unaffected", path, tostring(module))
  end
  return nil
end

-- Gen 1 free-roam.  Everything below is a state the overworld's own update
-- refuses to run handleInput under (OverworldController's `scripted` set),
-- plus the stack test that keeps a menu or a battle drawn over the world
-- from steering the player underneath it.
local function gen1Ready(game, world)
  local stack = game and game.stack
  if not (stack and stack.top and stack:top() == world) then return false end
  if world.transitioning or world.engaging or world.emote or world.teleportOut
     or world.flyAnim or world.flyArrive or world.healAnim or world.pikaHop then
    return false
  end
  local runner = world.runner
  if runner and runner.isRunning and runner:isRunning() then return false end
  return #(world.scriptMoves or {}) == 0
end

-- Gold free-roam.  World:acceptsMenuInput is the engine's own transcription
-- of the three gates PlayerEvents checks before it will act on the pad --
-- script running, mid-step, and the ice latch -- so a climb is offered
-- exactly when a step would have been.  Gold's world is not a stack state,
-- so anything on the stack at all is drawn over it.
local function gen2Ready(game, world)
  local stack = game and game.stack
  if stack and stack.top and stack:top() ~= nil then return false end
  if type(world.acceptsMenuInput) ~= "function" then return false end
  local ok, accepts = pcall(world.acceptsMenuInput, world)
  return ok and accepts == true
end

-- Start the climb.  Each arm mirrors its own engine's forward hop rather
-- than inventing a movement: Gen 1 queues the two script steps and sets the
-- cosmetic arc, Gold writes the two-cell target directly.  Doing it any
-- other way would put a second notion of "a hop" in the tree, and the one
-- that is already there is the one the follower, the camera and the save
-- all understand.
local function gen1Begin(game, world, dir)
  local p = world.player
  local Sound = engine("src.core.Sound")
  if Sound and Sound.play then
    pcall(Sound.play, game and game.data, Config.GEN1_LEDGE_SFX)
  end
  local step = p.stepFramesCur or p.stepFrames or Config.FALLBACK_STEP_FRAMES
  local hop = step * Config.HOP_STEP_MULTIPLIER
  p.hopFrames, p.hopTotal = hop, hop
  world:scriptMove(p, dir, 2)
end

local function gen2Begin(world, dir, lx, ly)
  local p = world.player
  local Player = engine("src.world.gen2.Player")
  p.facing = dir
  p.targetX, p.targetY = lx, ly
  p.moving = true
  p.jumping = true
  -- JumpStep clears IN_GRASS and rings neither UpdateTallGrassFlags nor
  -- ShakeGrass: a jump does not brush the grass it passes over, which is
  -- also why a climb cannot start an encounter mid-air.
  p.inGrass, p.grassShake = false, nil
  p.progress = 0
  p.stepFrames = ((Player and Player.STEP_FRAMES) or Config.FALLBACK_STEP_FRAMES)
    * Config.HOP_STEP_MULTIPLIER
  if type(world.playSfxNamed) == "function" then
    pcall(world.playSfxNamed, world, Config.GEN2_LEDGE_SFX,
          Config.GEN2_LEDGE_SFX_ID)
  end
end

-- One logic tick's worth of "should the player be climbing right now".
--
-- Raised from input.step, which both generations fire BEFORE the pad's
-- edges are promoted and before the overworld's own input pass -- so a climb
-- started here has the player already moving by the time the engine looks at
-- the d-pad, and the engine's `if p.moving then return end` stands down of
-- its own accord.  Nothing is suppressed and no vanilla path is patched out;
-- the frame simply already has a move in it.
--
-- isDown reads the previous tick's pad, one frame stale, which is exactly
-- right for the two held buttons this asks about and is the same staleness
-- the engine's own held-direction reads carry.
function M.tick(game)
  if mod.options:get("jump") == false then return end
  local api = mod.world
  if not api then return end
  local ok, world = pcall(api.overworld, api)
  if not (ok and type(world) == "table") then return end

  local p, map = world.player, world.map
  if not (p and map) then return end
  -- Surfing has no ledges to climb in either game, and a hop off the water
  -- would land the player on foot in the sea.
  if p.moving or p.inputLocked or p.surfing then return end

  local dir = p.facing
  if not DELTA[dir] then return end
  local input = game and game.input
  if not (input and input.isDown) then return end
  -- B is the whole gate, on foot and on the bike alike.  On the bike this
  -- cannot reach Cycling Road's brake: the brake is the no-direction-held
  -- branch, and this needs a direction held.
  if not (input:isDown("b") and input:isDown(dir)) then return end

  local gen = generationOf(world)
  if gen == 1 then
    if not gen1Ready(game, world) then return end
    local rows = game and game.data and game.data.field
      and game.data.field.ledges
    local tileset = map.def and map.def.tileset
    local lx = M.gen1Landing(map, rows, tileset, p.cellX, p.cellY, dir,
                             world.entities, p)
    if not lx then return end
    gen1Begin(game, world, dir)
  elseif gen == 2 then
    if not gen2Ready(game, world) then return end
    local Permissions = engine("src.world.gen2.Permissions")
    if not Permissions then return end
    local lx, ly = M.gen2Landing(map, Permissions.ledgeFacings, p.cellX,
                                 p.cellY, dir, world.entities, p)
    if not lx then return end
    gen2Begin(world, dir, lx, ly)
  end
end

local tickWarned = false

function M.install()
  mod.hooks:wrap("input.step", function(next, game, dt)
    local ok, err = pcall(M.tick, game)
    if not ok and not tickWarned then
      tickWarned = true
      mod.log:warn("ledge climbing failed (%s) and is left to the vanilla "
        .. "one-way rule -- turn B TO CLIMB off under START > OPTIONS if it "
        .. "repeats", tostring(err))
    end
    return next(game, dt)
  end)
end

return M
