--------------------------------------------------------------------------------
-- Main.lua  (finalmud_scripts)
-- Master script loader / reloader with GitHub auto-update support.
--
-- Paste this script into Mudlet as its own Script entry — load it first.
-- It auto-runs all listed modules on startup, checks GitHub for newer
-- versions, downloads any updates, then reloads.
--
-- Commands:
--   /scripts_reload — reload every script in Main.scripts from disk
--   /scripts_update — check GitHub for updates and download if newer
--
-- GitHub setup:
--   1. Copy config.example.lua → config.lua (gitignored — never commit it)
--   2. Fill in your GitHub username, repo name, branch, and PAT token
--   3. Keep versions.lua in the repo root; bump version strings when you
--      push changes — Mudlet will auto-download on next startup
--------------------------------------------------------------------------------

Main = Main or {}

Main = Main or {}
Main.VERSION = "1.0.1"

-- ── Base directory ────────────────────────────────────────────────────────────
Main.baseDir = "C:/Users/alicj/Programowanie/lua/finalmud_scripts/"

-- ── Script list ───────────────────────────────────────────────────────────────
-- Scripts are loaded/updated in the order listed.
Main.scripts = {
    "PathCreator.lua",
    -- "Herbs.lua",
    -- "Combat.lua",
}

-- ── Loader ────────────────────────────────────────────────────────────────────
function Main.reload()
    local ok_count  = 0
    local err_count = 0

    cecho("<yellow>╔══════════════════════════════════════╗<reset>\n")
    cecho("<yellow>║       <white>Scripts Reload<yellow>                 ║<reset>\n")
    cecho("<yellow>╠══════════════════════════════════════╣<reset>\n")

    for _, filename in ipairs(Main.scripts) do
        local filepath = Main.baseDir .. filename
        local f, open_err = io.open(filepath, "r")

        if not f then
            cecho(string.format(
                "<yellow>║ <red>FAIL  <white>%-28s<yellow>║<reset>\n", filename))
            cecho(string.format(
                "<yellow>║      <red>%s<reset>\n", open_err))
            err_count = err_count + 1
        else
            local source = f:read("*a")
            f:close()

            local chunk, compile_err = load(source, "@" .. filename)
            if not chunk then
                cecho(string.format(
                    "<yellow>║ <red>ERR   <white>%-28s<yellow>║<reset>\n", filename))
                cecho(string.format(
                    "<yellow>║      <red>%s<reset>\n", compile_err))
                err_count = err_count + 1
            else
                local run_ok, run_err = pcall(chunk)
                if not run_ok then
                    cecho(string.format(
                        "<yellow>║ <red>CRASH <white>%-28s<yellow>║<reset>\n", filename))
                    cecho(string.format(
                        "<yellow>║      <red>%s<reset>\n", run_err))
                    err_count = err_count + 1
                else
                    cecho(string.format(
                        "<yellow>║ <green>OK    <white>%-28s<yellow>║<reset>\n", filename))
                    ok_count = ok_count + 1
                end
            end
        end
    end

    cecho("<yellow>╠══════════════════════════════════════╣<reset>\n")
    cecho(string.format(
        "<yellow>║ <green>%d loaded  <red>%d error(s)<yellow>%-18s║<reset>\n",
        ok_count, err_count, ""))
    cecho("<yellow>╚══════════════════════════════════════╝<reset>\n")
end

-- ── GitHub auto-update ────────────────────────────────────────────────────────

-- Load config.lua (gitignored file containing GitHub credentials)
function Main.loadConfig()
    if Main.config then return true end  -- already loaded this session

    local path = Main.baseDir .. "config.lua"
    local f = io.open(path, "r")
    if not f then
        cecho("<yellow>[Main] config.lua not found — GitHub auto-update disabled.\n" ..
              "       Copy config.example.lua → config.lua and fill in your token.<reset>\n")
        return false
    end
    local src = f:read("*a")
    f:close()

    local chunk, err = load(src)
    if not chunk then
        cecho("<red>[Main] config.lua syntax error: " .. err .. "<reset>\n")
        return false
    end
    Main.config = chunk()
    return true
end

-- Build a raw GitHub URL (token embedded for private repo access)
function Main.rawURL(filename)
    local c = Main.config
    return string.format(
        "https://%s:%s@raw.githubusercontent.com/%s/%s/%s/%s",
        c.username, c.token, c.owner, c.repo, c.branch, filename)
end

-- Compare two "major.minor.patch" version strings; returns true if a > b
function Main.isNewer(a, b)
    if not b then return true end
    local function parts(v)
        local x, y, z = v:match("(%d+)%.(%d+)%.(%d+)")
        return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    end
    local a1,a2,a3 = parts(a)
    local b1,b2,b3 = parts(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

-- Read the VERSION field of an already-loaded module global (e.g. PathCreator.VERSION)
function Main.localVersion(filename)
    local mod = filename:match("^(.-)%.lua$")
    local tbl = _G[mod]
    return tbl and tbl.VERSION or nil
end

-- Download updates for any scripts that are behind the remote versions.lua
function Main.checkUpdates()
    if not Main.loadConfig() then return end

    local tmpPath = Main.baseDir .. ".tmp_versions"
    local url     = Main.rawURL("versions.lua")

    -- Clean up residual event handlers from a previous interrupted check
    if Main._versionsDoneHandler then
        killAnonymousEventHandler(Main._versionsDoneHandler)
    end
    if Main._versionsErrHandler then
        killAnonymousEventHandler(Main._versionsErrHandler)
    end

    Main._versionsDoneHandler = registerAnonymousEventHandler("sysDownloadDone",
        function(_, path)
            if path ~= tmpPath then return end
            killAnonymousEventHandler(Main._versionsDoneHandler)
            killAnonymousEventHandler(Main._versionsErrHandler)
            Main._versionsDoneHandler = nil
            Main._versionsErrHandler  = nil
            Main._onVersionsDownloaded(tmpPath)
        end)

    Main._versionsErrHandler = registerAnonymousEventHandler("sysDownloadError",
        function(_, path, err)
            if path ~= tmpPath then return end
            killAnonymousEventHandler(Main._versionsDoneHandler)
            killAnonymousEventHandler(Main._versionsErrHandler)
            Main._versionsDoneHandler = nil
            Main._versionsErrHandler  = nil
            cecho("<red>[Main] Update check failed: " .. (err or "unknown") .. "<reset>\n")
        end)

    downloadFile(tmpPath, url)
    cecho("<cyan>[Main] Checking for updates...<reset>\n")
end

function Main._onVersionsDownloaded(tmpPath)
    local f = io.open(tmpPath, "r")
    if not f then
        cecho("<red>[Main] Could not read downloaded versions file.<reset>\n")
        return
    end
    local src = f:read("*a")
    f:close()
    os.remove(tmpPath)

    local chunk, err = load(src)
    if not chunk then
        cecho("<red>[Main] versions.lua parse error: " .. err .. "<reset>\n")
        return
    end
    local remote = chunk()  -- { ["PathCreator.lua"] = "1.0.1", ... }

    -- Collect outdated scripts
    local toUpdate = {}
    for _, filename in ipairs(Main.scripts) do
        local remoteVer = remote[filename]
        local localVer  = Main.localVersion(filename)
        if remoteVer and Main.isNewer(remoteVer, localVer) then
            table.insert(toUpdate, { file = filename, ver = remoteVer })
            cecho(string.format(
                "<yellow>[Main] Update: <white>%s<yellow>  %s → %s<reset>\n",
                filename, localVer or "none", remoteVer))
        end
    end

    if #toUpdate == 0 then
        cecho("<green>[Main] All scripts up to date.<reset>\n")
        return
    end

    -- Download each outdated file; reload all scripts once every download finishes
    Main._pending = #toUpdate
    for _, info in ipairs(toUpdate) do
        local dest = Main.baseDir .. info.file
        local dlURL = Main.rawURL(info.file)
        local h, he
        h = registerAnonymousEventHandler("sysDownloadDone",
            function(_, path)
                if path ~= dest then return end
                killAnonymousEventHandler(h)
                killAnonymousEventHandler(he)
                cecho(string.format("<green>[Main] Downloaded: <white>%s<reset>\n", info.file))
                Main._pending = Main._pending - 1
                if Main._pending == 0 then
                    cecho("<green>[Main] All updates downloaded — reloading.<reset>\n")
                    Main.reload()
                end
            end)
        he = registerAnonymousEventHandler("sysDownloadError",
            function(_, path, err)
                if path ~= dest then return end
                killAnonymousEventHandler(h)
                killAnonymousEventHandler(he)
                cecho(string.format(
                    "<red>[Main] Download failed for %s: %s<reset>\n", info.file, err or "?"))
                Main._pending = Main._pending - 1
                if Main._pending == 0 then
                    Main.reload()
                end
            end)
        downloadFile(dest, dlURL)
    end
end

-- ── Aliases ───────────────────────────────────────────────────────────────────
local function safePermAlias(name, pattern, code)
    if exists(name, "alias") > 0 then
        disableAlias(name)
        enableAlias(name)
    end
    permAlias(name, "", pattern, code)
end

safePermAlias("scripts_reload", [[^/scripts_reload$]], "Main.reload()")
safePermAlias("scripts_update", [[^/scripts_update$]], "Main.checkUpdates()")

cecho("<green>[Main] Loaded — <white>/scripts_reload<green>  <white>/scripts_update<reset>\n")

-- On startup: load scripts, then check GitHub for updates
Main.reload()
Main.checkUpdates()
