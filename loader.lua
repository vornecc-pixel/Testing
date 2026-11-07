-- ══════════════════════════════════════════════════════════════════════════
--  ESP SUITE — loader (v2, self-diagnosing)
--
--  Paste this whole file into your executor and execute.
--
--  Why v2: a bare `loadstring(game:HttpGet(url))()` fails silently when the
--  download comes back empty, producing `[string ""]:1: attempt to call a nil
--  value` with no clue what went wrong. This version checks every step and
--  tells you exactly which one broke.
-- ══════════════════════════════════════════════════════════════════════════

local REPO    = "vornecc-pixel/Testing"
local PIN     = "e834f10ad75ce60393a5bbe69cf62f5a180f4bfb"
local BRANCH  = "arena/bc2a72bc-testing"
local MARKER  = "ESP SUITE"      -- present near the top of ESP.lua

-- every URL form worth trying, in order of preference
local SOURCES = {
	{ tag = "pinned commit",  url = ("https://raw.githubusercontent.com/%s/%s/ESP.lua"):format(REPO, PIN) },
	{ tag = "branch head",    url = ("https://raw.githubusercontent.com/%s/%s/ESP.lua"):format(REPO, BRANCH) },
	{ tag = "cdn (jsdelivr)", url = ("https://cdn.jsdelivr.net/gh/%s@%s/ESP.lua"):format(REPO, PIN) },
}

local function say(...)
	print("[ESP loader]", ...)
end

local function complain(msg)
	warn("[ESP loader] " .. msg)
end

-- ── 1. what HTTP tooling does this executor actually have? ────────────────
local httpMode
if type(request) == "function" then
	httpMode = "request"
elseif type(httpget) == "function" then
	httpMode = "httpget"
elseif type(game) == "table" or type(game) == "userdata" then
	httpMode = "game:HttpGet"
else
	complain("this executor exposes no HTTP function (request / httpget / game:HttpGet).")
	complain("Paste ESP.lua directly instead of loading it from a URL.")
	return
end
say("http backend:", httpMode)

if type(game) == "table" or type(game) == "userdata" then
	local ok, enabled = pcall(function() return game.HttpEnabled end)
	-- HttpEnabled is only readable server-side; a failure here is normal
	if ok and enabled == false then
		complain("this game has HTTP requests disabled — a URL loader cannot work here.")
		complain("Paste ESP.lua directly.")
		return
	end
end

-- ── 2. fetch, reporting status instead of swallowing it ──────────────────
local function fetch(url)
	local body, status

	if httpMode == "request" then
		local ok, res = pcall(request, {
			Url = url,
			Method = "GET",
			Headers = { ["User-Agent"] = "Roblox" },
		})
		if ok and type(res) == "table" then
			status = res.StatusCode
			body = res.Body
		elseif ok and type(res) == "string" then
			body = res
		end
	elseif httpMode == "httpget" then
		local ok, res = pcall(httpget, url)
		if ok then body = res end
	else
		local ok, res = pcall(function() return game:HttpGet(url) end)
		if ok then body = res end
	end

	if status and status ~= 200 then
		return nil, status, ("server said HTTP %s"):format(tostring(status))
	end
	if type(body) ~= "string" then return nil, status, "no body returned" end
	if #body == 0 then return nil, status, "empty response (#body == 0)" end
	return body, status
end

-- ── 3. try each source ───────────────────────────────────────────────────
local source, usedTag
local attempts = {}

for _, src in ipairs(SOURCES) do
	local body, status, why = fetch(src.url)
	if body and body:find(MARKER, 1, true) then
		source, usedTag = body, src.tag
		break
	elseif body then
		-- we got something, it just isn't ESP.lua
		attempts[#attempts + 1] = ("%s: %d bytes but no '%s' marker"):format(src.tag, #body, MARKER)
	else
		attempts[#attempts + 1] = ("%s: %s"):format(src.tag, why or "failed")
	end
end

if not source then
	complain("could not download ESP.lua. what each source did:")
	for _, line in ipairs(attempts) do
		warn("    • " .. line)
	end
	complain("")
	complain("most likely causes:")
	complain("  1. raw.githubusercontent.com is blocked by your executor or network")
	complain("  2. the repo was made private / the branch was deleted")
	complain("  3. the game has HTTP requests disabled")
	complain("")
	complain("fix: open the raw URL in a browser, copy ESP.lua, and paste it directly.")
	return
end

say(("downloaded %d bytes from %s"):format(#source, usedTag))

-- ── 4. compile, then run ─────────────────────────────────────────────────
local compiler = loadstring or load
if type(compiler) ~= "function" then
	complain("this executor has no loadstring/load — cannot run fetched code.")
	complain("Paste ESP.lua directly instead.")
	return
end

local chunk, compileErr = compiler(source, "=ESP.lua")
if not chunk then
	complain("the download was not valid Lua: " .. tostring(compileErr))
	complain("(if you got HTML, the URL resolved to a 404 page)")
	return
end

local ok, runErr = pcall(chunk)
if not ok then
	complain("ESP.lua itself errored: " .. tostring(runErr))
	return
end

say("ready — RightShift toggles the menu")
