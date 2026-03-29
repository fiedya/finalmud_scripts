SCRIPTS_VERSION = "1.0.2"

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
  local ok, err = pcall(dofile, getMudletHomeDir() .. "/" .. file)
  if not ok then
    cecho(string.format("<red>[Scripts] Błąd ładowania %s: %s\n", file, tostring(err)))
  end
end

for name, mod in pairs(modules) do
  if type(mod) == "table" and type(mod.init) == "function" then
    pcall(mod.init)
  end
end

cecho("<green>[Scripts] System loaded\n")
