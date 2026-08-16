-- Wiring.  Two options rows and two hooks, in that order so the first tick
-- after install already reads a defined schema.

local need, mod = ...
local Run = need("Run")
local Ledge = need("Ledge")

local M = {}

function M.install()
  mod.options:define({
    -- Both default on, because they are the reason the mod is installed.
    -- Both are a row at all because B already means "cancel" everywhere
    -- else: a player who finds their walk unexpectedly fast, or who wants a
    -- ledge to stay the one-way shortcut the game designed it as, should
    -- have somewhere to turn it off short of uninstalling.
    { key = "run", label = "B TO RUN", type = "toggle", default = true },
    { key = "jump", label = "B TO CLIMB", type = "toggle", default = true },
  })

  Run.install()
  Ledge.install()
end

return M
