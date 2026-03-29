cecho("<green>[Scripts] Loaded: core/commands.lua\n")
function scripts_help()
  utils.log("Help", "<cyan>")
end

function scripts_version()
  utils.log("Version: " .. (SCRIPTS_VERSION or "unknown"), "<yellow>")
end

function scripts_reload()
  utils.log("Reloading...", "<yellow>")
  for _, file in ipairs(FILES) do
    local ok, err = pcall(dofile, getMudletHomeDir() .. "/" .. file)
    if not ok then
      utils.log("Błąd ładowania " .. file .. ": " .. tostring(err), "<red>")
    end
  end
  for name, mod in pairs(modules) do
    if type(mod) == "table" and type(mod.init) == "function" then
      pcall(mod.init)
    end
  end
  utils.log("Reload complete", "<green>")
end

if not scripts_help_alias then
  scripts_help_alias = tempAlias("^/scripts_help$", scripts_help)
end
if not scripts_version_alias then
  scripts_version_alias = tempAlias("^/scripts_version$", scripts_version)
end
if not scripts_reload_alias then
  scripts_reload_alias = tempAlias("^/scripts_reload$", scripts_reload)
end
