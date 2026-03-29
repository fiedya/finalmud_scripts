_SCRIPTS_LOADED = _SCRIPTS_LOADED or {}
if not _SCRIPTS_LOADED["core/utils.lua"] then
  cecho("<green>[Scripts] Loaded: core/utils.lua\n")
  _SCRIPTS_LOADED["core/utils.lua"] = true
end
utils = {}

function utils.log(msg, color)
  color = color or "<white>"
  cecho(string.format("%s[Scripts] %s\n", color, msg))
end

function utils.fileExists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end
