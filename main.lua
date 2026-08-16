-- Run Forrest: hold B to run, and to climb the ledges you can only fall off.
--
-- The mod is split across src/*.lua, loaded through mod:read and an internal
-- resolver rather than the global require.  That keeps every file inside the
-- mod's own sandbox: nothing lands in package.loaded, the dev-mode
-- permissions tripwire sees only the engine requires this mod actually
-- declares engine_internals for, and the headless loader used by
-- `modkit validate` walks the same path the game does.
--
-- Nothing here raises.  A missing or malformed module disables the feature
-- with an attributed log line and leaves the vanilla game untouched -- the
-- mod being broken must never be the reason a player cannot play.

local MODULE_DIR = "src/"

return function(mod)
  local loadstr = loadstring or load
  local cache, loading = {}, {}
  local failed = false

  -- resolve a sibling module by name; returns nil once anything has failed
  -- so a partial wiring never half-installs
  local function need(name)
    if failed then return nil end
    local hit = cache[name]
    if hit ~= nil then return hit end

    if loading[name] then
      mod.log:error(
        "circular dependency reaching %s%s.lua -- break the cycle by moving "
        .. "the shared value into Config.lua", MODULE_DIR, name)
      failed = true
      return nil
    end
    loading[name] = true

    local path = MODULE_DIR .. name .. ".lua"
    local body = mod:read(path)
    if type(body) ~= "string" then
      mod.log:error(
        "missing %s -- the install is incomplete; reinstall the mod folder "
        .. "so every file under %s is present", path, MODULE_DIR)
      failed = true
      return nil
    end

    local chunk, syntaxErr = loadstr(body, "@rby_run_forrest/" .. path)
    if not chunk then
      mod.log:error("%s failed to parse (%s) -- restore it from a clean "
        .. "copy of the mod", path, tostring(syntaxErr))
      failed = true
      return nil
    end

    local ok, value = pcall(chunk, need, mod)
    if not ok then
      mod.log:error("%s failed to initialise (%s) -- report this with the "
        .. "line above", path, tostring(value))
      failed = true
      return nil
    end

    loading[name] = nil
    cache[name] = value == nil and true or value
    return cache[name]
  end

  local Install = need("Install")
  if failed or type(Install) ~= "table" then
    mod.log:warn("running and ledge climbing are off for this session; the "
      .. "vanilla game is unaffected")
    return
  end

  Install.install()
end
