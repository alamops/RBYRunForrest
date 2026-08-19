-- Wiring.  Two options rows and two hooks, in that order so the first tick
-- after install already reads a defined schema.

local need, mod = ...
local Run = need("Run")
local Ledge = need("Ledge")

local M = {}

function M.install()
  mod.options:define({
    -- The first two default on, because they are the reason the mod is
    -- installed.  Both are a row at all because B already means "cancel"
    -- everywhere else: a player who finds their walk unexpectedly fast, or
    -- who wants a ledge to stay the one-way shortcut the game designed it
    -- as, should have somewhere to turn it off short of uninstalling.
    { key = "run", label = "B TO RUN", type = "toggle", default = true },
    { key = "jump", label = "B TO CLIMB", type = "toggle", default = true },
    -- The third defaults OFF, because holding B is what the two rows above
    -- are named after and is the behaviour a player who installed them
    -- asked for.  Turned on it moves the gate rather than adding a feature:
    -- the run and the climb stop asking for B and become simply how the
    -- player moves, the way the Gen 3+ Running Shoes do once you own them.
    -- It is deliberately not a master switch -- with B TO RUN off there is
    -- still no running, and with B TO CLIMB off still no climb, so a player
    -- can keep one half on the button and the other off entirely.
    { key = "always", label = "ALWAYS RUN", type = "toggle", default = false },
  })

  Run.install()
  Ledge.install()
end

return M
