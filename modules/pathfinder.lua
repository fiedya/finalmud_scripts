cecho("<green>[Scripts] Loaded: modules/pathfinder.lua\n")

modules.pathfinder = modules.pathfinder or {}

local pathfinder = modules.pathfinder
pathfinder.VERSION = "1.2.0"

pathfinder.config = {
  gmcp_event  = "gmcp.Room.Info",
  hi_r        = 255,
  hi_g        = 165,
  hi_b        = 0,
  hi_alpha    = 210,
}

pathfinder.active    = false
pathfinder.paused    = false
pathfinder.path      = {}
pathfinder.mapPath   = {}
pathfinder.lastPath  = {}
pathfinder.lastMapPath = {}
pathfinder.visited   = {}
pathfinder.handlerID = nil
pathfinder.loaded    = nil
pathfinder._handles  = pathfinder._handles or { aliases = {} }

local function saveDir()
  return getMudletHomeDir() .. "/paths/"
end

function pathfinder.onRoomChange()
  if not pathfinder.active or pathfinder.paused then return end
  local mudID = gmcp and gmcp.Room and gmcp.Room.Info and gmcp.Room.Info.id
  if not mudID or mudID == "" then return end
  if pathfinder.path[#pathfinder.path] == mudID then return end
  table.insert(pathfinder.path, mudID)
  local mapID = getPlayerRoom()
  table.insert(pathfinder.mapPath, mapID or 0)
  if not pathfinder.visited[mudID] then
    pathfinder.visited[mudID] = true
    if mapID then
      local c = pathfinder.config
      highlightRoom(mapID, c.hi_r, c.hi_g, c.hi_b, c.hi_r, c.hi_g, c.hi_b, 1, c.hi_alpha)
      pathfinder.visited[mudID] = mapID
      updateMap()
    end
  end
  utils.log(string.format("[Path] +%s  (step #%d)", mudID, #pathfinder.path), "<yellow>")
end

function pathfinder.start()
  if pathfinder.active then
    utils.log("[Path] Already recording — use /path_stop first.", "<yellow>")
    return
  end
  pathfinder.active  = true
  pathfinder.paused  = false
  pathfinder.path    = {}
  pathfinder.mapPath = {}
  pathfinder.visited = {}
  if pathfinder.handlerID then
    killAnonymousEventHandler(pathfinder.handlerID)
  end
  pathfinder.handlerID = registerAnonymousEventHandler(
    pathfinder.config.gmcp_event, "modules.pathfinder.onRoomChange")
  utils.log("[Path] Recording started.", "<green>")
  pathfinder.onRoomChange()
end

function pathfinder.stop(silent)
  if not pathfinder.active then
    if not silent then utils.log("[Path] No active recording.", "<yellow>") end
    return
  end
  if pathfinder.handlerID then
    killAnonymousEventHandler(pathfinder.handlerID)
    pathfinder.handlerID = nil
  end
  pathfinder.active = false
  pathfinder.paused = false
  for _, mapID in pairs(pathfinder.visited) do
    if type(mapID) == "number" then unHighlightRoom(mapID) end
  end
  updateMap()
  local n = #pathfinder.path
  utils.log(string.format("[Path] Stopped — %d room(s) recorded.", n), "<green>")
  if n > 0 then
    utils.log("[Path] IDs: " .. table.concat(pathfinder.path, ", "), "<cyan>")
  end
  pathfinder.lastPath    = pathfinder.path
  pathfinder.lastMapPath = pathfinder.mapPath
  pathfinder.path        = {}
  pathfinder.mapPath     = {}
  pathfinder.visited     = {}
end

function pathfinder.save(name)
  if not name or name == "" then
    utils.log("[Path] Usage: /path_save <name>", "<yellow>")
    return
  end
  local rooms    = pathfinder.active and pathfinder.path or pathfinder.lastPath
  local mapRooms = pathfinder.active and pathfinder.mapPath or pathfinder.lastMapPath
  if #rooms == 0 then
    utils.log("[Path] Nothing to save — record a path first.", "<yellow>")
    return
  end
  local parts = {}
  for _, id in ipairs(rooms) do parts[#parts + 1] = string.format('%q', id) end
  local mapParts = {}
  for _, mapID in ipairs(mapRooms or {}) do
    if type(mapID) == "number" and mapID > 0 then mapParts[#mapParts + 1] = tostring(mapID) end
  end
  local json = '{"name":' .. string.format('%q', name) .. ',"rooms":[' .. table.concat(parts, ",") .. '],"mapRooms":[' .. table.concat(mapParts, ",") .. "]}\n"
  local dir  = saveDir()
  local path = dir .. name .. ".json"
  if not io.exists(dir) then lfs.mkdir(dir) end
  local f, err = io.open(path, "w")
  if not f then utils.log("[Path] Could not write file: " .. tostring(err), "<red>") return end
  f:write(json)
  f:close()
  utils.log(string.format("[Path] Saved %d rooms as '%s' → %s", #rooms, name, path), "<green>")
end

function pathfinder.load(name)
  if not name or name == "" then
    utils.log("[Path] Usage: /path_load <name>", "<yellow>")
    return
  end
  local path = saveDir() .. name .. ".json"
  local f, err = io.open(path, "r")
  if not f then utils.log("[Path] File not found: " .. path .. " (" .. tostring(err) .. ")", "<red>") return end
  local raw = f:read("*a")
  f:close()
  local function parseStringArray(src, key)
    local out = {}
    local body = src:match('"' .. key .. '"%s*:%s*%[(.-)%]')
    if not body then return out end
    for item in body:gmatch('"(.-)"') do out[#out + 1] = item end
    return out
  end
  local function parseNumberArray(src, key)
    local out = {}
    local body = src:match('"' .. key .. '"%s*:%s*%[(.-)%]')
    if not body then return out end
    for item in body:gmatch('(%d+)') do out[#out + 1] = tonumber(item) end
    return out
  end
  local rooms = parseStringArray(raw, "rooms")
  if #rooms == 0 then for id in raw:gmatch('"([0-9a-f][0-9a-f]+)"') do rooms[#rooms + 1] = id end end
  local mapRooms = parseNumberArray(raw, "mapRooms")
  if #rooms == 0 then utils.log("[Path] Could not parse rooms from " .. path, "<red>") return end
  pathfinder.loaded = { name = name, rooms = rooms, mapRooms = mapRooms }
  utils.log(string.format("[Path] Loaded '%s' — %d rooms. Available as modules.pathfinder.loaded.rooms and .mapRooms.", name, #rooms), "<green>")
end

function pathfinder.help()
  cecho(
    "<white>\n" ..
    "<yellow>╔══════════════════════════════════════════════╗<reset>\n" ..
    "<yellow>║          <white>Pathfinder  —  Commands<yellow>           ║<reset>\n" ..
    "<yellow>╠══════════════════════════════════════════════╣<reset>\n" ..
    "<yellow>║ <white>/path_start          <cyan>Begin new recording      <yellow>║<reset>\n" ..
    "<yellow>║ <white>/path_stop           <cyan>Stop & print IDs         <yellow>║<reset>\n" ..
    "<yellow>║ <white>/path_pause          <cyan>Toggle pause/resume      <yellow>║<reset>\n" ..
    "<yellow>║ <white>/path_save <name>    <cyan>Save path to file        <yellow>║<reset>\n" ..
    "<yellow>║ <white>/path_load <name>    <cyan>Load path from file      <yellow>║<reset>\n" ..
    "<yellow>║ <white>/path_help           <cyan>Show this help           <yellow>║<reset>\n" ..
    "<yellow>╚══════════════════════════════════════════════╝<reset>\n" ..
    "<cyan>Saved files: <white>" .. saveDir() .. "<reset>\n"
  )
end

function pathfinder.pause()
  if not pathfinder.active then utils.log("[Path] No active recording.", "<yellow>") return end
  pathfinder.paused = not pathfinder.paused
  if pathfinder.paused then
    utils.log("[Path] PAUSED — walk back freely. /path_pause again to resume.", "<yellow>")
  else
    utils.log("[Path] RESUMED.", "<green>")
    pathfinder.onRoomChange()
  end
end

function pathfinder.clearHandles()
  for _, aliasId in ipairs(pathfinder._handles.aliases or {}) do
    killAlias(aliasId)
  end
  pathfinder._handles.aliases = {}
end

function pathfinder.registerAlias(pattern, handler)
  local aliasId = tempAlias(pattern, handler)
  table.insert(pathfinder._handles.aliases, aliasId)
  return aliasId
end

function pathfinder.getMatches(passedMatches)
  if type(passedMatches) == "table" then return passedMatches end
  if type(matches) == "table" then return matches end
  return {}
end

function pathfinder.init()
  pathfinder.clearHandles()
  pathfinder.registerAlias("^/path_start$", function() pathfinder.start() end)
  pathfinder.registerAlias("^/path_stop$", function() pathfinder.stop() end)
  pathfinder.registerAlias("^/path_pause$", function() pathfinder.pause() end)
  pathfinder.registerAlias("^/path_save\\s+(\\S+)$", function(passedMatches)
    local m = pathfinder.getMatches(passedMatches)
    pathfinder.save(m[2])
  end)
  pathfinder.registerAlias("^/path_load\\s+(\\S+)$", function(passedMatches)
    local m = pathfinder.getMatches(passedMatches)
    pathfinder.load(m[2])
  end)
  pathfinder.registerAlias("^/path_help$", function() pathfinder.help() end)
  utils.log("[Pathfinder] Loaded", "<cyan>")
end
