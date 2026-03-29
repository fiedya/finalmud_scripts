
SCRIPTS_VERSION = "1.0.2"

local function _scripts_debug(msg)
  cecho("<purple>[Scripts Debug] " .. tostring(msg) .. "\n")
end

_scripts_debug("core/main.lua loaded")

FILES = {
  "core/main.lua",
  "core/utils.lua",
  "core/commands.lua",
  "modules/pathfinder.lua",
  "modules/herbs.lua",
  "modules/combat.lua"
}

modules = modules or {}

for _, file in ipairs(FILES) do
  _scripts_debug("Loading file: " .. file)
  local ok, err = pcall(dofile, getMudletHomeDir() .. "/" .. file)
  if not ok then
    cecho(string.format("<red>[Scripts] Błąd ładowania %s: %s\n", file, tostring(err)))
    _scripts_debug("Error loading " .. file .. ": " .. tostring(err))
  end
end

for name, mod in pairs(modules) do
  _scripts_debug("Module: " .. tostring(name))
  if type(mod) == "table" and type(mod.init) == "function" then
    local ok, err = pcall(mod.init)
    if not ok then
      _scripts_debug("Error in module init for " .. tostring(name) .. ": " .. tostring(err))
    end
  end
end

_scripts_debug("Checking if aliases are registered...")
_scripts_debug("installer_update_alias: " .. tostring(installer_update_alias))
_scripts_debug("scripts_version_alias: " .. tostring(scripts_version_alias))
_scripts_debug("scripts_reload_alias: " .. tostring(scripts_reload_alias))

cecho("<green>[Scripts] System loaded\n")
