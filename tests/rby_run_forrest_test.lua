-- rby_run_forrest suite.
--
-- Two halves.
--
-- The first drives the real headless loader on BOTH generations, which is
-- what proves the mod loads in the game: same Loader, same validate, same
-- merge.  It asserts the mod's *stated effect* -- the seams and options rows
-- it claims to install are actually installed -- and then drives the
-- registered movement.speed chain entry directly, because that closure is
-- the running shoes and nothing else reaches it.
--
-- The second unit-tests the ledge geometry through the same resolver
-- main.lua uses, so the files under test are the shipped ones and not a
-- copy.  That half is where the feature's real risk lives: a reverse-hop
-- rule that is one cell out, or that reads a ledge row in the forward
-- direction, is a mod that either does nothing or walks the player into
-- scenery, and neither shows up as an error.
--
-- Run: luajit tests/rby_run_forrest_test.lua   (from the engine checkout root)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local MOD_PATH = "mods/rby_run_forrest"
-- Out-of-tree checkouts may leave mods/rby_run_forrest pointed at another
-- tree; fall back to this suite's own mod root so the checkout under test is
-- the one that runs.
if not io.open(MOD_PATH .. "/src/Ledge.lua", "rb") then
  local src = debug.getinfo(1, "S").source
  if type(src) == "string" and src:sub(1, 1) == "@" then
    local dir = src:sub(2):match("(.+)[/\\]")
    if dir then
      local fallback = dir:gsub("[/\\]tests$", "")
      if io.open(fallback .. "/src/Ledge.lua", "rb") then MOD_PATH = fallback end
    end
  end
end

-- ------------------------------------------------------------------
-- 1. the real load, on both generations
-- ------------------------------------------------------------------

local run = T.sdk.loadMod(MOD_PATH)

eq(#run.errors, 0, "loads clean through the headless loader")
check(run.mod ~= nil, "the loader found the mod")
eq(run.mod.state, "loaded", "the mod reached the loaded state")

-- the seams it says it wraps.  Two, and only two: the speed of a committed
-- step, and the logic tick the climb is decided on.
for _, hook in ipairs({ "movement.speed", "input.step" }) do
  local chain = run.loader.hooks.chains[hook]
  check(chain ~= nil and #chain > 0, "wraps " .. hook)
end

-- the rows a player can turn off.  Both default ON -- they are the mod --
-- and the defaults are asserted here rather than trusted, because
-- mod.options:get falls back to exactly this table when nothing is stored,
-- so a typo'd default is a feature that silently never runs.
do
  local schema = run.loader.optionSchemas["rby_run_forrest"] or {}
  local byKey = {}
  for _, row in ipairs(schema) do byKey[row.key] = row end
  eq(#schema, 2, "defines exactly the two rows it documents")
  for _, key in ipairs({ "run", "jump" }) do
    check(byKey[key] ~= nil, "defines the " .. key .. " option row")
    eq(byKey[key] and byKey[key].type, "toggle", key .. " is a toggle")
    eq(byKey[key] and byKey[key].default, true, key .. " defaults on")
  end
end

-- Dual-gen headless load: the manifest claims games ["gen1","gen2"], so both
-- boots must reach loaded with an empty error list through the real loader
-- (the generation opt selects the Gen2Compat facade without a Gold ROM).
for _, gen in ipairs({ 1, 2 }) do
  local dual = T.sdk.loadMod(MOD_PATH, { generation = gen })
  eq(#dual.errors, 0, "generation=" .. gen .. " loads with no errors")
  check(dual.mod ~= nil, "generation=" .. gen .. " finds the mod")
  eq(dual.mod.state, "loaded", "generation=" .. gen .. " reaches loaded")
  dual.release()
end

-- ------- movement.speed: holding B on foot halves the step
--
-- Driven straight off the registered chain entry rather than through an
-- export, because the wrap runs entirely inside the closure the loader
-- captured -- this is the same chain Player:tryMove (Gen 1) and
-- World:movePlayer (Gold) call, with a passthrough `next` standing in for
-- the engine.  `frames` is frames-per-tile, so the arithmetic is relative to
-- whatever the engine handed in and never a hardcoded 8.

;(function()

local entry = run.loader.hooks.chains["movement.speed"][1]
local pass = function(f) return f end
local heldB = { isDown = function(_, b) return b == "b" end }
local noB = { isDown = function() return false end }

eq(entry.callback(pass, 16, { input = heldB }), 8,
   "on foot with B held, a 16-frame walk tile runs at 8")
eq(entry.callback(pass, 24, { input = heldB }), 12,
   "a data pack that says a tile is 24 frames runs at 12, not at 8")
eq(entry.callback(pass, 11, { input = heldB }), 5,
   "the halving floors rather than rounds")
check(entry.callback(pass, 1, { input = heldB }) >= 1,
      "and never drops below one frame a tile")

eq(entry.callback(pass, 16, { input = heldB, onBike = true }), 16,
   "the bike is already this fast, so holding B changes nothing about it")
eq(entry.callback(pass, 16, { input = heldB, surfing = true }), 16,
   "and surfing is left alone too")
eq(entry.callback(pass, 16, { input = noB }), 16,
   "letting go of B walks at the ordinary pace")
eq(entry.callback(pass, 16, nil), 16,
   "a ctx the engine did not build is walked, not thrown on")
eq(entry.callback(pass, "16", { input = heldB }), "16",
   "and a non-numeric speed is handed straight back rather than divided")

-- the loader's own option store, the same one mod.options:get reads -- this
-- is what a player who wants their old walk speed back flips
run.loader.modOptions["rby_run_forrest"] = { run = false }
eq(entry.callback(pass, 16, { input = heldB }), 16,
   "turning B TO RUN off walks at the ordinary pace even with B held")
run.loader.modOptions["rby_run_forrest"] = nil

end)()

-- ------------------------------------------------------------------
-- 2. the ledge geometry, through main.lua's own resolver
-- ------------------------------------------------------------------

local stubOptions = {}
local stubMod = {
  id = "rby_run_forrest",
  path = MOD_PATH,
  log = { info = function() end, warn = function() end, error = function() end },
  options = {
    define = function() end,
    get = function(_, key) return stubOptions[key] end,
  },
  hooks = { wrap = function() end },
}

-- `modOverride` lets a caller build a module graph against a mod facade of
-- its own -- the Gold section below needs a `mod.world` that answers with a
-- real World, which would be wrong to wire onto the stub the pure cases share.
local function resolver(modOverride)
  local useMod = modOverride or stubMod
  local loadstr = loadstring or load
  local cache = {}
  local function need(name)
    if cache[name] then return cache[name] end
    local handle = io.open(MOD_PATH .. "/src/" .. name .. ".lua", "rb")
    if not handle then error("missing module " .. name, 0) end
    local body = handle:read("*a")
    handle:close()
    local chunk = assert(loadstr(body, "@" .. name .. ".lua"))
    cache[name] = chunk(need, useMod)
    return cache[name]
  end
  return need
end

local need = resolver()
local Config = need("Config")
local Ledge = need("Ledge")

-- ------- Config's restated engine constants
--
-- Config.DELTA is a copy of src.world.Collision.DELTA, kept local so the
-- pure detection arms run with no engine tree on the path.  A copy is only
-- safe while it is held to the original, which is what this does: get the y
-- sign backwards and every climb in the mod goes the wrong way, silently,
-- with every other test in this file still passing because they would all
-- share the mistake.
do
  local Collision = require("src.world.Collision")
  for dir, d in pairs(Collision.DELTA) do
    local mine = Config.DELTA[dir]
    check(mine ~= nil, "Config.DELTA covers " .. dir)
    eq(mine[1], d[1], "Config.DELTA." .. dir .. " x matches the engine")
    eq(mine[2], d[2], "Config.DELTA." .. dir .. " y matches the engine")
  end
end

-- OPPOSITE is what turns a ledge row into its climb; if it is not a true
-- involution over all four directions, some ledges become one-way again for
-- no stated reason.
for dir in pairs(Config.DELTA) do
  local back = Config.OPPOSITE[dir]
  check(back ~= nil, "OPPOSITE covers " .. dir)
  eq(Config.OPPOSITE[back], dir, "OPPOSITE is its own inverse at " .. dir)
end

-- ------- Gen 1: a ledge row read backwards
--
-- The fixture below is the real geometry of a vanilla down-ledge, laid out
-- as a 3-cell column:
--
--     (5,3)  tile 44   walkable   <- the top: where a jumper takes off,
--                                    and where a climber lands
--     (5,4)  tile 55   REFUSED    <- the cliff face itself
--     (5,5)  tile  1   walkable   <- the bottom: where a jumper lands,
--                                    and where a climber takes off
--
-- so pressing UP from (5,5) must answer (5,3), and nothing else must.

;(function()

local ROWS = {
  { facing = "down",  input = "down",  standingTile = 44, ledgeTile = 55 },
  { facing = "left",  input = "left",  standingTile = 44, ledgeTile = 39 },
  { facing = "right", input = "right", standingTile = 44, ledgeTile = 13 },
  -- a row a data pack added for a different tileset, which must never match
  -- an OVERWORLD map
  { facing = "down", input = "down", standingTile = 44, ledgeTile = 99,
    tileset = "CAVERN" },
}

-- tiles the fixture map refuses; everything else is walkable ground
local BLOCKED = { [55] = true, [39] = true, [13] = true, [99] = true, [77] = true }

local function mapWith(tiles)
  return {
    def = { tileset = "OVERWORLD" },
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x <= 9 and y <= 9
    end,
    cellTile = function(_, x, y) return tiles[y * 10 + x] or 1 end,
    isWalkableCell = function(self, x, y)
      return not BLOCKED[self:cellTile(x, y)]
    end,
  }
end

local function landing(tiles, cx, cy, dir, entities)
  return Ledge.gen1Landing(mapWith(tiles), ROWS, "OVERWORLD", cx, cy, dir,
                           entities, nil)
end

-- the column above: 44 on top, the ledge face between, open ground below
local column = { [35] = 44, [45] = 55 }

do
  local lx, ly = landing(column, 5, 5, "up")
  eq(lx, 5, "climbing a down-ledge lands two cells up (x)")
  eq(ly, 3, "climbing a down-ledge lands two cells up (y)")
end

-- The forward direction is still the ENGINE's business.  Pressing down from
-- the top of the same ledge is the vanilla hop, and this mod must not answer
-- for it -- the tile one ahead is the ledge face, but the row facing "down"
-- is not the reverse of "down", so nothing matches.
check(landing(column, 5, 3, "down") == nil,
      "the vanilla forward hop is left entirely to the engine")

-- A left-ledge is climbed by pressing RIGHT, and a right-ledge by pressing
-- LEFT.  Kanto and Johto have far more of these than of the pure verticals,
-- so getting the horizontal inversion wrong would quietly halve the feature.
do
  -- (3,7) open, (4,7) tile 39 (a left-ledge face), (5,7) tile 44
  local rowTiles = { [74] = 39, [75] = 44 }
  local lx, ly = landing(rowTiles, 3, 7, "right")
  eq(lx, 5, "climbing a left-ledge lands two cells right (x)")
  eq(ly, 7, "climbing a left-ledge lands two cells right (y)")
end
do
  -- (5,7) open, (4,7) tile 13 (a right-ledge face), (3,7) tile 44
  local rowTiles = { [74] = 13, [73] = 44 }
  local lx = landing(rowTiles, 5, 7, "left")
  eq(lx, 3, "climbing a right-ledge lands two cells left")
end

-- The gap has to be refused.  If the cell between were walkable the player
-- could simply walk there, and a two-cell jump across open ground is a
-- teleport, not a climb -- this is the whole one-way-ness test.
check(landing({ [35] = 44, [45] = 1 }, 5, 5, "up") == nil,
      "an open cell ahead is walked into, never jumped over")

-- The landing has to be real ground.  A ledge with a wall above it is a
-- cliff, and the engine's forward hop refuses the mirror of this too.
check(landing({ [35] = 77, [45] = 55 }, 5, 5, "up") == nil,
      "a blocked landing refuses the climb")

-- ...and it has to be free.  An NPC standing on the far side is exactly the
-- case that would otherwise put two sprites in one cell.
check(landing(column, 5, 5, "up", { { cellX = 5, cellY = 3 } }) == nil,
      "an NPC standing on the landing refuses the climb")
check(landing(column, 5, 5, "up",
              { { cellX = 9, cellY = 9, targetX = 5, targetY = 3 } }) == nil,
      "and so does one already stepping into it")
check(landing(column, 5, 5, "up",
              { { cellX = 5, cellY = 3, passable = true } }) ~= nil,
      "but Yellow's companion Pikachu is walked through, not blocked by")

-- A row that names another tileset is not this map's row.
check(landing({ [35] = 44, [45] = 99 }, 5, 5, "up") == nil,
      "a ledge row for another tileset never matches this map")

-- Off the map is off the map.  The forward hop is allowed to land on a
-- connected map; a climb is not, because the seam crossing is the forward
-- hop's own machinery and there is no vanilla shortcut being restored here.
check(landing({ [5] = 44, [15] = 55 }, 5, 1, "up") == nil,
      "a climb that would land off the map edge is refused")

-- No rows at all (a dataset with the table stripped) is a quiet no-op, not a
-- crash inside a hook.
check(Ledge.gen1Landing(mapWith(column), nil, "OVERWORLD", 5, 5, "up") == nil,
      "a dataset with no ledge rows disables the climb quietly")

end)()

-- ------- Gen 2: the HI_NYBBLE_LEDGES nybble, read two cells ahead
--
-- Gold marks the tile a jumper STANDS on, not the face between, so a
-- climber's target is the marked tile itself:
--
--     (5,3)  COLL_HOP_DOWN, land    <- the ledge tile; a climber lands HERE
--     (5,4)  wall                   <- the gap that makes it one-way
--     (5,5)  land                   <- where the climber takes off
--
-- Landing ON the ledge tile is the point: the next press hops straight back
-- down, which is the two-way seam this feature is for.

;(function()

local HOP_DOWN, HOP_LEFT, WALL, LAND = 0xa3, 0xa1, 0x01, 0x00

-- src.world.gen2.Permissions.ledgeFacings, stubbed to the two nybbles this
-- fixture uses.  The live function is passed in by Ledge.tick; here the stub
-- keeps the case readable and independent of Gold's table ordering, which
-- differs between Gold and Crystal.
local function ledgeFacings(coll)
  if coll == HOP_DOWN then return { down = true } end
  if coll == HOP_LEFT then return { left = true } end
  return nil
end

local function mapWith(cells)
  return {
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x <= 9 and y <= 9
    end,
    cellCollision = function(_, x, y) return cells[y * 10 + x] or LAND end,
    isWalkable = function(self, x, y) return self:cellCollision(x, y) ~= WALL end,
  }
end

local function landing(cells, cx, cy, dir, entities)
  return Ledge.gen2Landing(mapWith(cells), ledgeFacings, cx, cy, dir,
                           entities, nil)
end

local column = { [35] = HOP_DOWN, [45] = WALL }

do
  local lx, ly = landing(column, 5, 5, "up")
  eq(lx, 5, "climbing a HOP_DOWN ledge lands on the ledge tile itself (x)")
  eq(ly, 3, "climbing a HOP_DOWN ledge lands on the ledge tile itself (y)")
end

-- Gold's own forward jump starts ON the ledge tile, so standing there and
-- pressing down is the engine's business, not ours.
check(landing(column, 5, 3, "down") == nil,
      "standing on the ledge tile leaves the forward jump to Gold")

-- HOP_LEFT is jumped westward off (3,7) onto (1,7), so it is CLIMBED by
-- standing at (1,7) and pressing RIGHT -- from the far side, back the way
-- the jumper came.  Approaching the same tile from the east and pressing
-- left is a different ledge's climb, and must not match this one.
do
  local cells = { [73] = HOP_LEFT, [72] = WALL }
  local lx, ly = landing(cells, 1, 7, "right")
  eq(lx, 3, "climbing a HOP_LEFT ledge lands two cells right (x)")
  eq(ly, 7, "climbing a HOP_LEFT ledge lands two cells right (y)")
  check(landing({ [73] = HOP_LEFT, [74] = WALL }, 5, 7, "left") == nil,
        "and approaching that same ledge from the other side does not climb it")
end

-- A ledge whose facings do not include the reverse of the press is a ledge
-- pointing some other way; walking round it is the answer, not jumping it.
check(landing({ [35] = HOP_LEFT, [45] = WALL }, 5, 5, "up") == nil,
      "a ledge facing another way is not climbed by this press")

-- The same two structural refusals as Gen 1, against Gold's own permission
-- reads rather than tile ids.
check(landing({ [35] = HOP_DOWN, [45] = LAND }, 5, 5, "up") == nil,
      "an open gap is walked into, never jumped over")
check(landing({ [35] = LAND, [45] = WALL }, 5, 5, "up") == nil,
      "a plain wall with land behind it is not a ledge")
check(landing(column, 5, 5, "up", { { cellX = 5, cellY = 3 } }) == nil,
      "an NPC on the ledge tile refuses the climb")
check(landing(column, 5, 1, "up") == nil,
      "a climb that would land off the map edge is refused")
check(Ledge.gen2Landing(mapWith(column), nil, 5, 5, "up") == nil,
      "no permissions module means no climb, quietly")

end)()

-- ------------------------------------------------------------------
-- 3. Gold, against a real World
-- ------------------------------------------------------------------
--
-- The fixture cases above prove the reverse-hop RULE.  This proves the
-- feature on Gold: a real src/world/gen2/World, a real Player, the real
-- Permissions table, and the shipped Ledge.tick driving them -- so the
-- collision nybbles, the two-cell target write and Gold's own
-- `if p.moving then return end` are all the engine's rather than a stub's.
--
-- Gen 1's half is proven the same way one level up, in a live LOVE run
-- against real ROUTE_4 tile data
-- (tests/drivers/route4_climb_test.lua).  Gold needs no ROM to reach the
-- same standard, because its overworld can be built headlessly.

;(function()

local World = require("src.world.gen2.World")
local Gen2Player = require("src.world.gen2.Player")
local Permissions = require("src.world.gen2.Permissions")

local COLL_FLOOR, COLL_WALL, COLL_HOP_DOWN = 0x00, 0x07, 0xa3
local MAP_W, MAP_H = 20, 20

local function fakeMap(cells)
  local map
  map = {
    id = "TEST_MAP", width = MAP_W, height = MAP_H, blocks = {},
    def = { bgEvents = {}, objects = {}, blocks = {},
            width = MAP_W, height = MAP_H, tileset = "TILESET_JOHTO",
            environment = "ROUTE", palette = "PALETTE_AUTO" },
    cellCollision = function(_, x, y) return cells[y * 100 + x] or COLL_FLOOR end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < MAP_W * 2 and y < MAP_H * 2
    end,
    isWalkable = function(_, x, y)
      if not map:inBounds(x, y) then return false end
      return Permissions.isWalkable(map:cellCollision(x, y))
    end,
    warpAt = function() return nil end,
  }
  return map
end

-- The climbable column, in Gold's terms:
--
--     (4,5)  COLL_HOP_DOWN   the ledge tile -- a climber's landing
--     (4,6)  COLL_WALL       the gap that makes it one-way
--     (4,7)  floor           where the climber stands
--
-- which is exactly the fixture tests/gen2_world_test.lua uses to prove the
-- FORWARD jump off (4,5) lands on (4,7).  Starting where that one lands and
-- asserting we end where it started is what makes this a true inverse.
local CELLS = { [5 * 100 + 4] = COLL_HOP_DOWN, [6 * 100 + 4] = COLL_WALL }

local heldButtons = {}
local fakeInput = {
  isDown = function(_, b) return heldButtons[b] == true end,
  wasPressed = function() return false end,
}

local function buildWorld(cells)
  local game = {
    data = { audio = {}, items = {} },
    save = { player = { name = "GOLD" }, party = {}, inventory = {} },
    input = fakeInput,
    stack = { top = function() return nil end },
  }
  local world = World.new(game)
  game.world = world
  world.map = fakeMap(cells)
  world.maps = { TEST_MAP = world.map.def }
  world.vm = { running = function() return false end, update = function() end }
  world.pollTimeOfDay = function() end
  -- nothing here is about audio, and playSfx reaches for a runtime
  world.playSfx = function() end
  return world, game
end

-- one Ledge.tick, then let Gold's own step loop carry the move it started
local function climb(world, game, Ledge, dir, frames)
  world.player.turnArmed = false
  world.entities = { world.player }
  heldButtons = { b = true, [dir] = true }
  Ledge.tick(game)
  local jumped = world.player.jumping == true
  for _ = 1, (frames or 60) do
    if not world.player.moving then break end
    world:step()
  end
  heldButtons = {}
  return world.player.cellX, world.player.cellY, jumped
end

-- A mod facade whose mod.world answers with whichever World the case built,
-- which is the one thing Ledge.tick reaches the live game through.
local current = nil
local goldMod = {
  id = "rby_run_forrest", path = MOD_PATH,
  log = { info = function() end, warn = function() end, error = function() end },
  options = { define = function() end, get = function(_, k)
    if k == "jump" then return true end
    return nil
  end },
  hooks = { wrap = function() end },
  world = { overworld = function() return current end },
}
local Ledge2 = resolver(goldMod)("Ledge")

do
  local world, game = buildWorld(CELLS)
  world.player = Gen2Player.new(4, 7, "up")
  current = world
  local x, y, jumped = climb(world, game, Ledge2, "up")
  check(jumped, "Gold: B+UP starts a jump off the real World")
  eq(x, 4, "Gold: the climb lands on the ledge tile (x)")
  eq(y, 5, "Gold: the climb lands on the ledge tile (y)")
end

-- Landing ON the ledge tile is the point, not a near miss: from there Gold's
-- own .TryJump takes the player straight back down, which is the two-way
-- seam the whole feature is for.  Proven by driving the ENGINE's jump from
-- where our climb finished.
do
  local world, game = buildWorld(CELLS)
  world.player = Gen2Player.new(4, 7, "up")
  current = world
  climb(world, game, Ledge2, "up")
  world.heldDir = "down"
  world.player.turnArmed = false
  for _ = 1, 2 do world:step() end
  world.heldDir = nil
  for _ = 1, 60 do
    if not world.player.moving and not world.turningDirection then break end
    world:step()
  end
  eq(world.player.cellY, 7, "Gold: and Gold's own hop takes it straight back down")
end

-- Without B, Gold is Gold.
do
  local world, game = buildWorld(CELLS)
  world.player = Gen2Player.new(4, 7, "up")
  current = world
  world.player.turnArmed = false
  world.entities = { world.player }
  heldButtons = { up = true }
  Ledge2.tick(game)
  heldButtons = {}
  check(world.player.jumping ~= true, "Gold: UP without B starts no jump")
  eq(world.player.cellY, 7, "Gold: and the player has not moved")
end

-- An NPC on the landing refuses the climb, against the real World's entity
-- list rather than a fixture array.
do
  local world, game = buildWorld(CELLS)
  world.player = Gen2Player.new(4, 7, "up")
  current = world
  world.player.turnArmed = false
  world.entities = { world.player, Gen2Player.new(4, 5, "down") }
  heldButtons = { b = true, up = true }
  Ledge2.tick(game)
  heldButtons = {}
  eq(world.player.cellY, 7, "Gold: an NPC on the ledge tile refuses the climb")
end

-- A plain wall is not a ledge, however much it looks like the gap in one.
do
  local world, game = buildWorld({ [6 * 100 + 4] = COLL_WALL })
  world.player = Gen2Player.new(4, 7, "up")
  current = world
  local _, y = climb(world, game, Ledge2, "up")
  eq(y, 7, "Gold: a wall with open ground behind it is not climbed")
end

current = nil

end)()

T.finish("rby_run_forrest")
