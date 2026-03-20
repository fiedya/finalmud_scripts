-- config.example.lua
-- Template for GitHub auto-update credentials.
--
-- HOW TO USE:
--   1. Copy this file to config.lua  (it is gitignored — never commit it)
--   2. Fill in the four values below
--   3. That's it — Main.lua reads config.lua automatically on startup
--
-- HOW TO CREATE A PERSONAL ACCESS TOKEN (PAT):
--   1. Go to https://github.com/settings/tokens
--   2. Click "Generate new token (classic)"
--   3. Give it a name (e.g. "mudlet-scripts")
--   4. Tick only the "repo" scope (full control of private repos)
--   5. Click "Generate token" — copy it immediately, GitHub shows it only once
--   6. Paste it below as the token value

return {
    username = "your-github-username",   -- your GitHub login name
    owner    = "your-github-username",   -- repo owner (same as username if it's yours)
    repo     = "finalmud_scripts",       -- repository name
    branch   = "main",                   -- branch to pull from
    token    = "ghp_YourPersonalAccessTokenHere",
}
