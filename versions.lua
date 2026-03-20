-- versions.lua
-- Remote script manifest for installer.lua.
--
-- Format:
-- return {
--   scripts = {
--     ["relative/path/to/file.lua"] = "major.minor.patch",
--   }
-- }

return {
    scripts = {
        ["Main.lua"] = "1.0.1",
        ["path_creator/Main.lua"] = "1.0.0",
        ["path_creator/PathCreator.lua"] = "1.0.0",
    }
}
