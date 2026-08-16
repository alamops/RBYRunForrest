-- Driver: climbing Johto's ledges, in a real Gold run (Gen 2).
--
-- The Gold half of the headless suite already drives a real
-- src/world/gen2/World through a climb and the round trip back down.  What it
-- cannot do is prove the rule against Gold's OWN map data: its collision
-- fixture is hand-written, so a reverse rule that is right about the nybble
-- and wrong about which cell carries it would pass there and fail on Route 32.
--
-- So this driver does not hardcode a single coordinate.  It SCANS the live
-- map for cells the mod would accept -- walkable, a refused gap one ahead, a
-- HI_NYBBLE_LEDGES tile two ahead facing back the way we came -- and then
-- climbs the ones it found.  A map with no candidates is reported and skipped
-- rather than silently passing, and the run fails if no map on the list
-- yielded a single climb.
--
-- Screenshots are taken standing below, mid-air, and standing on top, so the
-- Gold result can be eyeballed the same way the Gen 1 one is.
--
-- Run:
--   POKEPORT_GAME=gold \
--   POKEPORT_DRIVER=mods/rby_run_forrest/tests/drivers/gold_climb_test.lua \
--   POKEPORT_IDENTITY=runforrest-gold POKEPORT_TOUCH=0 \
--   POKEPORT_SHOTDIR=<dir> love .
local U = require("tests.drivers.util")

-- Johto's open routes, which is where its ledges are.  Several, because a
-- re-import or a map rename must not turn this driver into a no-op: the run
-- needs only one of them to carry a climbable cell, and reports what each
-- one had.
local MAPS = {
  "ROUTE_29", "ROUTE_30", "ROUTE_31", "ROUTE_32", "ROUTE_33",
  "ROUTE_34", "ROUTE_35", "ROUTE_36", "ROUTE_37", "ROUTE_38",
  "ROUTE_39", "ROUTE_42", "ROUTE_43", "ROUTE_45", "ROUTE_46",
}

local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

return function(game)
  local Permissions = require("src.world.gen2.Permissions")
  local shotDir = os.getenv("POKEPORT_SHOTDIR") or "."
  local shotN = 0
  local function shot(name)
    shotN = shotN + 1
    U.shot(game, ("%s/%02d_%s.png"):format(shotDir, shotN, name))
  end

  local fails, checks = 0, 0
  local function expect(cond, ...)
    checks = checks + 1
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  local loader = game.mods
  local function setOption(key, value)
    if not loader then return false end
    local store = loader.modOptions["rby_run_forrest"]
    if not store then
      store = {}
      loader.modOptions["rby_run_forrest"] = store
    end
    store[key] = value
    return true
  end

  -- Every cell on the current map from which a climb would be accepted, read
  -- off the live map through the live Permissions table.  This is the mod's
  -- own rule restated for the survey: standing cell walkable, the gap one
  -- ahead refused, and the cell two ahead a ledge whose facings include the
  -- way we came from.
  local function candidates()
    local map = world.map
    local out = {}
    local w = (map.def and map.def.width or map.width or 0) * 2
    local h = (map.def and map.def.height or map.height or 0) * 2
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        for dir, d in pairs(DELTA) do
          local gx, gy = x + d[1], y + d[2]
          local lx, ly = x + d[1] * 2, y + d[2] * 2
          if map:inBounds(gx, gy) and map:inBounds(lx, ly)
             and map:isWalkable(x, y)
             and not map:isWalkable(gx, gy)
             and map:isWalkable(lx, ly) then
            local facings = Permissions.ledgeFacings(map:cellCollision(lx, ly))
            if facings and facings[OPPOSITE[dir]] then
              out[#out + 1] = { x = x, y = y, dir = dir, lx = lx, ly = ly }
            end
          end
        end
      end
    end
    return out
  end

  -- Hold `dir` (with B unless told otherwise) and report where the jump put
  -- the player.  p.jumping is Gold's own STEP_LEDGE flag, so it is the honest
  -- witness that a two-cell jump happened rather than a walk.
  local function hold(dir, frames, withB, onAir)
    local p = world.player
    local jumped, wasJumping, landX, landY, fired = false, false, nil, nil, false
    for _ = 1, frames do
      if not fired then
        game.input.pressQueue[#game.input.pressQueue + 1] = dir
        game.input.state[dir] = true
        if withB then game.input.state.b = true end
      end
      coroutine.yield()
      local jumping = p.jumping == true
      if jumping then
        jumped = true
        if not fired and onAir then
          fired = true
          game.input.state[dir] = false
          game.input.state.b = false
          onAir()
        end
      end
      if wasJumping and not jumping and not landX then
        landX, landY = p.cellX, p.cellY
      end
      wasJumping = jumping
    end
    game.input.state[dir] = false
    game.input.state.b = false
    U.wait(6)
    return landX or p.cellX, landY or p.cellY, jumped
  end

  -- Which of World:busy's arms is up, for the log.
  local function busyReason()
    if world.vm and world.vm:running() then return "vm" end
    if world.mapSetup ~= nil then return "mapSetup" end
    if world.textbox ~= nil then return "textbox" end
    if world.moveState ~= nil then return "moveState" end
    if world.choicebox ~= nil then return "choicebox" end
    if world.fishing ~= nil then return "fishing" end
    if world.headbutt ~= nil then return "headbutt" end
    if world.fieldMove ~= nil then return "fieldMove" end
    return "none"
  end

  -- Wait for the world to go idle, dismissing anything that is waiting on a
  -- button.
  --
  -- This is the driver's problem, not the mod's.  Warping onto a live route
  -- can land the player in front of an NPC or a trigger, and the script that
  -- starts keeps World:busy() true -- through the next setMap, because a warp
  -- does not cancel a running script.  The mod then correctly declines to
  -- move a player the engine itself would not move (World:step returns above
  -- its movement arm while busy), so without this the second case onward
  -- measures the leftovers of the first.
  local function settle(budget)
    for _ = 1, (budget or 240) do
      if not world:busy() then return true end
      if world.textbox ~= nil or world.choicebox ~= nil then
        game.input.pressQueue[#game.input.pressQueue + 1] = "b"
        game.input.state.b = true
        U.wait(2)
        game.input.state.b = false
      end
      coroutine.yield()
    end
    return not world:busy()
  end

  local function place(mapId, c)
    -- settle BEFORE the warp as well: a script still running here would ride
    -- through setMap and be waiting on the other side
    settle()
    assert(world:setMap(mapId, c.x, c.y, c.dir), "setMap failed for " .. mapId)
    U.wait(8)
    local idle = settle()
    world.player.turnArmed = false
    if not idle then
      U.log("WARN", "world still busy after placing at", c.x, c.y,
            "reason:", busyReason())
    end
    return idle
  end

  -- Everything Ledge.tick consults, read back at the moment a climb is about
  -- to be asked for.  A refusal this driver cannot explain is worse than a
  -- failure it can, so the state goes in the log next to the verdict.
  local function diagnose(tag, c)
    local p, map = world.player, world.map
    local d = DELTA[c.dir]
    local gx, gy = c.x + d[1], c.y + d[2]
    local occupied = false
    for _, e in ipairs(world.entities or {}) do
      if e ~= p and not e.passable
         and ((e.cellX == c.lx and e.cellY == c.ly)
              or (e.targetX == c.lx and e.targetY == c.ly)) then
        occupied = true
      end
    end
    local okAccept, accepts = pcall(world.acceptsMenuInput, world)
    U.log("DIAG", tag,
      "facing=" .. tostring(p.facing), "want=" .. c.dir,
      "moving=" .. tostring(p.moving), "jumping=" .. tostring(p.jumping),
      "at=" .. tostring(p.cellX) .. "," .. tostring(p.cellY),
      "busy=" .. tostring(world:busy()) .. "/" .. busyReason(),
      "accepts=" .. tostring(okAccept and accepts),
      "gapWalk=" .. tostring(map:isWalkable(gx, gy)),
      "landWalk=" .. tostring(map:isWalkable(c.lx, c.ly)),
      "landColl=" .. string.format("%#x", map:cellCollision(c.lx, c.ly) or 0),
      "landOccupied=" .. tostring(occupied),
      "entities=" .. tostring(#(world.entities or {})))
  end

  -- ---- the survey, then the climbs

  local surveyed, best, bestMap = 0, nil, nil
  for _, mapId in ipairs(MAPS) do
    if world.maps and world.maps[mapId] then
      if world:setMap(mapId, 5, 5, "down") then
        U.wait(4)
        local found = candidates()
        surveyed = surveyed + #found
        U.log("INFO", mapId, "climbable cells:", #found)
        if #found > 0 and not best then
          best, bestMap = found, mapId
        end
      end
    else
      U.log("INFO", mapId, "not in this dataset")
    end
  end

  expect(surveyed > 0,
         "Gold: Johto's routes carry climbable ledge cells at all, found:",
         surveyed)
  if not best then
    U.log("FAILURES", (checks - fails) .. "/" .. checks, "checks")
    return false
  end

  -- Pick one candidate per direction the map offers, so the shots show more
  -- than one shape of ledge where Johto has more than one.
  local perDir, order = {}, {}
  for _, c in ipairs(best) do
    if not perDir[c.dir] then
      perDir[c.dir] = c
      order[#order + 1] = c.dir
    end
  end
  U.log("INFO", "climbing on", bestMap, "-- directions available:",
        table.concat(order, ","))

  for i, dir in ipairs(order) do
    local c = perDir[dir]
    local idle = place(bestMap, c)
    diagnose("climb#" .. i .. " " .. dir, c)
    expect(idle, ("Gold: the world is idle before climb #%d, so a refusal "
      .. "would be the mod's answer and not a leftover script"):format(i))
    shot(("gold_%d_%s_1_before"):format(i, dir))
    local x, y, jumped = hold(dir, 60, true,
      function() shot(("gold_%d_%s_2_midair"):format(i, dir)) end)
    shot(("gold_%d_%s_3_after"):format(i, dir))
    expect(jumped, ("Gold: B+%s climbs on %s at (%d,%d)")
      :format(dir:upper(), bestMap, c.x, c.y))
    expect(x == c.lx and y == c.ly,
      ("Gold: landed on the ledge tile, want (%d,%d) got:")
        :format(c.lx, c.ly), x, y)
  end

  -- The round trip, on Gold's own data: our climb puts the player ON the
  -- ledge tile, and Gold's untouched .TryJump takes them straight back down.
  -- That is the two-way seam the feature is for, proven by handing the return
  -- leg entirely to the engine -- no B held on the way down.
  do
    local c = perDir[order[1]]
    place(bestMap, c)
    diagnose("roundtrip-up " .. c.dir, c)
    local _, _, up = hold(c.dir, 60, true)
    shot("gold_roundtrip_1_climbed")
    expect(up, "Gold: climbed for the round trip")
    local back = OPPOSITE[c.dir]
    world.player.turnArmed = false
    local bx, by, down = hold(back, 60, false)
    shot("gold_roundtrip_2_dropped_back")
    expect(down, "Gold: and Gold's own hop takes you straight back down")
    expect(bx == c.x and by == c.y,
      ("Gold: back where the climb started, want (%d,%d) got:"):format(c.x, c.y),
      bx, by)
  end

  -- Without B, Gold is Gold.
  do
    local c = perDir[order[1]]
    place(bestMap, c)
    local _, _, jumped = hold(c.dir, 60, false)
    shot("gold_no_b_no_climb")
    expect(not jumped, "Gold: without B the ledge stays one-way")
  end

  -- And the option switch really switches it off.
  do
    if setOption("jump", false) then
      local c = perDir[order[1]]
      place(bestMap, c)
      local _, _, jumped = hold(c.dir, 60, true)
      shot("gold_option_off_no_climb")
      expect(not jumped, "Gold: B TO CLIMB off means no climb")
      setOption("jump", nil)
    else
      U.log("SKIP", "no loader handle for the options store")
    end
  end

  U.log(fails == 0 and "ALL PASS" or "FAILURES",
        (checks - fails) .. "/" .. checks, "checks")
  U.log("INFO", "screenshots:", shotN, "in", shotDir)
  return fails == 0
end
