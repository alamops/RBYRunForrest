-- Driver: climbing Route 4's ledges, in a real LOVE run (Gen 1).
--
-- The headless suite proves the reverse-hop GEOMETRY against fixture maps.
-- This proves the feature: a live overworld, the real ROUTE_4 tile data, the
-- real input pipeline, and the mod loaded through the real loader.  It also
-- captures a screenshot at each beat -- standing below the ledge, mid-air
-- over it, and standing on top -- so the result can be eyeballed and not just
-- read off a PASS line.
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
--   D  UP without B does NOT climb -- vanilla is untouched when the button is
--      not held, which is the whole contract with a player who wants the
--      one-way shortcut to stay one-way
--   E  B+UP with the B TO CLIMB option off does NOT climb
--   F  B+UP into a solid mountain-wall face does NOT climb
--   G  the climb works ON THE BIKE too
--   H  the four paces, measured on a flat stretch: a walk, a run, the bike,
--      and the bike with B held, which has to come out ahead of the run
--   I  the round trip: drop off a ledge the vanilla way, then climb back
--   J  a survey of every climbable cell ROUTE_4 actually has
--   L  with ALWAYS RUN on, UP alone climbs and a walk alone runs -- the
--      button stops being asked for, and nothing else about either half
--      changes
--
-- Run (from a private engine view with this mod symlinked into mods/):
--   POKEPORT_DRIVER=mods/rby_run_forrest/tests/drivers/route4_climb_test.lua \
--   POKEPORT_IDENTITY=runforrest POKEPORT_TOUCH=0 \
--   POKEPORT_SHOTDIR=<dir> love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local shotDir = os.getenv("POKEPORT_SHOTDIR") or "."
  local shotN = 0
  local function shot(name)
    shotN = shotN + 1
    U.shot(game, ("%s/%02d_%s.png"):format(shotDir, shotN, name))
  end

  -- Silence.
  --
  -- A driver run is automated: nobody is listening, and an unattended run
  -- that plays the ledge cue and the route theme out loud is just noise on
  -- whatever machine happens to be running it. LOVE's master volume is the
  -- one knob that covers both music and SFX no matter how the engine sets
  -- them per source, so this is the whole mute -- and it is only the output
  -- level, so every Sound.play the climb makes still runs, and a crash in
  -- the audio path would still fail this run rather than being muted out of
  -- sight. POKEPORT_DRIVER_AUDIO=1 turns the sound back on for a human
  -- watching a run.
  if os.getenv("POKEPORT_DRIVER_AUDIO") ~= "1" then
    pcall(function() love.audio.setVolume(0) end)
  end

  -- a party + starter flag so the overworld is fully usable
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  end
  -- zoomed out so a shot frames the whole cliff rather than the player's feet
  game.save.options = game.save.options or {}
  game.save.options.zoom = -2

  local fails, checks = 0, 0
  local function expect(cond, ...)
    checks = checks + 1
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  local function place(x, y, facing, onBike)
    game.save.onBike = onBike and true or false
    U.teleport(game, "ROUTE_4", x, y, facing)
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6)
  end

  -- Hold `dir` (optionally with B) for n frames.
  --
  -- Returns the cell the hop landed on, whether a hop happened at all, and
  -- the cell the hold finally ended on.  Those are two different questions,
  -- because a held direction keeps walking after a hop lands, and only the
  -- first is about the climb.  p.hopFrames is set only by a two-cell jump,
  -- which makes it the honest witness that a CLIMB happened rather than a
  -- walk that happened to cover two cells.
  --
  -- The landing is taken from the hop COMPLETING -- the player standing still
  -- with the script-move queue drained -- and deliberately not from the arc
  -- running out.  Those two are usually the same frame and sometimes are not:
  -- checkLedgeHop sizes the arc as `stepFramesCur * 2`, and stepFramesCur is
  -- whatever the last committed step happened to cost, so a hop taken shortly
  -- after dismounting the bike gets a 16-frame arc over a 32-frame move and
  -- the arc expires a whole cell early.  That is the engine's own cosmetic
  -- quirk and neither generation's landing depends on it, so nothing here
  -- should either.
  --
  -- `onAir` fires once, on the first frame the arc is up, and releases the
  -- pad before it runs: a screenshot spins the frame loop for as long as the
  -- capture takes, and a direction still held through that would walk on past
  -- the landing before the "after" shot is taken.  The hop itself is a queued
  -- script move and finishes regardless of the pad.
  local function hold(dir, frames, withB, onAir)
    local ow = game.overworld
    local p = ow.player
    local hopSeen, landX, landY, fired = false, nil, nil, false
    for _ = 1, frames do
      if not fired then
        table.insert(game.input.pressQueue, dir)
        game.input.state[dir] = true
        if withB then game.input.state.b = true end
      end
      coroutine.yield()
      if (p.hopFrames or 0) > 0 then
        hopSeen = true
        if not fired and onAir then
          fired = true
          game.input.state[dir] = false
          game.input.state.b = false
          onAir()
        end
      end
      if hopSeen and not landX and not p.moving
         and #(ow.scriptMoves or {}) == 0 then
        landX, landY = p.cellX, p.cellY
      end
    end
    game.input.state[dir] = false
    game.input.state.b = false
    U.wait(6)
    return landX or p.cellX, landY or p.cellY, hopSeen, p.cellX, p.cellY
  end

  -- before / mid-air / after, which is the whole story of one climb
  local function climbShots(slug, x, y, dir, withB, onBike, frames)
    place(x, y, dir, onBike)
    shot(slug .. "_1_before")
    local lx, ly, hop = hold(dir, frames or 60, withB,
                             function() shot(slug .. "_2_midair") end)
    shot(slug .. "_3_after")
    return lx, ly, hop
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

  -- A measured pace is only this mod's answer while this mod is the only
  -- link on the seam.  The engine records the owner of every wrap, so the two
  -- cases that MEASURE (H, and the pace half of L) ask first and stand down
  -- with a named SKIP rather than asserting the sum of two mods' arithmetic
  -- as if it were ours -- which is exactly what a second running-shoes mod in
  -- the same mods/ folder would otherwise make them do.
  local function sharesSpeedHook()
    local chain = loader and loader.hooks and loader.hooks.chains
      and loader.hooks.chains["movement.speed"]
    for _, entry in ipairs(chain or {}) do
      if entry.owner and entry.owner ~= "rby_run_forrest" then
        return tostring(entry.owner)
      end
    end
    return nil
  end

  -- A') the inverse of the control south-ledge hop: from where that hop
  -- LANDED, B+UP climbs back to where it took off.
  do
    local x, y, hop = climbShots("A_south_climb", 40, 10, "up", true)
    expect(hop, "A': B+UP climbs the south ledge (hop arc seen)")
    expect(x == 40 and y <= 8, "A': climbed back onto the ledge top, got:", x, y)
  end

  -- B') the cx45 right-facing side ledge, climbed westward.
  do
    local x, y, hop = climbShots("B_west_climb", 46, 6, "left", true, false, 40)
    expect(hop, "B': B+LEFT climbs the cx45 side ledge (hop arc seen)")
    expect(x == 44 and y == 6, "B': landed west of the side ledge, got:", x, y)
  end

  -- C') the cx50 left-facing side ledge, climbed eastward.
  do
    local x, y, hop = climbShots("C_east_climb", 49, 5, "right", true, false, 40)
    expect(hop, "C': B+RIGHT climbs the cx50 side ledge (hop arc seen)")
    expect(x == 51 and y == 5, "C': landed east of the side ledge, got:", x, y)
  end

  -- D) without B, nothing changes.  A player who never touches B plays the
  -- game the mod was installed into.
  do
    place(40, 10, "up")
    local x, y, hop = hold("up", 60, false)
    shot("D_no_b_no_climb")
    expect(not hop, "D: UP without B does not climb")
    expect(y == 10, "D: bonked below the ledge as vanilla does, got:", x, y)
  end

  -- E) and the option switch really switches it off.
  do
    if setOption("jump", false) then
      place(40, 10, "up")
      local x, y, hop = hold("up", 60, true)
      shot("E_option_off_no_climb")
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
    place(80, 6, "up")
    local x, y, hop = hold("up", 40, true)
    shot("F_cliff_face_no_climb")
    expect(not hop, "F: B+UP into a solid cliff face does not climb")
    expect(x == 80 and y == 6, "F: bonked at the cliff face, got:", x, y)
  end

  -- G) on the bike.  The bike is the reason the climb is gated on B rather
  -- than on running: a cyclist is not running, and still wants the way back.
  do
    local x, y, hop = climbShots("G_bike_climb", 40, 10, "up", true, true)
    expect(hop, "G: B+UP climbs while riding the bike (hop arc seen)")
    expect(x == 40 and y <= 8, "G: the bike climbed the ledge, got:", x, y)
    game.save.onBike = false
  end

  -- H) the four paces themselves, measured rather than asserted.
  --
  -- Run EAST along row 3 of the east plateau, which the control driver
  -- establishes as open tile-57 ground from roughly x=72 to x=80 -- no
  -- ledges, no terraces, nothing to hop.  Measuring on a stretch with ledges
  -- in it measures the ledges, not the pace.
  --
  -- 32 frames is chosen to stay inside that stretch at every pace, and the
  -- fastest pace is what sets it: a boosted bike is 4 frames a tile, so 32
  -- frames is 8 tiles and ends at x=78 with ground to spare.  All four runs
  -- start from the same cell and get the same window, so the gaps between
  -- them ARE the features.
  --
  -- The comparisons are ordering plus a one-cell tolerance rather than exact
  -- equality: no window divides evenly into every pace, so which side of a
  -- tile boundary a run ends on moves by one with where its first step was
  -- committed.  An exact-equality assertion here measures that boundary.
  local speedHookShared = sharesSpeedHook()
  if speedHookShared then
    U.log("SKIP", "H: " .. speedHookShared .. " also wraps movement.speed, so"
      .. " a measured pace would be the chain's answer and not this mod's")
  else
    local FRAMES, FROM = 32, 70
    local function distance(withB, onBike, slug)
      place(FROM, 3, "right", onBike)
      local _, _, hop, endX = hold("right", FRAMES, withB)
      if slug then shot(slug) end
      return endX - FROM, hop
    end
    local walked, walkHop = distance(false, false, "H_pace_1_walk_32f")
    local ran, runHop = distance(true, false, "H_pace_2_run_32f")
    local biked, bikeHop = distance(false, true, "H_pace_3_bike_32f")
    local bikedB, bikeBHop = distance(true, true, "H_pace_4_bike_plus_b_32f")
    game.save.onBike = false
    U.log("INFO", "cells in", FRAMES, "frames -- walk:", walked, "run:", ran,
          "bike:", biked, "bike+B:", bikedB)
    expect(not (walkHop or runHop or bikeHop or bikeBHop),
           "H: the measured stretch is flat (no hop in any of the four runs)")
    expect(ran > walked, "H: holding B on foot covers more ground than walking")
    expect(math.abs(ran - biked) <= 1,
           "H: and running is bike-fast, which is the whole design,",
           ran, "vs", biked)
    expect(bikedB > biked,
           "H: holding B on the bike is faster than coasting on it,",
           bikedB, "vs", biked)
    expect(bikedB > ran,
           "H: and a boosted bike beats a runner, which is the ordering the",
           "feature is for,", bikedB, "vs", ran)
  end

  -- I) the round trip, which is the feature in one sequence: drop off the
  -- ledge exactly as the game has always let you, change your mind, and come
  -- back up.  The DOWN half holds no B at all, so it is the vanilla hop.
  do
    place(40, 8, "down")
    shot("I_roundtrip_1_on_top")
    local _, downY, downHop = hold("down", 40, false,
                                   function() shot("I_roundtrip_2_dropping") end)
    shot("I_roundtrip_3_dropped")
    expect(downHop, "I: the vanilla drop still works with the mod installed")
    expect(downY >= 10, "I: dropped below the ledge, got y:", downY)

    place(40, 10, "up")
    local _, upY, upHop = hold("up", 60, true,
                               function() shot("I_roundtrip_4_climbing") end)
    shot("I_roundtrip_5_back_on_top")
    expect(upHop, "I: and B+UP brings you back")
    expect(upY <= 8, "I: back on the ledge top, got y:", upY)
  end

  -- K) running AT a ledge climbs it without stopping.
  --
  -- Every case above starts the player already standing on the take-off cell,
  -- which is not how anyone plays: they hold B and a direction and run at the
  -- thing. The climb is decided on input.step, and p.moving is false for a
  -- single frame between committed steps, so the arrival frame is also a
  -- frame the climb can start on -- no pause, no second press.
  --
  -- Asserted three ways, because "it worked" is the easy half: a hop
  -- happened, the player ended up past the ledge, and they never sat idle on
  -- the take-off cell for anything like a step's worth of frames. That last
  -- one is what would catch a regression turning this into "walk up, stop,
  -- press again" -- which still ends in the right cell and would pass the
  -- first two checks on its own.
  do
    place(40, 11, "up")
    shot("K_runup_1_approaching")
    local p = game.overworld.player
    local hop, idleOnTakeoff, run = false, 0, 0
    for _ = 1, 90 do
      table.insert(game.input.pressQueue, "up")
      game.input.state.up = true
      game.input.state.b = true
      coroutine.yield()
      if (p.hopFrames or 0) > 0 then hop = true end
      if p.cellY == 10 and not p.moving then
        run = run + 1
        if run > idleOnTakeoff then idleOnTakeoff = run end
      else
        run = 0
      end
    end
    game.input.state.up = false
    game.input.state.b = false
    U.wait(6)
    shot("K_runup_2_past_the_ledge")
    U.log("INFO", "run-up: ended (" .. p.cellX .. "," .. p.cellY .. ")",
          "idle frames on the take-off cell:", idleOnTakeoff)
    expect(hop, "K: running at the ledge climbs it (hop arc seen)")
    expect(p.cellY <= 8, "K: and carried on past it, got y:", p.cellY)
    -- A walk tile is 16 frames and a run tile 8; anything at or above a whole
    -- walk tile spent standing still on that cell is a stop, not a stride.
    expect(idleOnTakeoff < 16,
           "K: without stopping on the take-off cell, idle frames:",
           idleOnTakeoff)
  end

  -- L) ALWAYS RUN: the same two features, with nothing held but a direction.
  --
  -- The row moves the gate off B rather than adding a third feature, so this
  -- re-asks the two cases that define each half -- case A' for the climb and
  -- case H for the pace -- with the button never touched.  Case D above is
  -- the control: the same press, the same cell, with the row off.
  do
    if setOption("always", true) then
      place(40, 10, "up")
      shot("L_always_1_before")
      local x, y, hop = hold("up", 60, false,
                             function() shot("L_always_2_midair") end)
      shot("L_always_3_after")
      expect(hop, "L: with ALWAYS RUN on, UP alone climbs (hop arc seen)")
      expect(x == 40 and y <= 8,
             "L: climbed back onto the ledge top with no B, got:", x, y)

      -- and the pace, on foot and on the bike, measured on the same flat
      -- stretch and over the same 32-frame window as case H so the numbers
      -- sit alongside that case's.  Each pace is measured with the row on
      -- and nothing held, then again with the row off, so every comparison
      -- is between two runs of this driver rather than a remembered figure.
      --
      -- The claim is "clears the unheld pace, matches the held one to within
      -- a cell", for the same tile-boundary reason case H states -- and it
      -- stands down for the same reason too when the seam is shared.
      if speedHookShared then
        setOption("always", nil)
        U.log("SKIP", "L: pace not measured -- " .. speedHookShared
          .. " also wraps movement.speed, so it would be the chain's answer")
      else
        local FRAMES, FROM = 32, 70
        local function distance(withB, onBike)
          place(FROM, 3, "right", onBike)
          local _, _, hop, endX = hold("right", FRAMES, withB)
          game.save.onBike = false
          return endX - FROM, hop
        end
        local alwaysRan, alwaysHop = distance(false, false)
        shot("L_always_4_pace_32f")
        local alwaysBiked, alwaysBikeHop = distance(false, true)
        setOption("always", nil)
        local walked, walkHop = distance(false, false)
        local heldRan, heldHop = distance(true, false)
        local coasted, coastHop = distance(false, true)
        local heldBiked, heldBikeHop = distance(true, true)
        U.log("INFO", "cells in", FRAMES, "frames -- always-run:", alwaysRan,
              "walk:", walked, "B held:", heldRan, "| always-bike:", alwaysBiked,
              "coast:", coasted, "bike+B:", heldBiked)
        expect(not (alwaysHop or alwaysBikeHop or walkHop or heldHop
                    or coastHop or heldBikeHop),
               "L: the measured stretch is flat (no hop in any of the six)")
        expect(alwaysRan > walked,
               "L: with ALWAYS RUN on, a player holding nothing runs,",
               alwaysRan, "cells against a walk's", walked)
        expect(math.abs(alwaysRan - heldRan) <= 1,
               "L: and runs at the pace B held gives,", alwaysRan, "vs",
               heldRan)
        expect(alwaysBiked > coasted,
               "L: the bike is boosted with nothing held too,", alwaysBiked,
               "cells against a coast's", coasted)
        expect(math.abs(alwaysBiked - heldBiked) <= 1,
               "L: at the pace B held gives it,", alwaysBiked, "vs", heldBiked)
      end
    else
      U.log("SKIP", "L: no loader handle for the options store")
    end
  end

  -- J) a survey: how many cells on this one map the feature actually opens.
  -- Read straight off the live map and the live ledge rows, so it counts what
  -- the mod would really accept rather than what this driver remembered to
  -- try.  A zero here would mean every case above passed on a special case.
  do
    local ow = game.overworld
    local map = ow.map
    local rows = game.data.field.ledges or {}
    local tileset = map.def.tileset
    local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                    left = { -1, 0 }, right = { 1, 0 } }
    local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
    local found, byDir = 0, { up = 0, down = 0, left = 0, right = 0 }
    for y = 0, map.def.height * 2 - 1 do
      for x = 0, map.def.width * 2 - 1 do
        for dir, d in pairs(DELTA) do
          local gx, gy = x + d[1], y + d[2]
          local lx, ly = x + d[1] * 2, y + d[2] * 2
          if map:inBounds(gx, gy) and map:inBounds(lx, ly)
             and map:isWalkableCell(x, y)
             and not map:isWalkableCell(gx, gy)
             and map:isWalkableCell(lx, ly) then
            local front = map:cellTile(gx, gy)
            local back = OPPOSITE[dir]
            for _, ledge in ipairs(rows) do
              if (ledge.tileset or "OVERWORLD") == tileset
                 and ledge.facing == back and ledge.input == back
                 and ledge.ledgeTile == front then
                found = found + 1
                byDir[dir] = byDir[dir] + 1
                break
              end
            end
          end
        end
      end
    end
    U.log("INFO", "ROUTE_4 climbable cells:", found,
          "-- up:", byDir.up, "right:", byDir.right, "left:", byDir.left,
          "down:", byDir.down)
    expect(found > 0, "J: ROUTE_4 has climbable cells at all")
    expect(byDir.down == 0,
           "J: and none of them climb DOWNWARD (Gen 1 has no up-facing ledge)")
  end

  U.log(fails == 0 and "ALL PASS" or "FAILURES",
        (checks - fails) .. "/" .. checks, "checks")
  U.log("INFO", "screenshots:", shotN, "in", shotDir)
  return fails == 0
end
