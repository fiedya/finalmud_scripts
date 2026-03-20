--------------------------------------------------------------------------------
-- Main.lua
-- Master script loader / reloader for FinalMUD.
--
-- Paste this script into Mudlet FIRST (before any module scripts).
-- It defines /scripts_reload which re-executes every listed script file
-- from disk so you can live-edit without restarting Mudlet.
--
-- Commands:
--   /scripts_reload — reload all scripts listed in Main.scripts
--------------------------------------------------------------------------------

Main = Main or {}

-- ── Script list ───────────────────────────────────────────────────────────────
-- Add every module file here.  Paths are relative to Main.baseDir.
-- Point baseDir at wherever you keep these .lua files on disk.
Main.baseDir = getMudletHomeDir() .. "/scripts/"

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
                "<yellow>║      <red>%s\n<reset>", open_err))
            err_count = err_count + 1
        else
            local source = f:read("*a")
            f:close()

            local chunk, compile_err = load(source, "@" .. filename)
            if not chunk then
                cecho(string.format(
                    "<yellow>║ <red>ERR   <white>%-28s<yellow>║<reset>\n", filename))
                cecho(string.format(
                    "<yellow>║      <red>%s\n<reset>", compile_err))
                err_count = err_count + 1
            else
                local run_ok, run_err = pcall(chunk)
                if not run_ok then
                    cecho(string.format(
                        "<yellow>║ <red>CRASH <white>%-28s<yellow>║<reset>\n", filename))
                    cecho(string.format(
                        "<yellow>║      <red>%s\n<reset>", run_err))
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

-- ── Alias ─────────────────────────────────────────────────────────────────────
local function safePermAlias(name, pattern, code)
    if exists(name, "alias") > 0 then
        disableAlias(name)
        enableAlias(name)
    end
    permAlias(name, "", pattern, code)
end

safePermAlias("scripts_reload", [[^/scripts_reload$]], "Main.reload()")

cecho("<green>[Main] Loaded — type <white>/scripts_reload<green> to reload all scripts.<reset>\n")

-- Auto-run on load so scripts initialise immediately when Mudlet starts
Main.reload()
