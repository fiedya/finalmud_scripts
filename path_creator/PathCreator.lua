--------------------------------------------------------------------------------
-- PathCreator.lua
-- Records a sequence of room IDs as you walk in Mudlet.
--
-- Commands:
--   /path_start       — begin a new recording (clears previous path)
--   /path_stop        — stop recording, print collected IDs, clear highlights
--   /path_pause       — toggle pause (backtrack without polluting the path)
--   /path_save <name> — save the last recorded path to a JSON file
--   /path_load <name> — load a saved path by name (stored in PathCreator.loaded)
--   /path_help        — show this command reference in-game
--
-- How it works:
--   Each time your MUD sends a GMCP Room.Info update, the current room ID
--   is appended to the list.  Consecutive duplicates are silently skipped.
--   While paused, no rooms are recorded, so you can walk back to a
--   crossroads and resume without getting duplicates in the list.
--   Every recorded room is highlighted on the Mudlet mapper in orange so
--   you can see at a glance which rooms are already part of the path.
--
-- Installation:
--   Paste this whole file into a new Script inside Mudlet's Script editor
--   (or use the Package Manager).  It creates three permanent aliases
--   automatically.  Run it once — aliases persist across sessions.
--
-- GMCP event name:
--   Most MUDs send "gmcp.Room.Info" — change PathCreator.config.gmcp_event
--   below if your MUD uses a different event (e.g. "gmcp.room.info").
--------------------------------------------------------------------------------

PathCreator = PathCreator or {}

PathCreator.VERSION = "1.0.0"

-- ── Configuration ─────────────────────────────────────────────────────────────
PathCreator.config = {
    gmcp_event  = "gmcp.Room.Info",  -- GMCP event that fires on room entry
    hi_r        = 255,               -- highlight colour (orange)
    hi_g        = 165,
    hi_b        = 0,
    hi_alpha    = 210,               -- 0-255
}

-- ── State ─────────────────────────────────────────────────────────────────────
PathCreator.active    = false
PathCreator.paused    = false
PathCreator.path      = {}   -- ordered list of room IDs (current recording)
PathCreator.lastPath  = {}   -- copy kept after /path_stop so /path_save still works
PathCreator.visited   = {}   -- set  { [mudID] = mudletIntID } for highlight bookkeeping
PathCreator.handlerID = nil  -- event-handler handle
PathCreator.loaded    = nil  -- most recently loaded path { name=, rooms={} }

-- ── Save directory ───────────────────────────────────────────────────────────
-- Paths are stored as plain JSON files under getMudletHomeDir()/paths/
function PathCreator.saveDir()
    return getMudletHomeDir() .. "/paths/"
end

-- ── Core: record the room we are currently standing in ────────────────────────
function PathCreator.onRoomChange()
    if not PathCreator.active or PathCreator.paused then return end

    -- Use the MUD's own string ID from GMCP
    local mudID = gmcp and gmcp.Room and gmcp.Room.Info and gmcp.Room.Info.id
    if not mudID or mudID == "" then return end

    -- Skip consecutive duplicate (same room fired twice, or entry on start)
    if PathCreator.path[#PathCreator.path] == mudID then return end

    table.insert(PathCreator.path, mudID)

    -- Highlight on map using Mudlet's internal integer room ID (once per unique room)
    if not PathCreator.visited[mudID] then
        PathCreator.visited[mudID] = true
        local mapID = getPlayerRoom()   -- Mudlet internal integer, needed for highlightRoom()
        if mapID then
            local c = PathCreator.config
            highlightRoom(mapID, c.hi_r, c.hi_g, c.hi_b,
                                 c.hi_r, c.hi_g, c.hi_b, 1, c.hi_alpha)
            PathCreator.visited[mudID] = mapID  -- store mapID so we can unhighlight later
            updateMap()
        end
    end

    cecho(string.format(
        "<yellow>[Path] +<cyan>%s<yellow>  (step <green>#%d<yellow>)<reset>\n",
        mudID, #PathCreator.path))
end

-- ── /path_start ──────────────────────────────────────────────────────────────
function PathCreator.start()
    if PathCreator.active then
        cecho("<yellow>[Path] Already recording — use <white>/path_stop<yellow> first.<reset>\n")
        return
    end

    PathCreator.active  = true
    PathCreator.paused  = false
    PathCreator.path    = {}
    PathCreator.visited = {}

    -- (Re-)register GMCP handler
    if PathCreator.handlerID then
        killAnonymousEventHandler(PathCreator.handlerID)
    end
    PathCreator.handlerID = registerAnonymousEventHandler(
        PathCreator.config.gmcp_event, "PathCreator.onRoomChange")

    cecho("<green>[Path] Recording started.<reset>\n")

    -- Capture the room we are already standing in
    PathCreator.onRoomChange()
end

-- ── /path_stop ───────────────────────────────────────────────────────────────
function PathCreator.stop()
    if not PathCreator.active then
        cecho("<yellow>[Path] No active recording.<reset>\n")
        return
    end

    -- Tear down event handler
    if PathCreator.handlerID then
        killAnonymousEventHandler(PathCreator.handlerID)
        PathCreator.handlerID = nil
    end

    PathCreator.active = false
    PathCreator.paused = false

    -- Remove all highlights we added (visited values are Mudlet integer mapIDs)
    for _, mapID in pairs(PathCreator.visited) do
        if type(mapID) == "number" then
            unHighlightRoom(mapID)
        end
    end
    updateMap()

    -- Report
    local n = #PathCreator.path
    cecho(string.format(
        "<green>[Path] Stopped — <white>%d<green> room(s) recorded.<reset>\n", n))

    if n > 0 then
        cecho("<cyan>[Path] IDs: <white>" .. table.concat(PathCreator.path, ", ") .. "<reset>\n")
    end

    -- Keep a copy so /path_save can still be called after stopping
    PathCreator.lastPath = PathCreator.path
    PathCreator.path    = {}
    PathCreator.visited = {}
end

-- ── /path_save <name> ───────────────────────────────────────────────────────
function PathCreator.save(name)
    if not name or name == "" then
        cecho("<yellow>[Path] Usage: <white>/path_save <name><reset>\n")
        return
    end

    -- Allow saving from an active recording OR after /path_stop
    local rooms = PathCreator.active and PathCreator.path or PathCreator.lastPath
    if #rooms == 0 then
        cecho("<yellow>[Path] Nothing to save — record a path first.<reset>\n")
        return
    end

    -- Build JSON manually (no external deps needed for a simple array)
    local parts = {}
    for _, id in ipairs(rooms) do
        parts[#parts + 1] = string.format('%q', id)
    end
    local json = '{"name":' .. string.format('%q', name) ..
                 ',"rooms":[' .. table.concat(parts, ",") .. "]}\n"

    local dir  = PathCreator.saveDir()
    local path = dir .. name .. ".json"

    -- Create directory if needed
    if not io.exists(dir) then
        lfs.mkdir(dir)
    end

    local f, err = io.open(path, "w")
    if not f then
        cecho(string.format("<red>[Path] Could not write file: %s<reset>\n", err))
        return
    end
    f:write(json)
    f:close()

    cecho(string.format(
        "<green>[Path] Saved <white>%d<green> rooms as '<white>%s<green>' → %s<reset>\n",
        #rooms, name, path))
end

-- ── /path_load <name> ────────────────────────────────────────────────────────
function PathCreator.load(name)
    if not name or name == "" then
        cecho("<yellow>[Path] Usage: <white>/path_load <name><reset>\n")
        return
    end

    local path = PathCreator.saveDir() .. name .. ".json"
    local f, err = io.open(path, "r")
    if not f then
        cecho(string.format("<red>[Path] File not found: %s (%s)<reset>\n", path, err))
        return
    end
    local raw = f:read("*a")
    f:close()

    -- Simple JSON parser — expects exactly the format we wrote
    local rooms = {}
    for id in raw:gmatch('"([0-9a-f][0-9a-f]+)"') do
        rooms[#rooms + 1] = id
    end

    if #rooms == 0 then
        cecho(string.format("<red>[Path] Could not parse rooms from %s<reset>\n", path))
        return
    end

    PathCreator.loaded = { name = name, rooms = rooms }

    cecho(string.format(
        "<green>[Path] Loaded '<white>%s<green>' — <white>%d<green> rooms.\n" ..
        "<cyan>[Path] Available as <white>PathCreator.loaded.rooms<cyan>.<reset>\n",
        name, #rooms))
end

-- ── /path_help ──────────────────────────────────────────────────────────────
function PathCreator.help()
    cecho(
        "<white>\n" ..
        "<yellow>╔══════════════════════════════════════════════╗<reset>\n" ..
        "<yellow>║          <white>PathCreator  —  Commands<yellow>           ║<reset>\n" ..
        "<yellow>╠══════════════════════════════════════════════╣<reset>\n" ..
        "<yellow>║ <white>/path_start          <cyan>Begin new recording      <yellow>║<reset>\n" ..
        "<yellow>║ <white>/path_stop           <cyan>Stop & print IDs         <yellow>║<reset>\n" ..
        "<yellow>║ <white>/path_pause          <cyan>Toggle pause/resume      <yellow>║<reset>\n" ..
        "<yellow>║ <white>/path_save <name>    <cyan>Save path to file        <yellow>║<reset>\n" ..
        "<yellow>║ <white>/path_load <name>    <cyan>Load path from file      <yellow>║<reset>\n" ..
        "<yellow>║ <white>/path_help           <cyan>Show this help           <yellow>║<reset>\n" ..
        "<yellow>╚══════════════════════════════════════════════╝<reset>\n" ..
        "<cyan>Saved files: <white>" .. PathCreator.saveDir() .. "<reset>\n"
    )
end

-- ── /path_pause ──────────────────────────────────────────────────────────────
function PathCreator.pause()
    if not PathCreator.active then
        cecho("<yellow>[Path] No active recording.<reset>\n")
        return
    end

    PathCreator.paused = not PathCreator.paused

    if PathCreator.paused then
        cecho("<yellow>[Path] PAUSED — walk back freely. " ..
              "<white>/path_pause<yellow> again to resume.<reset>\n")
    else
        cecho("<green>[Path] RESUMED.<reset>\n")
        -- Record the room we are standing in when we unpause
        PathCreator.onRoomChange()
    end
end

-- ── Alias registration ────────────────────────────────────────────────────────
-- permAlias() stores aliases permanently in the Mudlet profile.
-- Guard with exists() so reloading the script never creates duplicates.
local function safePermAlias(name, pattern, code)
    if exists(name, "alias") > 0 then
        disableAlias(name)   -- disable any stale copy
        enableAlias(name)    -- re-enable (Mudlet deduplicates by name)
    end
    permAlias(name, "", pattern, code)
end

safePermAlias("path_start", [[^/path_start$]],        "PathCreator.start()")
safePermAlias("path_stop",  [[^/path_stop$]],         "PathCreator.stop()")
safePermAlias("path_pause", [[^/path_pause$]],        "PathCreator.pause()")
safePermAlias("path_save",  [[^/path_save%s+(%S+)$]], "PathCreator.save(matches[1])")
safePermAlias("path_load",  [[^/path_load%s+(%S+)$]], "PathCreator.load(matches[1])")
safePermAlias("path_help",  [[^/path_help$]],         "PathCreator.help()")

cecho("<green>[PathCreator] Loaded — type <white>/path_help<green> for commands.<reset>\n")
