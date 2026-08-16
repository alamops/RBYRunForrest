-- Driver: climbing Route 4's ledges, in a real LOVE run.
--
-- The headless suite proves the reverse-hop GEOMETRY against fixture maps.
-- This proves the feature: a live overworld, the real ROUTE_4 tile data, the
-- real input pipeline, and the mod loaded through the real loader.
--
-- The three positive cases are the exact inverses of the three control cases
-- in tests/drivers/route4_ledge_bug223_test.lua, which is what makes them
-- worth running.  That driver establishes, on a good build, that:
--
--   A  from (40,8) DOWN hops the tile-55 south ledge and lands on (40,10)
--   B  from (44,6) RIGHT hops the cx45 side ledge and lands on (46,6)
--   C  from (51,5) LEFT  hops the cx50 side ledge and lands on (49,5)
--
-- so this driver starts where each of those landed, holds B and the opposite
-- direction, and asserts the player ends up where each of those started.
-- Every cell here is a cell the engine's own ledge test already vouches for.
--
-- Cases:
--   A' B+UP    from (40,10) climbs back to (40,8)
--   B' B+LEFT  from (46,6)  climbs back to (44,6)
--   C' B+RIGHT from (49,5)  climbs back to (51,5)
--   D  UP without B from (40,10) does NOT climb -- vanilla is untouched when
--      the button is not held, which is the whole contract with a player who
--      wants the one-way shortcut to stay one-way
--   E  B+UP with the JUMP option off does NOT climb
--   F  B+UP into a solid cliff face does NOT climb (a wall is not a ledge)
--   G  the climb works ON THE BIKE too
--   H  holding B on foot covers ground faster than walking, and the bike is
--      not slowed or sped by holding B
--
-- Run (from a private engine view with this mod symlinked into mods/):
--   POKEPORT_DRIVER=mods/rby_run_forrest/tests/drivers/route4_climb_test.lua \
--   POKEPORT_IDENTITY=runforrest POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local shotDir = os.getenv("POKEPORT_SHOTDIR") or "."
  local function shot(name) U.shot(game, shotDir .. "/" .. name) end

  -- a party + starter flag so the overworld is fully usable
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  end
  game.save.options = game.save.options or {}
  game.save.options.zoom = -2

  local fails, checks = 0, 0
  local function expect(cond, ...)
    checks = checks + 1
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  -- The mod's own options store, reached the way the manager reaches it, so
  -- case E turns the feature off through the same switch a player would.
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

  -- Hold `dir` (optionally with B) for n frames from a known cell.
  --
  -- Returns the cell the FIRST hop landed on, whether a hop happened at all,
  -- and the cell the hold finally ended on.  The landing is captured on the
  -- frame the arc runs out rather than read at the end of the hold, because a
  -- held direction keeps walking after a hop lands -- so "where did the climb
  -- put me" and "where did I stop" are two different questions and only the
  -- first one is about the climb.  p.hopFrames is set only by a two-cell
  -- jump, which makes it the honest witness that a CLIMB happened rather than
  -- a walk that happened to cover two cells.
  local function holdDir(x, y, facing, dir, frames, withB, onBike)
    game.save.onBike = onBike and true or false
    U.teleport(game, "ROUTE_4", x, y, facing)
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6)
    local p = game.overworld.player
    local hopSeen, arcWas, landX, landY = false, false, nil, nil
    for _ = 1, frames do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      if withB then game.input.state.b = true end
      coroutine.yield()
      local arc = (p.hopFrames or 0) > 0
      if arc then hopSeen = true end
      -- the arc has just run out: this is the landing cell
      if arcWas and not arc and not landX then landX, landY = p.cellX, p.cellY end
      arcWas = arc
    end
    game.input.state[dir] = false
    game.input.state.b = false
    U.wait(6)
    return landX or p.cellX, landY or p.cellY, hopSeen, p.cellX, p.cellY
  end

  -- A') the inverse of the control south-ledge hop: from where that hop
  -- LANDED, B+UP climbs back to where it took off.
  do
    U.teleport(game, "ROUTE_4", 40, 10, "up")
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6); shot("climb_south_ledge_before.png")
    local x, y, hop = holdDir(40, 10, "up", "up", 60, true)
    shot("climb_south_ledge_after.png")
    expect(hop, "A': B+UP climbs the south ledge (hop arc seen)")
    expect(x == 40 and y <= 8, "A': climbed back onto the ledge top, got:", x, y)
  end

  -- B') the cx45 right-facing side ledge, climbed westward.
  do
    local x, y, hop = holdDir(46, 6, "left", "left", 40, true)
    expect(hop, "B': B+LEFT climbs the cx45 side ledge (hop arc seen)")
    expect(x == 44 and y == 6, "B': landed west of the side ledge, got:", x, y)
  end

  -- C') the cx50 left-facing side ledge, climbed eastward.
  do
    local x, y, hop = holdDir(49, 5, "right", "right", 40, true)
    expect(hop, "C': B+RIGHT climbs the cx50 side ledge (hop arc seen)")
    expect(x == 51 and y == 5, "C': landed east of the side ledge, got:", x, y)
  end

  -- D) without B, nothing changes.  A player who never touches B plays the
  -- game the mod was installed into.
  do
    local x, y, hop = holdDir(40, 10, "up", "up", 60, false)
    expect(not hop, "D: UP without B does not climb")
    expect(y == 10, "D: bonked below the ledge as vanilla does, got:", x, y)
  end

  -- E) and the option switch really switches it off.
  do
    if setOption("jump", false) then
      local x, y, hop = holdDir(40, 10, "up", "up", 60, true)
      expect(not hop, "E: B+UP with B TO CLIMB off does not climb")
      expect(y == 10, "E: stayed below the ledge, got:", x, y)
      setOption("jump", nil)
    else
      U.log("SKIP", "E: no loader handle for the options store")
    end
  end

  -- F) a solid mountain-wall face (OVERWORLD tile 58) is not a ledge in
  -- either direction.  The control driver's case E proves DOWN into it bonks;
  -- this proves the climb does not invent a way up it.
  do
    local x, y, hop = holdDir(80, 6, "up", "up", 40, true)
    expect(not hop, "F: B+UP into a solid cliff face does not climb")
    expect(x == 80 and y == 6, "F: bonked at the cliff face, got:", x, y)
  end

  -- G) on the bike.  The bike is the reason the climb is gated on B rather
  -- than on running: a cyclist is not running, and still wants the way back.
  do
    local x, y, hop = holdDir(40, 10, "up", "up", 60, true, true)
    expect(hop, "G: B+UP climbs while riding the bike (hop arc seen)")
    expect(x == 40 and y <= 8, "G: the bike climbed the ledge, got:", x, y)
    game.save.onBike = false
  end

  -- H) the running shoes themselves, measured rather than asserted.
  --
  -- Run EAST along row 3 of the east plateau, which the control driver
  -- establishes as open tile-57 ground from roughly x=72 to x=80 -- no
  -- ledges, no terraces, nothing to hop.  Measuring on a stretch with ledges
  -- in it measures the ledges, not the pace.
  --
  -- 64 frames is chosen to stay inside that stretch at every pace: a walk is
  -- 16 frames a tile (4 tiles) and everything faster is 8 (8 tiles), so the
  -- fastest run ends at x=78 with ground to spare.
  do
    local FRAMES, FROM = 64, 70
    local function distance(withB, onBike)
      local _, _, hop, endX = holdDir(FROM, 3, "right", "right", FRAMES,
                                      withB, onBike)
      return endX - FROM, hop
    end
    local walked, walkHop = distance(false, false)
    local ran, runHop = distance(true, false)
    local biked, bikeHop = distance(false, true)
    local bikedB, bikeBHop = distance(true, true)
    game.save.onBike = false
    U.log("INFO", "cells in", FRAMES, "frames -- walk:", walked, "run:", ran,
          "bike:", biked, "bike+B:", bikedB)
    expect(not (walkHop or runHop or bikeHop or bikeBHop),
           "H: the measured stretch is flat (no hop in any of the four runs)")
    expect(ran > walked, "H: holding B on foot covers more ground than walking")
    expect(ran == biked,
           "H: and running is bike-fast, which is the whole design")
    expect(biked == bikedB, "H: the bike's pace is the same with B held")
  end

  U.log(fails == 0 and "ALL PASS" or "FAILURES",
        (checks - fails) .. "/" .. checks, "checks")
  return fails == 0
end
