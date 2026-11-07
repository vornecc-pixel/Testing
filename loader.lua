-- ══════════════════════════════════════════════════════════════════════════
--  ESP SUITE — loader
--  Paste this one-liner into your executor. It fetches ESP.lua from GitHub
--  and runs it. Re-running it replaces the previous instance cleanly
--  (ESP.lua unloads whatever is already loaded before it starts).
-- ══════════════════════════════════════════════════════════════════════════

local SOURCES = {
	-- pinned to the commit that was tested — stable, never surprises you
	"https://raw.githubusercontent.com/vornecc-pixel/Testing/e834f10ad75ce60393a5bbe69cf62f5a180f4bfb/ESP.lua",
	-- branch head — picks up newer commits automatically (fallback + "latest")
	"https://raw.githubusercontent.com/vornecc-pixel/Testing/arena/bc2a72bc-testing/ESP.lua",
}

local MARKER = "ESP SUITE"      -- sanity check: make sure we got Lua, not a 404 page

local function fetch(url)
	if not (game and game.HttpGet) and not httpget then return nil end
	local ok, body = pcall(function()
		if httpget then return httpget(url) end
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" then return body end
	return nil
end

local source, usedURL
for _, url in ipairs(SOURCES) do
	local body = fetch(url)
	if body and body:find(MARKER, 1, true) then
		source, usedURL = body, url
		break
	end
end

if not source then
	warn("[ESP loader] could not fetch ESP.lua — check your connection, or that " ..
		"the repo is still public at github.com/vornecc-pixel/Testing")
	return
end

local chunk, err = (loadstring or load)(source, "=ESP.lua")
if not chunk then
	warn("[ESP loader] download was not valid Lua: " .. tostring(err))
	return
end

local ok, runErr = pcall(chunk)
if not ok then
	warn("[ESP loader] ESP.lua errored: " .. tostring(runErr))
	return
end

print("[ESP loader] loaded from " .. (usedURL:match("/([^/]+)/ESP%.lua$") or usedURL))
