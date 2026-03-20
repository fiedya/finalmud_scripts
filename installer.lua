-- installer.lua
-- Bootstrap installer + updater for Mudlet scripts.
--
-- Usage:
--   1) Paste this file as a script in Mudlet and run it once.
--   2) It will install all files listed in remote versions.lua.
--   3) Use /scripts_update any time to fetch only newer files.

ScriptsInstaller = ScriptsInstaller or {}

-- Central config: change GitHub details here only.
ScriptsInstaller.config = {
    github_user = "fiedya",
    repo = "finalmud_scripts",
    branch = "main",
    scripts_subdir = "scripts", -- under getMudletHomeDir()
    retries = 2,
    auto_update_on_load = false,
}

function ScriptsInstaller.log(msg, color)
    echo(string.format("[Installer] %s\n", msg))
end

function ScriptsInstaller.joinPath(a, b)
    if not a or a == "" then return b end
    if not b or b == "" then return a end
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

function ScriptsInstaller.scriptBaseDir()
    return ScriptsInstaller.joinPath(getMudletHomeDir(), ScriptsInstaller.config.scripts_subdir)
end

function ScriptsInstaller.rawUrl(path)
    local c = ScriptsInstaller.config
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        c.github_user,
        c.repo,
        c.branch,
        path
    )
end

function ScriptsInstaller.normalizePath(path)
    local p = (path or ""):gsub("\\", "/")
    p = p:gsub("//+", "/")
    return p
end

function ScriptsInstaller.ensureDir(path)
    if not path or path == "" then return true end
    if not lfs then
        ScriptsInstaller.log("lfs is unavailable; cannot create directories.", "red")
        return false
    end

    local normalized = ScriptsInstaller.normalizePath(path)
    local root = ""
    local startAt = 1

    if normalized:match("^%a:/") then
        root = normalized:sub(1, 3) -- C:/
        startAt = 4
    elseif normalized:sub(1, 1) == "/" then
        root = "/"
        startAt = 2
    end

    local rest = normalized:sub(startAt)
    local current = root
    for part in rest:gmatch("[^/]+") do
        if current == "" or current:sub(-1) == "/" then
            current = current .. part
        else
            current = current .. "/" .. part
        end
        lfs.mkdir(current)
    end

    return true
end

function ScriptsInstaller.ensureParentDir(filePath)
    local normalized = ScriptsInstaller.normalizePath(filePath)
    local parent = normalized:match("^(.*)/[^/]+$")
    if not parent then return true end
    return ScriptsInstaller.ensureDir(parent)
end

function ScriptsInstaller.readFile(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local data = f:read("*a")
    f:close()
    return data
end

function ScriptsInstaller.writeFile(path, data)
    local ok = ScriptsInstaller.ensureParentDir(path)
    if not ok then
        return false, "failed to create parent directory"
    end

    local f, err = io.open(path, "w")
    if not f then return false, err end
    local wOk, wErr = f:write(data)
    f:close()
    if not wOk then return false, wErr or "write failed" end
    return true
end

function ScriptsInstaller.versionParts(v)
    local parts = {}
    for n in tostring(v or "0"):gmatch("%d+") do
        parts[#parts + 1] = tonumber(n) or 0
    end
    return parts
end

-- Returns 1 if a>b, -1 if a<b, 0 if equal.
function ScriptsInstaller.compareSemver(a, b)
    local ap = ScriptsInstaller.versionParts(a)
    local bp = ScriptsInstaller.versionParts(b)
    local maxLen = math.max(#ap, #bp)

    for i = 1, maxLen do
        local av = ap[i] or 0
        local bv = bp[i] or 0
        if av > bv then return 1 end
        if av < bv then return -1 end
    end
    return 0
end

function ScriptsInstaller.extractScriptsTable(manifest)
    if type(manifest) ~= "table" then
        return nil, "manifest is not a table"
    end

    if type(manifest.scripts) == "table" then
        return manifest.scripts
    end

    -- Backward compatible format: return { ["file.lua"] = "1.2.3", ... }
    local out = {}
    for k, v in pairs(manifest) do
        if type(k) == "string" and type(v) == "string" then
            out[k] = v
        end
    end

    if next(out) == nil then
        return nil, "manifest has no scripts"
    end
    return out
end

function ScriptsInstaller.parseVersionsSource(source)
    if not source or source == "" then
        return nil, "empty versions source"
    end

    local chunk, err = load(source, "@versions.lua")
    if not chunk then return nil, err end

    local ok, result = pcall(chunk)
    if not ok then return nil, result end

    return ScriptsInstaller.extractScriptsTable(result)
end

function ScriptsInstaller.parseVersionsFile(path)
    local src, err = ScriptsInstaller.readFile(path)
    if not src then return nil, err end
    return ScriptsInstaller.parseVersionsSource(src)
end

function ScriptsInstaller.getLocalVersions(remoteScripts)
    local versionsPath = ScriptsInstaller.joinPath(ScriptsInstaller.scriptBaseDir(), "versions.lua")
    local localVersions = {}

    local parsed = ScriptsInstaller.parseVersionsFile(versionsPath)
    if type(parsed) == "table" then
        localVersions = parsed
    end

    -- Fallback: if local versions.lua is missing or incomplete, parse VERSION from files.
    for scriptPath, _ in pairs(remoteScripts) do
        if not localVersions[scriptPath] then
            local fullPath = ScriptsInstaller.joinPath(ScriptsInstaller.scriptBaseDir(), scriptPath)
            local src = ScriptsInstaller.readFile(fullPath)
            if src then
                local v = src:match("VERSION%s*=%s*[\"']([^\"']+)[\"']")
                if v then
                    localVersions[scriptPath] = v
                end
            end
        end
    end

    return localVersions
end

function ScriptsInstaller.downloadToFile(url, destPath, callback, attempt)
    local currentAttempt = attempt or 1
    local maxAttempts = (ScriptsInstaller.config.retries or 0) + 1
    local doneHandler
    local errHandler

    local function cleanup()
        if doneHandler then killAnonymousEventHandler(doneHandler) end
        if errHandler then killAnonymousEventHandler(errHandler) end
        doneHandler = nil
        errHandler = nil
    end

    local function retryOrFail(reason)
        cleanup()
        if currentAttempt < maxAttempts then
            ScriptsInstaller.log(string.format(
                "Retry %d/%d for %s (%s)",
                currentAttempt,
                maxAttempts - 1,
                destPath,
                reason or "unknown"
            ), "yellow")
            return ScriptsInstaller.downloadToFile(url, destPath, callback, currentAttempt + 1)
        end
        callback(false, reason or "download failed")
    end

    if not ScriptsInstaller.ensureParentDir(destPath) then
        callback(false, "unable to create destination directory")
        return
    end

    local normalizedDest = ScriptsInstaller.normalizePath(destPath)

    doneHandler = registerAnonymousEventHandler("sysDownloadDone", function(_, path)
        if ScriptsInstaller.normalizePath(path) ~= normalizedDest then return end
        cleanup()

        local data, readErr = ScriptsInstaller.readFile(destPath)
        if not data then
            callback(false, "downloaded but unreadable: " .. tostring(readErr))
            return
        end
        if data == "" then
            retryOrFail("empty response")
            return
        end
        callback(true, nil, data)
    end)

    errHandler = registerAnonymousEventHandler("sysDownloadError", function(_, path, err)
        if ScriptsInstaller.normalizePath(path) ~= normalizedDest then return end
        retryOrFail(err or "HTTP error")
    end)

    local ok, callErr = pcall(downloadFile, destPath, url)
    if not ok then
        retryOrFail(callErr or "downloadFile call failed")
    end
end

function ScriptsInstaller.reloadScript(relativePath)
    local fullPath = ScriptsInstaller.joinPath(ScriptsInstaller.scriptBaseDir(), relativePath)
    local src, err = ScriptsInstaller.readFile(fullPath)
    if not src then
        return false, "read failed: " .. tostring(err)
    end

    local loader = loadstring or load
    local chunk, compileErr = loader(src, "@" .. relativePath)
    if not chunk then
        return false, "compile failed: " .. tostring(compileErr)
    end

    local ok, runErr = pcall(chunk)
    if not ok then
        return false, "runtime failed: " .. tostring(runErr)
    end

    return true
end

function ScriptsInstaller.downloadMany(fileList, onFinished)
    local results = {
        ok = {},
        failed = {},
    }

    local idx = 1
    local function nextOne()
        local rel = fileList[idx]
        if not rel then
            onFinished(results)
            return
        end

        local url = ScriptsInstaller.rawUrl(rel)
        local dest = ScriptsInstaller.joinPath(ScriptsInstaller.scriptBaseDir(), rel)

        ScriptsInstaller.log("Downloading " .. rel .. " ...", "cyan")
        ScriptsInstaller.downloadToFile(url, dest, function(success, err)
            if success then
                ScriptsInstaller.log("Downloaded " .. rel, "green")
                table.insert(results.ok, rel)
            else
                ScriptsInstaller.log("Failed " .. rel .. ": " .. tostring(err), "red")
                table.insert(results.failed, { file = rel, err = err })
            end
            idx = idx + 1
            nextOne()
        end)
    end

    nextOne()
end

function ScriptsInstaller.fetchRemoteManifest(callback)
    local versionsUrl = ScriptsInstaller.rawUrl("versions.lua")
    local localVersionsPath = ScriptsInstaller.joinPath(ScriptsInstaller.scriptBaseDir(), "versions.lua")

    ScriptsInstaller.log("Fetching remote versions.lua ...", "cyan")
    ScriptsInstaller.downloadToFile(versionsUrl, localVersionsPath, function(success, err, source)
        if not success then
            callback(nil, "versions.lua download failed: " .. tostring(err))
            return
        end

        local scripts, parseErr = ScriptsInstaller.parseVersionsSource(source)
        if not scripts then
            callback(nil, "versions.lua parse failed: " .. tostring(parseErr))
            return
        end
        callback(scripts, nil)
    end)
end

function ScriptsInstaller.installAll()
    ScriptsInstaller.log("Starting bootstrap install...", "yellow")
    ScriptsInstaller.ensureDir(ScriptsInstaller.scriptBaseDir())

    ScriptsInstaller.fetchRemoteManifest(function(remoteScripts, err)
        if not remoteScripts then
            ScriptsInstaller.log(err or "unknown error", "red")
            return
        end

        local files = {}
        for path, _ in pairs(remoteScripts) do
            if path ~= "versions.lua" then
                files[#files + 1] = path
            end
        end
        table.sort(files)

        if #files == 0 then
            ScriptsInstaller.log("No scripts listed in manifest.", "red")
            return
        end

        ScriptsInstaller.downloadMany(files, function(result)
            ScriptsInstaller.log(string.format(
                "Bootstrap finished: %d success, %d failed",
                #result.ok,
                #result.failed
            ), (#result.failed == 0) and "green" or "yellow")

            for _, rel in ipairs(result.ok) do
                local ok, rErr = ScriptsInstaller.reloadScript(rel)
                if ok then
                    ScriptsInstaller.log("Reloaded " .. rel, "green")
                else
                    ScriptsInstaller.log("Reload skipped for " .. rel .. ": " .. tostring(rErr), "yellow")
                end
            end
        end)
    end)
end

function ScriptsInstaller.update()
    ScriptsInstaller.log("Checking for script updates...", "yellow")
    ScriptsInstaller.ensureDir(ScriptsInstaller.scriptBaseDir())

    ScriptsInstaller.fetchRemoteManifest(function(remoteScripts, err)
        if not remoteScripts then
            ScriptsInstaller.log(err or "unknown error", "red")
            return
        end

        local localVersions = ScriptsInstaller.getLocalVersions(remoteScripts)
        local toUpdate = {}
        local skipped = {}

        for rel, remoteVersion in pairs(remoteScripts) do
            if rel ~= "versions.lua" then
                local localVersion = localVersions[rel]
                local cmp = ScriptsInstaller.compareSemver(remoteVersion, localVersion)
                if cmp > 0 then
                    toUpdate[#toUpdate + 1] = rel
                else
                    skipped[#skipped + 1] = string.format(
                        "%s (local %s, remote %s)",
                        rel,
                        tostring(localVersion or "none"),
                        tostring(remoteVersion)
                    )
                end
            end
        end

        table.sort(toUpdate)
        table.sort(skipped)

        if #toUpdate == 0 then
            ScriptsInstaller.log("Everything is up to date.", "green")
            for _, line in ipairs(skipped) do
                ScriptsInstaller.log("Skip " .. line, "white")
            end
            return
        end

        ScriptsInstaller.log(string.format("Updating %d script(s)...", #toUpdate), "cyan")
        ScriptsInstaller.downloadMany(toUpdate, function(result)
            for _, line in ipairs(skipped) do
                ScriptsInstaller.log("Skip " .. line, "white")
            end

            for _, rel in ipairs(result.ok) do
                local ok, rErr = ScriptsInstaller.reloadScript(rel)
                if ok then
                    ScriptsInstaller.log("Reloaded " .. rel, "green")
                else
                    ScriptsInstaller.log("Reload failed for " .. rel .. ": " .. tostring(rErr), "red")
                end
            end

            ScriptsInstaller.log(string.format(
                "Update complete: %d updated, %d failed, %d skipped",
                #result.ok,
                #result.failed,
                #skipped
            ), (#result.failed == 0) and "green" or "yellow")
        end)
    end)
end

-- Public function requested by user.
function scripts_update()
    ScriptsInstaller.update()
end

function ScriptsInstaller.showVersions()
    ScriptsInstaller.log("Checking versions...", "cyan")
    ScriptsInstaller.ensureDir(ScriptsInstaller.scriptBaseDir())

    ScriptsInstaller.fetchRemoteManifest(function(remoteScripts, err)
        if not remoteScripts then
            ScriptsInstaller.log(err or "unknown error", "red")
            return
        end

        local localVersions = ScriptsInstaller.getLocalVersions(remoteScripts)
        
        echo("\n")
        echo("=" .. string.rep("=", 73) .. "\n")
        echo(string.format("%-40s %12s %12s\n", "Script", "Local", "Remote"))
        echo("=" .. string.rep("=", 73) .. "\n")

        local scripts = {}
        for path, _ in pairs(remoteScripts) do
            if path ~= "versions.lua" then
                table.insert(scripts, path)
            end
        end
        table.sort(scripts)

        for _, path in ipairs(scripts) do
            local localVer = localVersions[path] or "---"
            local remoteVer = remoteScripts[path] or "---"
            local status = " "
            
            if localVer ~= "---" and remoteVer ~= "---" then
                local cmp = ScriptsInstaller.compareSemver(remoteVer, localVer)
                if cmp > 0 then
                    status = "↑"  -- update available
                elseif cmp < 0 then
                    status = "!"  -- local ahead of remote (unusual)
                else
                    status = "✓"  -- up to date
                end
            end
            
            echo(string.format("%s %-38s %12s %12s\n", status, path, localVer, remoteVer))
        end

        echo("=" .. string.rep("=", 73) .. "\n")
        echo("Legend:  ✓ = up to date  |  ↑ = update available  |  ! = local ahead\n\n")
    end)
end

function scripts_version()
    ScriptsInstaller.showVersions()
end

function ScriptsInstaller.reloadAll()
    ScriptsInstaller.log("Reloading all scripts...", "yellow")
    ScriptsInstaller.ensureDir(ScriptsInstaller.scriptBaseDir())

    ScriptsInstaller.fetchRemoteManifest(function(remoteScripts, err)
        if not remoteScripts then
            ScriptsInstaller.log(err or "unknown error", "red")
            return
        end

        local scripts = {}
        for path, _ in pairs(remoteScripts) do
            if path ~= "versions.lua" then
                table.insert(scripts, path)
            end
        end
        table.sort(scripts)

        local ok_count = 0
        local err_count = 0

        for _, rel in ipairs(scripts) do
            local ok, rErr = ScriptsInstaller.reloadScript(rel)
            if ok then
                ScriptsInstaller.log("Reloaded " .. rel, "green")
                ok_count = ok_count + 1
            else
                ScriptsInstaller.log("Reload failed for " .. rel .. ": " .. tostring(rErr), "red")
                err_count = err_count + 1
            end
        end

        ScriptsInstaller.log(string.format(
            "Reload complete: %d loaded, %d error(s)",
            ok_count,
            err_count
        ), (err_count == 0) and "green" or "yellow")
    end)
end

function scripts_reload()
    ScriptsInstaller.reloadAll()
end

local function safePermAlias(name, pattern, code)
    if exists(name, "alias") > 0 then
        disableAlias(name)
        enableAlias(name)
    end
    permAlias(name, "", pattern, code)
end

safePermAlias("scripts_update", [[^/scripts_update$]], "scripts_update()")
safePermAlias("scripts", [[^/scripts$]], "scripts_version()")
safePermAlias("scripts_reload", [[^/scripts_reload$]], "scripts_reload()")

ScriptsInstaller.log("Loaded. Aliases available: /scripts  /scripts_update  /scripts_reload", "green")

if ScriptsInstaller.config.auto_update_on_load then
    scripts_update()
else
    ScriptsInstaller.installAll()
end
