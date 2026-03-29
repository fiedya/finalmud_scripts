-- MyScripts Mudlet Auto-Updater
-- Version system
FINALSCRIPTS_VERSION = "1.0.0"
FINALSCRIPTS_REPO_USER = "fiedya" -- replace with your GitHub username
FINALSCRIPTS_REPO_NAME = "finalmud_scripts" -- replace with your GitHub repo name
FINALSCRIPTS_XML_NAME = "FinalInstaller.xml"

local _updateHandler = nil
local _updateInProgress = false

function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function checkScriptsVersion()
  local url = string.format("https://raw.githubusercontent.com/%s/%s/main/version.txt", FINALSCRIPTS_REPO_USER, FINALSCRIPTS_REPO_NAME)
  getHTTP(url, "finalscripts_version_check")
end

function onScriptsVersionCheck(_, url, body)
  if not body or #body == 0 then return end
  local remote = trim(body)
  if remote ~= FINALSCRIPTS_VERSION then
    cecho("<red>Masz nieaktualne skrypty! Wpisz <yellow>/zaktualizuj_skrypty\n")
  end
end

registerAnonymousEventHandler("sysGetHttpDone", function(event, url, body)
  if event == "finalscripts_version_check" then
    onScriptsVersionCheck(event, url, body)
  end
end)

function updateScripts()
  if _updateInProgress then
    cecho("<yellow>Aktualizacja już trwa...\n")
    return
  end
  _updateInProgress = true
  local url = string.format("https://github.com/%s/%s/releases/latest/download/%s", FINALSCRIPTS_REPO_USER, MY_SCRIPTS_REPO_NAME, FINALSCRIPTS_XML_NAME)
  local path = getMudletHomeDir() .. "/" .. FINALSCRIPTS_XML_NAME

  if _updateHandler then killAnonymousEventHandler(_updateHandler) end
  _updateHandler = registerAnonymousEventHandler("sysDownloadDone", function(_, fname, success)
    if fname == path then
      if success then
        installPackage(path)
        cecho("<green>Skrypty zaktualizowane! Zrestartuj Mudleta.\n")
      else
        cecho("<red>Błąd pobierania aktualizacji skryptów!\n")
      end
      _updateInProgress = false
      killAnonymousEventHandler(_updateHandler)
      _updateHandler = nil
    end
  end)
  downloadFile(path, url)
  cecho("<cyan>Pobieranie najnowszych skryptów...\n")
end

-- Register update alias
if not scripts_update_alias then
  scripts_update_alias = tempAlias("^/zaktualizuj_skrypty$", function() updateScripts() end)
end

-- Run version check on load
checkScriptsVersion()
