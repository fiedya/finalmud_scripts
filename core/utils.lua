cecho("<green>[Scripts] Loaded: core/utils.lua\n")
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
