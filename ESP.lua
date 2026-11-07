-- ══════════════════════════════════════════════════════════════════════════
--  ESP SUITE  v2.0   ·   players / npcs / nodes
-- ──────────────────────────────────────────────────────────────────────────
--  • chams            Highlight based, optional through-wall rendering
--  • boxes            corner accents or full frame, colour + opacity + width
--  • skeleton         R15 bones (auto-detects R6), optional health tint
--  • health bar       configurable colour / width / health tint
--  • health text      numeric HP
--  • name             size + colour + health tint
--  • distance         studs or metres
--  • weapon           equipped tool / attribute / part detection
--  • head dot         marker on the head bone
--  • tracer           line from screen edge to the target
--  • distance limits  per-category slider (this is the "max distance" cap)
--  • masters          per-category on/off, editable name filters
--
--  Everything is live: every toggle, slider and colour writes straight into
--  the config table that the render loop reads, so changes apply instantly.
--
--  Usage   paste into your executor and execute.
--          RightShift (or the little ESP pill) shows/hides the menu.
--  API     _G.ESP_Suite ... see the bottom of this file
--  Unload  _G.EspUnload()  (legacy alias)  /  _G.ESP_Suite.unload()
-- ══════════════════════════════════════════════════════════════════════════

local VERSION = "2.0"

-- clean up a previous injection so re-executing never stacks menus ----------
if type(_G) == "table" and _G.ESP_Suite and type(_G.ESP_Suite.unload) == "function" then
	pcall(_G.ESP_Suite.unload)
end

-- ══════════════════════════════════════════════════════════════════════════
--  SERVICES
-- ══════════════════════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local CoreGui          = game:GetService("CoreGui")

local waitFn  = (task and task.wait)  or wait
local spawnFn = (task and task.spawn) or spawn
local delayFn = (task and task.delay) or delay

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	for _ = 1, 100 do
		waitFn(0.1)
		LocalPlayer = Players.LocalPlayer
		if LocalPlayer then break end
	end
end
if not LocalPlayer then
	warn("[ESP] no LocalPlayer — run this on the client (executor / LocalScript)")
	return
end

local Camera = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = Workspace.CurrentCamera
end)

-- ══════════════════════════════════════════════════════════════════════════
--  SMALL UTILITIES
-- ══════════════════════════════════════════════════════════════════════════

local floor, ceil, huge = math.floor, math.ceil, math.huge

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function round(v)
	return floor(v + 0.5)
end

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, val in pairs(v) do
		out[k] = deepcopy(val)
	end
	return out
end

local function shallowCopy(v)
	local out = {}
	for k, val in pairs(v) do out[k] = val end
	return out
end

-- { r, g, b } (0-255) -> Color3
local function rgb(t)
	if type(t) ~= "table" then return Color3.fromRGB(255, 255, 255) end
	return Color3.fromRGB(
		clamp(round(tonumber(t[1]) or 255), 0, 255),
		clamp(round(tonumber(t[2]) or 255), 0, 255),
		clamp(round(tonumber(t[3]) or 255), 0, 255)
	)
end

local function alphaOf(v)
	return 1 - clamp(tonumber(v) or 100, 0, 100) / 100
end

local function hexOf(t)
	return string.format("#%02X%02X%02X",
		clamp(round(tonumber(t[1]) or 0), 0, 255),
		clamp(round(tonumber(t[2]) or 0), 0, 255),
		clamp(round(tonumber(t[3]) or 0), 0, 255))
end

local function parseHex(str)
	local s = tostring(str or ""):gsub("%s", "")
	if s:sub(1, 1) == "#" then s = s:sub(2) end
	if #s == 3 then
		s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
	end
	if #s ~= 6 then return nil end
	local r = tonumber(s:sub(1, 2), 16)
	local g = tonumber(s:sub(3, 4), 16)
	local b = tonumber(s:sub(5, 6), 16)
	if not r or not g or not b then return nil end
	return { r, g, b }
end

-- turns { "MetalNode", "Ore*" } into a fast matcher closure -----------------
local function compileMatcher(list)
	local exact, patterns = {}, {}
	if type(list) == "table" then
		for i = 1, #list do
			local name = tostring(list[i])
			if name:find("*", 1, true) then
				local escaped = name:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
				escaped = escaped:gsub("%*", ".*")
				patterns[#patterns + 1] = "^" .. escaped .. "$"
			else
				exact[name] = true
			end
		end
	end
	return function(name)
		if exact[name] then return true end
		for i = 1, #patterns do
			if name:match(patterns[i]) then return true end
		end
		return false
	end
end

-- ══════════════════════════════════════════════════════════════════════════
--  DEFAULT CONFIG
--  every category owns its own colour table, so colours are independent
-- ══════════════════════════════════════════════════════════════════════════

local DEFAULTS = {
	players = {
		enabled = true,
		maxDistance = 400,
		unlimited = false,

		chams     = { on = true,  color = { 120, 200, 255 }, fill = 35, outline = 100, throughWalls = true },
		box       = { on = true,  color = { 120, 200, 255 }, mode = "Corners", corner = 25, thickness = 1, alpha = 100 },
		fill      = { on = false, color = { 120, 200, 255 }, alpha = 12 },
		skeleton  = { on = true,  color = { 120, 200, 255 }, alpha = 100, thickness = 1, healthTint = false },
		healthBar = { on = true,  color = { 80, 220, 140 }, alpha = 100, width = 3, tint = false },
		healthText = { on = false, color = { 80, 220, 140 }, alpha = 100, tint = false },
		name      = { on = true,  color = { 255, 255, 255 }, alpha = 100, size = 14, healthTint = false },
		distance  = { on = true,  color = { 200, 200, 200 }, alpha = 100, meters = false },
		weapon    = { on = true,  color = { 255, 220, 80 }, alpha = 100, hideUnarmed = false },
		headDot   = { on = false, color = { 255, 255, 255 }, alpha = 100, size = 4 },
		tracer    = { on = false, color = { 167, 139, 250 }, alpha = 100, thickness = 1, origin = "Bottom" },
	},

	npcs = {
		enabled = true,
		maxDistance = 400,
		unlimited = false,

		chams     = { on = true,  color = { 255, 80, 80 }, fill = 35, outline = 100, throughWalls = true },
		box       = { on = true,  color = { 255, 80, 80 }, mode = "Corners", corner = 25, thickness = 1, alpha = 100 },
		fill      = { on = false, color = { 255, 80, 80 }, alpha = 12 },
		skeleton  = { on = true,  color = { 255, 80, 80 }, alpha = 100, thickness = 1, healthTint = false },
		healthBar = { on = true,  color = { 80, 220, 140 }, alpha = 100, width = 3, tint = false },
		healthText = { on = false, color = { 80, 220, 140 }, alpha = 100, tint = false },
		name      = { on = true,  color = { 255, 220, 220 }, alpha = 100, size = 14, healthTint = false },
		distance  = { on = true,  color = { 220, 200, 200 }, alpha = 100, meters = false },
		weapon    = { on = false, color = { 255, 220, 80 }, alpha = 100, hideUnarmed = true },
		headDot   = { on = false, color = { 255, 255, 255 }, alpha = 100, size = 4 },
		tracer    = { on = false, color = { 255, 120, 120 }, alpha = 100, thickness = 1, origin = "Bottom" },
	},

	nodes = {
		enabled = true,
		maxDistance = 500,
		unlimited = false,

		chams    = { on = true,  color = { 80, 220, 140 }, fill = 30, outline = 0, throughWalls = true },
		box      = { on = true,  color = { 80, 220, 140 }, mode = "Corners", corner = 25, thickness = 1, alpha = 100 },
		fill     = { on = false, color = { 80, 220, 140 }, alpha = 12 },
		name     = { on = true,  color = { 180, 255, 200 }, alpha = 100, size = 13, healthTint = false },
		distance = { on = true,  color = { 180, 255, 200 }, alpha = 100, meters = false },
		tracer   = { on = false, color = { 80, 220, 140 },  alpha = 100, thickness = 1, origin = "Bottom" },
	},

	filters = {
		npcMode           = "Whitelist",   -- Whitelist | Blacklist | All
		npcList           = { "Guard", "Scavenger", "Soldier" },
		nodeMode          = "Whitelist",   -- Whitelist | Blacklist
		nodeList          = { "MetalNode", "StoneNode", "SulfurNode", "Tree" },
		ignoreDead        = true,
		teamCheck         = false,
		showLocal         = false,
		maxTrackedNodes   = 400,
	},

	misc = {
		studsPerMeter = 3.571,
		boxScale      = 100,      -- % applied to the projected box
		maxObjects    = 160,      -- render budget (nearest first)
		rescanEvery   = 10,       -- seconds between full world rescans
	},

	menu = {
		keybind    = "RightShift",
		showButton = true,
		open       = true,
		x          = 60,
		y          = 60,
	},
}

local CFG = deepcopy(DEFAULTS)

-- numeric guards (a hand-edited / old config can never break the script) ---
local KEY_RANGES = {
	alpha     = { 0, 100 },
	fill      = { 0, 100 },
	outline   = { 0, 100 },
	corner    = { 5, 100 },
	thickness = { 1, 6 },
	size      = { 8, 32 },
	width     = { 1, 8 },
}

local function sanitize()
	for _, key in ipairs({ "players", "npcs", "nodes" }) do
		if type(CFG[key]) ~= "table" then CFG[key] = deepcopy(DEFAULTS[key]) end
		local cat = CFG[key]
		cat.maxDistance = clamp(tonumber(cat.maxDistance) or 400, 10, 3000)
		for _, fcfg in pairs(cat) do
			if type(fcfg) == "table" then
				if type(fcfg.color) == "table" then
					for i = 1, 3 do
						fcfg.color[i] = clamp(round(tonumber(fcfg.color[i]) or 255), 0, 255)
					end
				elseif fcfg.color ~= nil then
					fcfg.color = { 255, 255, 255 }
				end
				for k, v in pairs(fcfg) do
					local range = KEY_RANGES[k]
					if range and type(v) == "number" then
						fcfg[k] = clamp(v, range[1], range[2])
					end
				end
			end
		end
	end
	CFG.misc.studsPerMeter = clamp(tonumber(CFG.misc.studsPerMeter) or 3.571, 0.1, 100)
	CFG.misc.boxScale      = clamp(tonumber(CFG.misc.boxScale) or 100, 50, 200)
	CFG.misc.maxObjects    = clamp(round(tonumber(CFG.misc.maxObjects) or 160), 10, 500)
	CFG.misc.rescanEvery   = clamp(tonumber(CFG.misc.rescanEvery) or 10, 2, 120)
	CFG.filters.maxTrackedNodes = clamp(round(tonumber(CFG.filters.maxTrackedNodes) or 400), 10, 2000)
	if type(CFG.filters.npcList) ~= "table" then CFG.filters.npcList = { "Guard", "Scavenger", "Soldier" } end
	if type(CFG.filters.nodeList) ~= "table" then CFG.filters.nodeList = { "MetalNode", "StoneNode", "SulfurNode", "Tree" } end
end

-- merge (never replaces tables, so UI bindings stay valid) ------------------
-- list = dense array (1..n). Lists are replaced wholesale so e.g. editing the
-- npc whitelist to {"A"} really leaves you with just {"A"}.
local function isList(t)
	if type(t) ~= "table" then return false end
	if next(t) == nil then return false end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n == #t
end

local function mergeInto(dst, src)
	if type(src) ~= "table" then return dst end
	for k, v in pairs(src) do
		local cur = dst[k]
		if type(v) == "table" and type(cur) == "table" and not isList(v) then
			mergeInto(cur, v)
		elseif cur == nil or type(cur) == type(v) then
			if type(v) == "table" then
				-- replace list contents in place so live references stay valid
				for i = #cur, 1, -1 do cur[i] = nil end
				for i = 1, #v do cur[i] = v[i] end
			else
				dst[k] = v
			end
		end
	end
	return dst
end

local refreshers = {}

local function refreshUI()
	for i = 1, #refreshers do
		pcall(refreshers[i])
	end
end

-- ══════════════════════════════════════════════════════════════════════════
--  DRAWING WRAPPER
--  If the executor exposes no Drawing library (or it errors mid-session) the
--  ESP degrades gracefully instead of spamming errors every frame.
-- ══════════════════════════════════════════════════════════════════════════

local DRAWING_OK = (type(Drawing) == "table" and type(Drawing.new) == "function")

local function newDrawing(class)
	if not DRAWING_OK then return nil end
	local ok, obj = pcall(Drawing.new, class)
	if not ok or not obj then return nil end
	return obj
end

-- wrapper around a Drawing object. Every field write is forwarded to the real
-- object, so `Visible`, `From`, `Color`, ... behave exactly like the raw API.
local function wrapDrawing(obj)
	if not obj then return nil end

	local w = { __dead = false, __obj = obj }

	function w.set(props)
		if w.__dead then return end
		local ok = pcall(function()
			for k, v in pairs(props) do
				obj[k] = v
			end
		end)
		if not ok then
			w.__dead = true
		end
	end

	function w.remove()
		if w.__obj then w.__dead = true end
		pcall(function() obj.Visible = false end)
		pcall(function() obj:Remove() end)
		pcall(function() obj:Destroy() end)
		w.__obj = nil
	end

	-- proxy: reads/writes go to the underlying Drawing object
	return setmetatable(w, {
		__index = function(t, k)
			local raw = rawget(t, k)
			if raw ~= nil then return raw end
			return obj[k]
		end,
		__newindex = function(t, k, v)
			if k == "set" or k == "remove" or k == "__dead" or k == "__obj" then
				rawset(t, k, v)
				return
			end
			local ok = pcall(function() obj[k] = v end)
			if not ok then rawset(t, "__dead", true) end
		end,
	})
end

local function newLine(color, thickness, alpha)
	local w = wrapDrawing(newDrawing("Line"))
	if not w then return nil end
	w.set({
		Color = color or Color3.new(1, 1, 1),
		Thickness = thickness or 1,
		Transparency = alphaOf(alpha),
	})
	return w
end

local function newText(color, size, alpha)
	local w = wrapDrawing(newDrawing("Text"))
	if not w then return nil end
	w.set({
		Color = color or Color3.new(1, 1, 1),
		Size = size or 14,
		Transparency = alphaOf(alpha),
		Center = true,
		Outline = true,
		OutlineColor = Color3.fromRGB(0, 0, 0),
		Font = 2,
	})
	return w
end

local function newSquare(color, alpha, filled)
	local w = wrapDrawing(newDrawing("Square"))
	if not w then return nil end
	w.set({
		Color = color or Color3.new(1, 1, 1),
		Transparency = alphaOf(alpha),
		Filled = filled ~= false,
		Thickness = 1,
	})
	return w
end

local function showLine(w, a, b)
	if not w or w.__dead then return end
	w.Visible = true
	w.set({ From = a, To = b })
end

local function showText(w, text, x, y)
	if not w or w.__dead then return end
	if w.__text ~= text then
		w.__text = text
		w.set({ Text = text })
	end
	w.Visible = true
	w.set({ Position = Vector2.new(x, y) })
end

local function showSquare(w, x, y, sx, sy)
	if not w or w.__dead then return end
	w.Visible = true
	w.set({ Position = Vector2.new(x, y), Size = Vector2.new(math.max(sx, 0.5), math.max(sy, 0.5)) })
end

-- ══════════════════════════════════════════════════════════════════════════
--  MODEL HELPERS
-- ══════════════════════════════════════════════════════════════════════════

local R15_PAIRS = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
}

local R6_PAIRS = {
	{ "Head", "Torso" },
	{ "Torso", "Left Leg" }, { "Left Leg", "Left Foot" },
	{ "Torso", "Right Leg" }, { "Right Leg", "Right Foot" },
	{ "Torso", "Left Arm" }, { "Left Arm", "Left Hand" },
	{ "Torso", "Right Arm" }, { "Right Arm", "Right Hand" },
}

local MAX_BONES = math.max(#R15_PAIRS, #R6_PAIRS)

local function getRoot(model)
	if not model then return nil end
	return model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("Head")
end

local function getHumanoid(model)
	if not model then return nil end
	return model:FindFirstChildOfClass("Humanoid")
end

local function isAlive(model)
	if not model or not model.Parent then return false end
	if not model:IsDescendantOf(Workspace) then return false end
	local hum = getHumanoid(model)
	if not hum then return false end
	if CFG.filters.ignoreDead then
		return hum.Health > 0
	end
	return true
end

local function bonePairsFor(model)
	if model:FindFirstChild("UpperTorso") or model:FindFirstChild("LowerTorso") then
		return R15_PAIRS
	end
	if model:FindFirstChild("Torso") then
		return R6_PAIRS
	end
	return nil
end

local WEAPON_WORDS = {
	"gun", "rifle", "pistol", "smg", "shotgun", "sniper", "melee", "knife",
	"sword", "axe", "bow", "launcher", "carbine", "grenade", "club", "bat",
	"revolver", "magnum", "blade",
}

local function getEquippedWeapon(model)
	local tool = model:FindFirstChildOfClass("Tool")
	if tool then return tool.Name end

	local attr = model:GetAttribute("EquippedWeapon")
		or model:GetAttribute("Weapon")
		or model:GetAttribute("CurrentGun")
		or model:GetAttribute("Equipped")
	if attr then return tostring(attr) end

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Tool") then
			local lower = child.Name:lower()
			for i = 1, #WEAPON_WORDS do
				if lower:find(WEAPON_WORDS[i], 1, true) then
					return child.Name
				end
			end
		end
	end

	return nil
end

local function nodePosition(obj)
	if not obj or not obj.Parent then return nil end
	if obj:IsA("BasePart") then return obj.Position end
	if obj:IsA("Model") then
		local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
		return part and part.Position or nil
	end
	return nil
end

-- eye-level anchor + world height, used for box projection ----------------
local function anchorOf(model)
	local hum = getHumanoid(model)
	if hum and hum.RootPart then
		return hum.RootPart.Position
	end
	local root = getRoot(model)
	return root and root.Position or nil
end

local function worldHeight(model, rootPos)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") and rootPos then
		local topY = head.Position.Y + head.Size.Y * 0.5
		local footY = rootPos.Y - 2.8
		local height = topY - footY
		if height > 1 then return height end
	end
	return 5
end

-- ══════════════════════════════════════════════════════════════════════════
--  ESP OBJECT FACTORY
-- ══════════════════════════════════════════════════════════════════════════

local function makeEsp(kind, cat)
	local esp = {
		kind = kind,
		cat = cat,
		box = {},
		skeleton = {},
		highlight = nil,
		lastVisible = false,
		lastPos = nil,
	}

	for i = 1, 8 do
		esp.box[i] = newLine(Color3.new(1, 1, 1), 1, 100)
	end

	if kind ~= "node" then
		for i = 1, MAX_BONES do
			esp.skeleton[i] = newLine(Color3.new(1, 1, 1), 1, 100)
		end
		esp.fill       = newSquare(Color3.new(1, 1, 1), 100, true)
		esp.healthBg   = newSquare(Color3.new(0, 0, 0), 60, true)
		esp.healthFg   = newSquare(Color3.new(1, 1, 1), 100, true)
		esp.name       = newText(Color3.new(1, 1, 1), CFG[cat].name.size, 100)
		esp.distance   = newText(Color3.new(1, 1, 1), 12, 100)
		esp.weapon     = newText(Color3.new(1, 1, 1), 12, 100)
		esp.healthText = newText(Color3.new(1, 1, 1), 11, 100)
		esp.headDot    = newSquare(Color3.new(1, 1, 1), 100, true)
		esp.tracer     = newLine(Color3.new(1, 1, 1), 1, 100)
	else
		esp.fill     = newSquare(Color3.new(1, 1, 1), 100, true)
		esp.name     = newText(Color3.new(1, 1, 1), 13, 100)
		esp.distance = newText(Color3.new(1, 1, 1), 11, 100)
		esp.tracer   = newLine(Color3.new(1, 1, 1), 1, 100)
	end

	return esp
end

local function destroyEsp(esp)
	for i = 1, #esp.box do
		if esp.box[i] then esp.box[i].remove() end
	end
	for i = 1, #esp.skeleton do
		if esp.skeleton[i] then esp.skeleton[i].remove() end
	end
	for _, key in ipairs({ "fill", "healthBg", "healthFg", "name", "distance", "weapon", "healthText", "headDot", "tracer" }) do
		local obj = esp[key]
		if obj then obj.remove() end
	end
	if esp.highlight then
		pcall(function() esp.highlight:Destroy() end)
		esp.highlight = nil
	end
end

local function hideEsp(esp)
	for i = 1, #esp.box do
		if esp.box[i] then esp.box[i].Visible = false end
	end
	for i = 1, #esp.skeleton do
		if esp.skeleton[i] then esp.skeleton[i].Visible = false end
	end
	for _, key in ipairs({ "fill", "healthBg", "healthFg", "name", "distance", "weapon", "healthText", "headDot", "tracer" }) do
		local obj = esp[key]
		if obj then obj.Visible = false end
	end
	if esp.highlight then esp.highlight.Enabled = false end
	esp.lastVisible = false
end

local function syncHighlight(esp, instance)
	local chams = CFG[esp.cat].chams

	if not chams.on then
		if esp.highlight then
			pcall(function() esp.highlight:Destroy() end)
			esp.highlight = nil
		end
		return
	end

	if not esp.highlight then
		local ok, hl = pcall(Instance.new, "Highlight")
		if not ok or not hl then return end
		hl.Name = "ESP_Chams"
		esp.highlight = hl
	end

	local hl = esp.highlight
	local col = rgb(chams.color)

	hl.FillColor = col
	hl.OutlineColor = col
	hl.FillTransparency = clamp(1 - (chams.fill / 100), 0, 1)
	hl.OutlineTransparency = clamp(1 - (chams.outline / 100), 0, 1)
	hl.Enabled = esp.lastVisible

	pcall(function()
		if chams.throughWalls then
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		else
			hl.DepthMode = Enum.HighlightDepthMode.Occluded
		end
	end)

	if hl.Parent ~= instance then
		hl.Adornee = instance
		hl.Parent = instance
	end
end

-- ══════════════════════════════════════════════════════════════════════════
--  FILTERS  (live-editable name lists, supports * wildcards)
-- ══════════════════════════════════════════════════════════════════════════

local matchers = {
	npc  = function() return false end,
	node = function() return false end,
}

local function rebuildFilters()
	matchers.npc  = compileMatcher(CFG.filters.npcList)
	matchers.node = compileMatcher(CFG.filters.nodeList)
end
rebuildFilters()

local function isTargetNpc(model)
	if not model or not model.Parent then return false end
	if not model:IsA("Model") then return false end
	if not model:IsDescendantOf(Workspace) then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	if not getHumanoid(model) then return false end

	local mode = CFG.filters.npcMode
	local matched = matchers.npc(model.Name)
	if mode == "All" then return true end
	if mode == "Blacklist" then return not matched end
	return matched
end

local function isTargetNode(obj)
	if not obj or not obj.Parent then return false end
	if not obj:IsDescendantOf(Workspace) then return false end
	if obj:IsA("Player") or obj:IsA("PlayerGui") or obj:IsA("Camera") then return false end
	if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end

	local matched = matchers.node(obj.Name)
	if CFG.filters.nodeMode == "Blacklist" then return not matched end
	return matched
end

-- ══════════════════════════════════════════════════════════════════════════
--  TRACKING
-- ══════════════════════════════════════════════════════════════════════════

local tracked = {}          -- [instance] = esp
local trackedCount = { player = 0, npc = 0, node = 0 }

local function track(instance, kind)
	if not instance or tracked[instance] then return end
	local cat = (kind == "node") and "nodes" or (kind == "npc" and "npcs" or "players")
	if kind == "node" and trackedCount.node >= CFG.filters.maxTrackedNodes then return end

	tracked[instance] = makeEsp(kind, cat)
	trackedCount[kind] = (trackedCount[kind] or 0) + 1
end

local function untrack(instance)
	local esp = tracked[instance]
	if not esp then return end
	destroyEsp(esp)
	tracked[instance] = nil
	trackedCount[esp.kind] = math.max((trackedCount[esp.kind] or 1) - 1, 0)
end

local function untrackAll()
	for instance in pairs(tracked) do
		untrack(instance)
	end
end

local function trackedFor(instance)
	return tracked[instance]
end

-- ══════════════════════════════════════════════════════════════════════════
--  RENDERING
-- ══════════════════════════════════════════════════════════════════════════

local function viewport()
	local v = Camera.ViewportSize
	return v.X, v.Y
end

local function project(pos)
	local sp, onScreen = Camera:WorldToScreenPoint(pos)
	if sp.Z <= 0 then return nil end
	local vx, vy = viewport()
	return sp, onScreen, vx, vy
end

-- box: 8 segments, cornerFraction 1.0 makes them join into a full frame ----
local function drawBox(esp, bcfg, x, y, w, h)
	local col = rgb(bcfg.color)
	local alpha = alphaOf(bcfg.alpha)
	local f = (bcfg.mode == "Full") and 1 or (clamp(bcfg.corner, 5, 100) / 100)
	local ch, cv = w * f, h * f
	local x2, y2 = x + w, y + h

	local segs = {
		{ x, y, x + ch, y },       { x, y, x, y + cv },
		{ x2 - ch, y, x2, y },     { x2, y, x2, y + cv },
		{ x, y2, x + ch, y2 },     { x, y2 - cv, x, y2 },
		{ x2 - ch, y2, x2, y2 },   { x2, y2 - cv, x2, y2 },
	}

	for i = 1, 8 do
		local line = esp.box[i]
		if line and not line.__dead then
			local s = segs[i]
			line.Visible = true
			line.set({
				From = Vector2.new(s[1], s[2]),
				To = Vector2.new(s[3], s[4]),
				Color = col,
				Thickness = bcfg.thickness,
				Transparency = alpha,
			})
		end
	end
end

-- green at full health -> yellow -> red at zero
local function hpColor(pct)
	pct = clamp(pct, 0, 1)
	return Color3.fromRGB(floor(255 * (1 - pct)), floor(255 * pct), 40)
end

local function drawSkeleton(esp, model, scfg, healthPct)
	local pairsList = bonePairsFor(model)
	if not pairsList then return end

	local col = scfg.healthTint and hpColor(healthPct) or rgb(scfg.color)
	local alpha = alphaOf(scfg.alpha)

	for i = 1, MAX_BONES do
		local line = esp.skeleton[i]
		if line and not line.__dead then
			local pair = pairsList[i]
			if pair then
				local a = model:FindFirstChild(pair[1])
				local b = model:FindFirstChild(pair[2])
				if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
					local sa, oka = Camera:WorldToScreenPoint(a.Position)
					local sb, okb = Camera:WorldToScreenPoint(b.Position)
					if oka and okb and sa.Z > 0 and sb.Z > 0 then
						line.Visible = true
						line.set({
							From = Vector2.new(sa.X, sa.Y),
							To = Vector2.new(sb.X, sb.Y),
							Color = col,
							Thickness = scfg.thickness,
							Transparency = alpha,
						})
					else
						line.Visible = false
					end
				else
					line.Visible = false
				end
			else
				line.Visible = false
			end
		end
	end
end

local function withinLimit(catCfg, studs)
	if catCfg.unlimited then return true end
	return studs <= catCfg.maxDistance
end

local function formatDistance(studs, meters)
	if meters then
		return string.format("%.1fm", studs / (CFG.misc.studsPerMeter or 3.571))
	end
	return string.format("%.0fs", studs)
end

local function tracerOrigin(vx, vy, origin)
	if origin == "Top" then return Vector2.new(vx * 0.5, 0) end
	if origin == "Left" then return Vector2.new(0, vy * 0.5) end
	if origin == "Right" then return Vector2.new(vx, vy * 0.5) end
	if origin == "Center" then return Vector2.new(vx * 0.5, vy * 0.5) end
	if origin == "Mouse" then
		local m = UserInputService:GetMouseLocation()
		return Vector2.new(m.X, m.Y)
	end
	return Vector2.new(vx * 0.5, vy)
end

local function drawTracer(esp, tcfg, vx, vy, toX, toY)
	local t = esp.tracer
	if not t or t.__dead then return end
	if not tcfg.on then t.Visible = false return end
	local from = tracerOrigin(vx, vy, tcfg.origin)
	t.Visible = true
	t.set({
		From = from,
		To = Vector2.new(toX, toY),
		Color = rgb(tcfg.color),
		Thickness = tcfg.thickness,
		Transparency = alphaOf(tcfg.alpha),
	})
end

-- ── characters (players + npcs) ───────────────────────────────────────────
local function renderCharacter(instance, esp)
	local cat = CFG[esp.cat]
	local model = instance

	if not cat.enabled or not isAlive(model) then
		hideEsp(esp)
		return
	end

	local hum = getHumanoid(model)
	local anchor = anchorOf(model)
	if not hum or not anchor then
		hideEsp(esp)
		return
	end

	local camPos = Camera.CFrame.Position
	local studs = (anchor - camPos).Magnitude

	if not withinLimit(cat, studs) then
		hideEsp(esp)
		return
	end

	if esp.kind == "player" then
		if not CFG.filters.showLocal and instance == LocalPlayer.Character then
			hideEsp(esp)
			return
		end
		if CFG.filters.teamCheck and LocalPlayer.Team then
			local ok, plr = pcall(Players.GetPlayerFromCharacter, Players, instance)
			if ok and plr and plr.Team == LocalPlayer.Team then
				hideEsp(esp)
				return
			end
		end
	end

	local rootPos = anchor
	local height = worldHeight(model, rootPos) * (CFG.misc.boxScale / 100)
	local half = height * 0.5

	local topPos = rootPos + Vector3.new(0, half, 0)
	local botPos = rootPos - Vector3.new(0, half, 0)

	local sTop = project(topPos)
	local sBot = project(botPos)
	if not sTop or not sBot then
		hideEsp(esp)
		return
	end

	local vx, vy = viewport()
	local cx = (sTop.X + sBot.X) * 0.5
	local y = math.min(sTop.Y, sBot.Y)
	local h = math.abs(sBot.Y - sTop.Y)
	local w = h * 0.55

	if h < 2 or h > vy * 4 then
		hideEsp(esp)
		return
	end

	local x = cx - w / 2
	local y2 = y + h
	local onScreen = (cx + w * 0.5 > -40 and cx - w * 0.5 < vx + 40 and y2 > -40 and y < vy + 40)
	if not onScreen then
		hideEsp(esp)
		return
	end

	local healthPct = clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)

	-- chams
	syncHighlight(esp, model)
	if esp.highlight then esp.highlight.Enabled = true end

	-- box
	if cat.box.on then
		drawBox(esp, cat.box, x, y, w, h)
	else
		for i = 1, 8 do if esp.box[i] then esp.box[i].Visible = false end end
	end

	-- fill
	if cat.fill.on and esp.fill and not esp.fill.__dead then
		showSquare(esp.fill, x, y, w, h)
		esp.fill.set({ Color = rgb(cat.fill.color), Transparency = alphaOf(cat.fill.alpha), Filled = true })
	elseif esp.fill then
		esp.fill.Visible = false
	end

	-- skeleton
	if cat.skeleton.on then
		drawSkeleton(esp, model, cat.skeleton, healthPct)
	else
		for i = 1, MAX_BONES do if esp.skeleton[i] then esp.skeleton[i].Visible = false end end
	end

	-- health bar
	if cat.healthBar.on and esp.healthBg and esp.healthFg then
		local barW = cat.healthBar.width
		local bx = x - barW - 3
		showSquare(esp.healthBg, bx, y, barW, h)
		esp.healthBg.set({ Color = Color3.fromRGB(15, 15, 15), Transparency = 0.35 })

		local fgH = h * healthPct
		showSquare(esp.healthFg, bx, y + (h - fgH), barW, fgH)
		esp.healthFg.set({
			Color = cat.healthBar.tint and hpColor(healthPct) or rgb(cat.healthBar.color),
			Transparency = alphaOf(cat.healthBar.alpha),
		})
	else
		if esp.healthBg then esp.healthBg.Visible = false end
		if esp.healthFg then esp.healthFg.Visible = false end
	end

	-- health text
	if cat.healthText.on and esp.healthText then
		local hpStr = string.format("%d", math.ceil(hum.Health))
		showText(esp.healthText, hpStr, x - 14, y + h * 0.5)
		esp.healthText.set({
			Color = cat.healthText.tint and hpColor(healthPct) or rgb(cat.healthText.color),
			Transparency = alphaOf(cat.healthText.alpha),
			Size = 11,
		})
	elseif esp.healthText then
		esp.healthText.Visible = false
	end

	-- name
	if cat.name.on and esp.name then
		showText(esp.name, model.Name, cx, y - (cat.name.size or 14) - 4)
		esp.name.set({
			Color = cat.name.healthTint and hpColor(healthPct) or rgb(cat.name.color),
			Transparency = alphaOf(cat.name.alpha),
			Size = cat.name.size,
		})
	elseif esp.name then
		esp.name.Visible = false
	end

	-- distance + weapon stack below the box
	local stackY = y2 + 3
	if cat.distance.on and esp.distance then
		showText(esp.distance, formatDistance(studs, cat.distance.meters), cx, stackY)
		esp.distance.set({
			Color = rgb(cat.distance.color),
			Transparency = alphaOf(cat.distance.alpha),
			Size = 12,
		})
		stackY = stackY + 14
	elseif esp.distance then
		esp.distance.Visible = false
	end

	if cat.weapon.on and esp.weapon then
		local weapon = getEquippedWeapon(model)
		if weapon or not cat.weapon.hideUnarmed then
			showText(esp.weapon, weapon or "Unarmed", cx, stackY)
			esp.weapon.set({
				Color = rgb(cat.weapon.color),
				Transparency = alphaOf(cat.weapon.alpha),
				Size = 12,
			})
		else
			esp.weapon.Visible = false
		end
	elseif esp.weapon then
		esp.weapon.Visible = false
	end

	-- head dot
	if cat.headDot.on and esp.headDot then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local sh = project(head.Position)
			if sh then
				local s = cat.headDot.size
				showSquare(esp.headDot, sh.X - s / 2, sh.Y - s / 2, s, s)
				esp.headDot.set({ Color = rgb(cat.headDot.color), Transparency = alphaOf(cat.headDot.alpha) })
			else
				esp.headDot.Visible = false
			end
		else
			esp.headDot.Visible = false
		end
	elseif esp.headDot then
		esp.headDot.Visible = false
	end

	-- tracer
	drawTracer(esp, cat.tracer, vx, vy, cx, y + h * 0.5)

	esp.lastVisible = true
	esp.lastPos = anchor
end

-- ── nodes ─────────────────────────────────────────────────────────────────
local function renderNode(instance, esp)
	local cat = CFG.nodes
	local pos = nodePosition(instance)

	if not cat.enabled or not pos then
		hideEsp(esp)
		return
	end

	local camPos = Camera.CFrame.Position
	local studs = (pos - camPos).Magnitude
	if not withinLimit(cat, studs) then
		hideEsp(esp)
		return
	end

	local sp = project(pos)
	if not sp then
		hideEsp(esp)
		return
	end

	local vx, vy = viewport()
	local sizeStuds = 4
	if instance:IsA("BasePart") then
		local s = instance.Size
		sizeStuds = math.max(s.X, s.Y, s.Z)
	elseif instance:IsA("Model") then
		local part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
		if part then
			local s = part.Size
			sizeStuds = math.max(s.X, s.Y, s.Z)
		end
	end
	sizeStuds = clamp(sizeStuds, 2, 24)

	local h = clamp((sizeStuds * 40) / math.max(sp.Z, 1) * 1.6, 12, 900) * (CFG.misc.boxScale / 100)
	local w = h
	local x = sp.X - w / 2
	local y = sp.Y - h / 2

	if sp.X + w < -60 or sp.X - w > vx + 60 or sp.Y + h < -60 or sp.Y - h > vy + 60 then
		hideEsp(esp)
		return
	end

	syncHighlight(esp, instance)
	if esp.highlight then esp.highlight.Enabled = true end

	if cat.box.on then
		drawBox(esp, cat.box, x, y, w, h)
	else
		for i = 1, 8 do if esp.box[i] then esp.box[i].Visible = false end end
	end

	if cat.fill.on and esp.fill and not esp.fill.__dead then
		showSquare(esp.fill, x, y, w, h)
		esp.fill.set({ Color = rgb(cat.fill.color), Transparency = alphaOf(cat.fill.alpha), Filled = true })
	elseif esp.fill then
		esp.fill.Visible = false
	end

	if cat.name.on and esp.name then
		showText(esp.name, instance.Name, sp.X, y - (cat.name.size or 13) - 4)
		esp.name.set({
			Color = rgb(cat.name.color),
			Transparency = alphaOf(cat.name.alpha),
			Size = cat.name.size,
		})
	elseif esp.name then
		esp.name.Visible = false
	end

	if cat.distance.on and esp.distance then
		showText(esp.distance, formatDistance(studs, cat.distance.meters), sp.X, y + h + 3)
		esp.distance.set({
			Color = rgb(cat.distance.color),
			Transparency = alphaOf(cat.distance.alpha),
			Size = 11,
		})
	elseif esp.distance then
		esp.distance.Visible = false
	end

	drawTracer(esp, cat.tracer, vx, vy, sp.X, sp.Y)

	esp.lastVisible = true
	esp.lastPos = pos
end

-- ══════════════════════════════════════════════════════════════════════════
--  RENDER LOOP
-- ══════════════════════════════════════════════════════════════════════════

local renderConn
local renderEnabled = true
local scratch = {}

local function renderLoop()
	if not renderEnabled then return end
	Camera = Workspace.CurrentCamera
	if not Camera then return end

	-- gather + sort by distance so the render budget favours nearby targets
	local camPos = Camera.CFrame.Position
	local n = 0
	for instance, esp in pairs(tracked) do
		if instance.Parent and instance:IsDescendantOf(Workspace) then
			local pos = esp.lastPos or anchorOf(instance) or nodePosition(instance)
			local d = pos and (pos - camPos).Magnitude or huge
			n = n + 1
			scratch[n] = { instance, esp, d }
		else
			untrack(instance)
		end
	end

	for i = n + 1, #scratch do
		scratch[i] = nil
	end

	table.sort(scratch, function(a, b) return a[3] < b[3] end)

	local budget = CFG.misc.maxObjects
	for i = 1, n do
		local entry = scratch[i]
		if entry then
			local instance, esp = entry[1], entry[2]
			if i > budget then
				hideEsp(esp)
			else
				local ok = pcall(function()
					if esp.kind == "node" then
						renderNode(instance, esp)
					else
						renderCharacter(instance, esp)
					end
				end)
				if not ok then hideEsp(esp) end
			end
			scratch[i] = nil
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════
--  DISCOVERY  (players / npcs / nodes)
-- ══════════════════════════════════════════════════════════════════════════

local connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

local function watchCharacter(player)
	if player == LocalPlayer and not CFG.filters.showLocal then
		return
	end
	local char = player.Character
	if char then track(char, "player") end
end

local function hookPlayer(player)
	if player == LocalPlayer and not CFG.filters.showLocal then return end
	watchCharacter(player)
	connect(player.CharacterAdded, function(char)
		track(char, "player")
	end)
	connect(player.CharacterRemoving, function(char)
		untrack(char)
	end)
end

-- NPCs are found by walking Workspace for Humanoids whose parent model
-- passes the (editable) whitelist / blacklist filter.
local function scanNpcs()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Humanoid") and d.Parent then
			local model = d.Parent
			if isTargetNpc(model) then
				track(model, "npc")
			elseif tracked[model] and tracked[model].kind == "npc" then
				untrack(model)
			end
		end
	end
end

local function belongsToCharacter(obj)
	local parent = obj.Parent
	if not parent then return false end
	if Players:GetPlayerFromCharacter(parent) then return true end
	if tracked[parent] and tracked[parent].kind ~= "node" then return true end
	return false
end

local function scanNodes()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and isTargetNode(d) then
			if not belongsToCharacter(d) then
				track(d, "node")
			end
		elseif tracked[d] and tracked[d].kind == "node" and not isTargetNode(d) then
			untrack(d)
		end
	end
end

local function scanPlayers()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer or CFG.filters.showLocal then
			if p.Character then track(p.Character, "player") end
		end
	end
end

local function fullScan()
	if CFG.players.enabled then scanPlayers() end
	if CFG.npcs.enabled then scanNpcs() end
	if CFG.nodes.enabled then scanNodes() end
end

-- ── live hooks ────────────────────────────────────────────────────────────
connect(Players.PlayerAdded, hookPlayer)
connect(Players.PlayerRemoving, function(player)
	if player.Character then untrack(player.Character) end
end)

local hookedPlayers = {}
for _, p in ipairs(Players:GetPlayers()) do
	if not hookedPlayers[p] then
		hookedPlayers[p] = true
		hookPlayer(p)
	end
end

connect(Workspace.DescendantAdded, function(d)
	if d:IsA("Humanoid") and d.Parent then
		local model = d.Parent
		if isTargetNpc(model) then
			delayFn(0.1, function()
				if model.Parent and isTargetNpc(model) then
					track(model, "npc")
				end
			end)
		end
	elseif (d:IsA("BasePart") or d:IsA("Model")) and isTargetNode(d) then
		track(d, "node")
	end
end)

connect(Workspace.DescendantRemoving, function(d)
	if tracked[d] then untrack(d) end
	if d:IsA("Humanoid") and d.Parent and tracked[d.Parent] then
		untrack(d.Parent)
	end
end)

-- the filters are editable at runtime, so rescan when they change ----------
local function onFiltersChanged()
	rebuildFilters()
	untrackAll()
	fullScan()
end

-- periodic rescan catches anything the hooks missed -----------------------
local rescanAccum = 0
connect(RunService.Heartbeat, function(dt)
	rescanAccum = rescanAccum + dt
	if rescanAccum >= (CFG.misc.rescanEvery or 10) then
		rescanAccum = 0
		if CFG.npcs.enabled then scanNpcs() end
		if CFG.nodes.enabled then scanNodes() end
	end
end)

renderConn = RunService.RenderStepped:Connect(renderLoop)

-- ══════════════════════════════════════════════════════════════════════════
--  UI THEME
-- ══════════════════════════════════════════════════════════════════════════

local THEME = {
	bg        = Color3.fromRGB(15, 16, 20),
	panel     = Color3.fromRGB(23, 25, 31),
	row       = Color3.fromRGB(30, 33, 41),
	rowHover  = Color3.fromRGB(38, 42, 52),
	stroke    = Color3.fromRGB(43, 47, 58),
	text      = Color3.fromRGB(228, 232, 240),
	muted     = Color3.fromRGB(126, 134, 150),
	accent    = Color3.fromRGB(167, 139, 250),
	good      = Color3.fromRGB(74, 222, 128),
	bad       = Color3.fromRGB(248, 113, 113),
	input     = Color3.fromRGB(17, 18, 23),
	warn      = Color3.fromRGB(250, 204, 21),
}

local FONT       = Enum.Font.GothamMedium
local FONT_BOLD  = Enum.Font.GothamBold
local FONT_SMALL = Enum.Font.Gotham

local MENU_W, MENU_H = 340, 400
local PAD, ROW_H, ROW_GAP = 10, 26, 4
local SLIDER_H = 34
local TAB_H = 28

-- ══════════════════════════════════════════════════════════════════════════
--  UI HELPERS
-- ══════════════════════════════════════════════════════════════════════════

local function new(className, props, children)
	local obj = Instance.new(className)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then obj[k] = v end
	end
	for _, child in ipairs(children or {}) do child.Parent = obj end
	if props and props.Parent then obj.Parent = props.Parent end
	return obj
end

local function corner(radius, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function stroke(color, thickness, parent)
	return new("UIStroke", {
		Color = color or THEME.stroke,
		Thickness = thickness or 1,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function pad(amount, parent)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, amount), PaddingBottom = UDim.new(0, amount),
		PaddingLeft = UDim.new(0, amount), PaddingRight = UDim.new(0, amount),
		Parent = parent,
	})
end

local function listLayout(parent, gap, padTop)
	return new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

local function label(text, size, color, parent, bold)
	local l = new("TextLabel", {
		Text = text,
		BackgroundTransparency = 1,
		Font = bold and FONT_BOLD or FONT,
		TextSize = size or 12,
		TextColor3 = color or THEME.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
		Parent = parent,
	})
	return l
end

-- ══════════════════════════════════════════════════════════════════════════
--  GUI ROOT
-- ══════════════════════════════════════════════════════════════════════════

local gui = nil
local screen = nil

local guiParentCandidates = { CoreGui, LocalPlayer:FindFirstChild("PlayerGui"), game:GetService("Players") }

local function createGui()
	for _, parent in ipairs(guiParentCandidates) do
		if parent then
			local ok, result = pcall(function()
				local g = new("ScreenGui", {
					Name = "ESP_Suite_" .. tostring(math.random(1000, 9999)),
					ResetOnSpawn = false,
					IgnoreGuiInset = true,
					DisplayOrder = 999,
					ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
					Parent = parent,
				})
				return g
			end)
			if ok and result then return result end
		end
	end
	return nil
end

gui = createGui()
if gui then
	local ok, err = pcall(function()
		screen = new("Frame", {
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
		})
	end)
	if not ok then screen = nil end
else
	warn("[ESP] could not create a ScreenGui — running without the menu")
end

-- ══════════════════════════════════════════════════════════════════════════
--  MINI UI LIBRARY
-- ══════════════════════════════════════════════════════════════════════════

local UI = {}
local tabs = {}
local activeTab = nil
local needsSort = {}

local function markSort(parent)
	needsSort[parent] = true
end

local function applySorts()
	for parent in pairs(needsSort) do
		needsSort[parent] = nil
		local ok, layout = pcall(function()
			return parent:FindFirstChildOfClass("UIListLayout")
		end)
		if ok and layout then
			pcall(function() parent.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y) end)
		end
	end
end

-- ── toggle row ────────────────────────────────────────────────────────────
function UI.toggle(parent, text, obj, key, onChange)
	local row = new("TextButton", {
		Name = "Toggle_" .. text,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.row,
		Size = UDim2.new(1, 0, 0, ROW_H),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	corner(5, row)
	local lbl = label(text, 12, THEME.text, row)
	lbl.Size = UDim2.new(1, -56, 1, 0)
	lbl.Position = UDim2.new(0, 10, 0, 0)

	local track = new("Frame", {
		Name = "Track",
		BackgroundColor3 = THEME.input,
		Size = UDim2.fromOffset(34, 16),
		Position = UDim2.new(1, -44, 0.5, -8),
		Parent = row,
	})
	corner(8, track)
	stroke(THEME.stroke, 1, track)

	local knob = new("Frame", {
		Name = "Knob",
		BackgroundColor3 = THEME.muted,
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.new(0, 2, 0.5, -6),
		Parent = track,
	})
	corner(6, knob)

	local function paint(on)
		if on then
			track.BackgroundColor3 = THEME.accent
			stroke(THEME.accent, 1, track)
			knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			TweenService:Create(knob, TweenInfo.new(0.12), { Position = UDim2.new(1, -14, 0.5, -6) }):Play()
			lbl.TextColor3 = THEME.text
		else
			track.BackgroundColor3 = THEME.input
			stroke(THEME.stroke, 1, track)
			knob.BackgroundColor3 = THEME.muted
			TweenService:Create(knob, TweenInfo.new(0.12), { Position = UDim2.new(0, 2, 0.5, -6) }):Play()
			lbl.TextColor3 = THEME.muted
		end
	end

	row.MouseEnter:Connect(function() row.BackgroundColor3 = THEME.rowHover end)
	row.MouseLeave:Connect(function() row.BackgroundColor3 = THEME.row end)
	row.MouseButton1Click:Connect(function()
		obj[key] = not obj[key]
		paint(obj[key])
		if onChange then pcall(onChange) end
	end)

	paint(obj[key])
	row.Destroying:Connect(function() end)

	refreshers[#refreshers + 1] = function() paint(obj[key]) end
	markSort(parent)
	return row
end

-- ── slider row ────────────────────────────────────────────────────────────
function UI.slider(parent, text, obj, key, min, max, step, suffix, onChange)
	step = step or 1
	local holder = new("Frame", {
		Name = "Slider_" .. text,
		BackgroundColor3 = THEME.row,
		Size = UDim2.new(1, 0, 0, SLIDER_H),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	corner(5, holder)

	local lbl = label(text, 12, THEME.text, holder)
	lbl.Size = UDim2.new(1, -70, 0, 14)
	lbl.Position = UDim2.new(0, 10, 0, 5)

	local valueLbl = label("", 12, THEME.muted, holder)
	valueLbl.Size = UDim2.new(1, -20, 0, 14)
	valueLbl.Position = UDim2.new(0, 10, 0, 5)
	valueLbl.TextXAlignment = Enum.TextXAlignment.Right
	valueLbl.Font = FONT_BOLD
	valueLbl.TextColor3 = THEME.accent

	local bar = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.input,
		Size = UDim2.new(1, -20, 0, 5),
		Position = UDim2.new(0, 10, 0, 24),
		Parent = holder,
	})
	corner(3, bar)
	local fill = new("Frame", {
		BackgroundColor3 = THEME.accent,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	})
	corner(3, fill)

	local knob = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Size = UDim2.fromOffset(10, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Parent = bar,
	})
	corner(5, knob)

	local function decimals()
		if step >= 1 then return 0 end
		if step >= 0.1 then return 1 end
		return 2
	end

	local function paint()
		local v = tonumber(obj[key]) or min
		local t = (max > min) and clamp((v - min) / (max - min), 0, 1) or 0
		fill.Size = UDim2.fromScale(t, 1)
		knob.Position = UDim2.new(t, 0, 0.5, 0)
		local txt = string.format("%." .. decimals() .. "f", v)
		if txt == "-0" then txt = "0" end
		valueLbl.Text = txt .. (suffix or "")
	end

	local dragging = false
	local function setFromX(x)
		local abs = bar.AbsolutePosition.X
		local width = math.max(bar.AbsoluteSize.X, 1)
		local t = clamp((x - abs) / width, 0, 1)
		local raw = min + t * (max - min)
		local v = floor(raw / step + 0.5) * step
		v = clamp(v, min, max)
		obj[key] = v
		paint()
		if onChange then pcall(onChange) end
	end

	bar.MouseButton1Down:Connect(function() dragging = true end)
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)

	paint()
	refreshers[#refreshers + 1] = paint
	markSort(parent)
	return holder
end

-- ── dropdown row ──────────────────────────────────────────────────────────
local openDropdown = nil

function UI.dropdown(parent, text, obj, key, options, onChange)
	local row = new("TextButton", {
		Name = "Dropdown_" .. text,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.row,
		Size = UDim2.new(1, 0, 0, ROW_H),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	corner(5, row)

	local lbl = label(text, 12, THEME.text, row)
	lbl.Size = UDim2.new(0.55, -10, 1, 0)
	lbl.Position = UDim2.new(0, 10, 0, 0)

	local valueLbl = label(tostring(obj[key]), 12, THEME.accent, row)
	valueLbl.Size = UDim2.new(0.45, -16, 1, 0)
	valueLbl.Position = UDim2.new(0.55, 0, 0, 0)
	valueLbl.TextXAlignment = Enum.TextXAlignment.Right
	valueLbl.Font = FONT_BOLD

	row.MouseEnter:Connect(function() row.BackgroundColor3 = THEME.rowHover end)
	row.MouseLeave:Connect(function() row.BackgroundColor3 = THEME.row end)

	row.MouseButton1Click:Connect(function()
		if openDropdown and openDropdown ~= row then
			local old = openDropdown:FindFirstChild("Options")
			if old then old:Destroy() end
			openDropdown = nil
		end

		local existing = row:FindFirstChild("Options")
		if existing then
			existing:Destroy()
			openDropdown = nil
			return
		end

		openDropdown = row
		local list = new("Frame", {
			Name = "Options",
			BackgroundColor3 = THEME.panel,
			Size = UDim2.new(1, -16, 0, #options * 24 + 8),
			Position = UDim2.new(0, 8, 1, 4),
			ZIndex = 20,
			Parent = row,
		})
		corner(5, list)
		stroke(THEME.stroke, 1, list)
		listLayout(list, 0)

		for i, opt in ipairs(options) do
			local btn = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = THEME.panel,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = i,
				ZIndex = 21,
				Parent = list,
			})
			local t = label(tostring(opt), 12, tostring(obj[key]) == tostring(opt) and THEME.accent or THEME.text, btn)
			t.Size = UDim2.new(1, -16, 1, 0)
			t.Position = UDim2.new(0, 10, 0, 0)
			t.ZIndex = 21
			btn.MouseEnter:Connect(function() btn.BackgroundColor3 = THEME.rowHover end)
			btn.MouseLeave:Connect(function() btn.BackgroundColor3 = THEME.panel end)
			btn.MouseButton1Click:Connect(function()
				obj[key] = opt
				valueLbl.Text = tostring(opt)
				list:Destroy()
				openDropdown = nil
				if onChange then pcall(onChange) end
			end)
		end
	end)

	refreshers[#refreshers + 1] = function() valueLbl.Text = tostring(obj[key]) end
	markSort(parent)
	return row
end

-- ── text input row ────────────────────────────────────────────────────────
function UI.input(parent, text, obj, key, onChange)
	local row = new("Frame", {
		BackgroundColor3 = THEME.row,
		Size = UDim2.new(1, 0, 0, ROW_H),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	corner(5, row)
	local lbl = label(text, 12, THEME.text, row)
	lbl.Size = UDim2.new(0.4, -10, 1, 0)
	lbl.Position = UDim2.new(0, 10, 0, 0)

	local box = new("TextBox", {
		Text = tostring(obj[key] or ""),
		PlaceholderText = "comma separated",
		BackgroundColor3 = THEME.input,
		Font = FONT_SMALL,
		TextSize = 11,
		TextColor3 = THEME.text,
		PlaceholderColor3 = THEME.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Size = UDim2.new(0.6, -10, 0, ROW_H - 8),
		Position = UDim2.new(0.4, 0, 0, 4),
		Parent = row,
	})
	corner(4, box)
	pad(4, box)

	local function commit()
		local list = {}
		for part in string.gmatch(box.Text, "[^,]+") do
			local trimmed = part:match("^%s*(.-)%s*$")
			if trimmed ~= "" then list[#list + 1] = trimmed end
		end
		local target = obj[key]
		if type(target) == "table" then
			for i = #target, 1, -1 do target[i] = nil end
			for i = 1, #list do target[i] = list[i] end
		else
			obj[key] = list
		end
		if onChange then pcall(onChange) end
	end

	box.FocusLost:Connect(commit)
	refreshers[#refreshers + 1] = function()
		if not box:IsFocused() then
			local t = obj[key]
			if type(t) == "table" then box.Text = table.concat(t, ", ") end
		end
	end
	markSort(parent)
	return row
end

-- ── color picker (swatch + HSV + hex) ─────────────────────────────────────
local picker = nil

local function colorToHsv(c)
	return Color3.toHSV(c)
end

local function hsvToColor(h, s, v)
	return Color3.fromHSV(clamp(h, 0, 1), clamp(s, 0, 1), clamp(v, 0, 1))
end

local buildPicker

function UI.color(parent, text, obj)
	local colorFn = function() return rgb(obj.color) end
	local row = new("TextButton", {
		Name = "Color_" .. text,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.row,
		Size = UDim2.new(1, 0, 0, ROW_H),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	corner(5, row)

	local lbl = label(text, 12, THEME.text, row)
	lbl.Size = UDim2.new(1, -60, 1, 0)
	lbl.Position = UDim2.new(0, 10, 0, 0)

	local swatch = new("Frame", {
		BackgroundColor3 = colorFn(),
		Size = UDim2.fromOffset(38, 16),
		Position = UDim2.new(1, -48, 0.5, -8),
		Parent = row,
	})
	corner(4, swatch)
	stroke(THEME.stroke, 1, swatch)

	row.MouseEnter:Connect(function() row.BackgroundColor3 = THEME.rowHover end)
	row.MouseLeave:Connect(function() row.BackgroundColor3 = THEME.row end)
	row.MouseButton1Click:Connect(function()
		if picker and picker.target == obj then
			picker.frame:Destroy()
			picker = nil
			return
		end
		if picker then picker.frame:Destroy() picker = nil end

		local built, buildErr = xpcall(function() buildPicker(row, obj, swatch) end,
			function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end)
		if not built then
			warn("[ESP] colour picker failed: " .. tostring(buildErr))
		end
	end)

	refreshers[#refreshers + 1] = function() swatch.BackgroundColor3 = colorFn() end
	markSort(parent)
	return row
end

-- builds the picker panel; isolated so a failure can never leave a
-- half-built panel behind (the caller runs it through pcall)
function buildPicker(row, obj, swatch)
	local frame = new("Frame", {
			Name = "ColorPicker",
			BackgroundColor3 = THEME.panel,
			Size = UDim2.fromOffset(MENU_W - 2 * PAD - 20, 168),
			Position = UDim2.new(0, 8, 1, 4),
			ZIndex = 20,
			Parent = row,
		})
		corner(6, frame)
		stroke(THEME.stroke, 1, frame)

		local h, s, v = colorToHsv(rgb(obj.color))
		local hexBox, svBox          -- assigned below, referenced by redraw()
		local swatchPreview = new("Frame", {
			BackgroundColor3 = rgb(obj.color),
			Size = UDim2.new(1, -20, 0, 26),
			Position = UDim2.new(0, 10, 0, 8),
			ZIndex = 21,
			Parent = frame,
		})
		corner(4, swatchPreview)

		local function redraw()
			local c = hsvToColor(h, s, v)
			obj.color = { round(c.R * 255), round(c.G * 255), round(c.B * 255) }
			swatch.BackgroundColor3 = c
			swatchPreview.BackgroundColor3 = c
			svBox.BackgroundColor3 = hsvToColor(h, 1, 1)
			hexBox.Text = hexOf(obj.color)
		end

		-- hue strip -------------------------------------------------------
		local hueBar = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, -20, 0, 12),
			Position = UDim2.new(0, 10, 0, 42),
			ZIndex = 21,
			Parent = frame,
		})
		corner(3, hueBar)
		local hueGrad = new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
			}),
			Parent = hueBar,
		})
		local hueKnob = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(4, 16),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(h, 0, 0.5, 0),
			ZIndex = 22,
			Parent = hueBar,
		})
		corner(2, hueKnob)

		local function setHue(x)
			local w = math.max(hueBar.AbsoluteSize.X, 1)
			h = clamp((x - hueBar.AbsolutePosition.X) / w, 0, 1)
			hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
			redraw()
		end

		local hueDrag = false
		hueBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				hueDrag = true
				setHue(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if hueDrag and input.UserInputType == Enum.UserInputType.MouseMovement then
				setHue(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then hueDrag = false end
		end)

		-- saturation / value square --------------------------------------
		-- base = pure hue, white layer = saturation, black layer = value
		svBox = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = hsvToColor(h, 1, 1),
			Size = UDim2.new(1, -20, 0, 52),
			Position = UDim2.new(0, 10, 0, 62),
			ClipsDescendants = true,
			ZIndex = 21,
			Parent = frame,
		})
		corner(3, svBox)

		local whiteLayer = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 21,
			Parent = svBox,
		})
		new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = whiteLayer,
		})

		local blackLayer = new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 21,
			Parent = svBox,
		})
		new("UIGradient", {
			Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Rotation = 90,
			Parent = blackLayer,
		})

		local svKnob = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(7, 7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(s, 1 - v),
			ZIndex = 22,
			Parent = svBox,
		})
		corner(4, svKnob)
		stroke(Color3.new(0, 0, 0), 1, svKnob)

		local function setSV(x, y)
			local abs, size = svBox.AbsolutePosition, svBox.AbsoluteSize
			s = clamp((x - abs.X) / math.max(size.X, 1), 0, 1)
			v = 1 - clamp((y - abs.Y) / math.max(size.Y, 1), 0, 1)
			svKnob.Position = UDim2.fromScale(s, 1 - v)
			redraw()
		end

		local svDrag = false
		svBox.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				svDrag = true
				setSV(input.Position.X, input.Position.Y)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if svDrag and input.UserInputType == Enum.UserInputType.MouseMovement then
				setSV(input.Position.X, input.Position.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then svDrag = false end
		end)

		-- hex field -------------------------------------------------------
		hexBox = new("TextBox", {
			Text = hexOf(obj.color),
			BackgroundColor3 = THEME.input,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = THEME.text,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -20, 0, 22),
			Position = UDim2.new(0, 10, 0, 122),
			ZIndex = 21,
			Parent = frame,
		})
		corner(4, hexBox)
		hexBox.FocusLost:Connect(function()
			local parsed = parseHex(hexBox.Text)
			if parsed then
				obj.color = parsed
				local hh, ss, vv = colorToHsv(rgb(parsed))
				h, s, v = hh, ss, vv
				swatch.BackgroundColor3 = rgb(parsed)
				swatchPreview.BackgroundColor3 = rgb(parsed)
				svBox.BackgroundColor3 = hsvToColor(h, 1, 1)
				hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
				svKnob.Position = UDim2.fromScale(s, 1 - v)
				end
			hexBox.Text = hexOf(obj.color)
		end)

		picker = { frame = frame, target = obj }

		-- live ticker so the swatch reflects external config edits
		local tick = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if picker ~= nil and picker.frame == frame and frame.Parent then
				tick = tick + dt
				if tick > 0.25 then
					tick = 0
					local c = rgb(obj.color)
					if swatch.BackgroundColor3 ~= c then
						swatch.BackgroundColor3 = c
						local hh, ss, vv = colorToHsv(c)
						h, s, v = hh, ss, vv
						svBox.BackgroundColor3 = hsvToColor(h, 1, 1)
						hexBox.Text = hexOf(obj.color)
						hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
						svKnob.Position = UDim2.fromScale(s, 1 - v)
					end
				end
			else
				conn:Disconnect()
			end
		end)
end

-- ── misc row builders ─────────────────────────────────────────────────────
function UI.note(parent, text)
	local holder = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	local l = label(text, 10, THEME.muted, holder)
	l.Size = UDim2.fromScale(1, 1)
	l.TextWrapped = true
	l.Position = UDim2.new(0, 2, 0, 0)
	markSort(parent)
	return holder
end

function UI.section(parent, text)
	local holder = new("Frame", {
		BackgroundColor3 = THEME.panel,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	corner(4, holder)
	local l = label(text, 11, THEME.accent, holder, true)
	l.Size = UDim2.new(1, -12, 1, 0)
	l.Position = UDim2.new(0, 8, 0, 0)
	markSort(parent)
	return holder
end

function UI.button(parent, text, color, onClick)
	local btn = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.row,
		Size = UDim2.new(1, 0, 0, ROW_H),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	})
	corner(5, btn)
	local l = label(text, 12, color or THEME.text, btn, true)
	l.Size = UDim2.fromScale(1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Center
	btn.MouseEnter:Connect(function() btn.BackgroundColor3 = THEME.rowHover end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = THEME.row end)
	btn.MouseButton1Click:Connect(function() pcall(onClick) end)
	markSort(parent)
	return btn
end

-- ══════════════════════════════════════════════════════════════════════════
--  MAIN WINDOW
-- ══════════════════════════════════════════════════════════════════════════

local function buildCategoryPage(parent, catKey, opts)
	local cat = CFG[catKey]

	UI.toggle(parent, "Category enabled", cat, "enabled")

	-- distance limit --------------------------------------------------------
	-- the render loop re-reads maxDistance every frame, so the slider needs
	-- no callback: dragging it applies instantly
	UI.slider(parent, "Max distance", cat, "maxDistance", 10, 3000, 10, " studs")
	UI.toggle(parent, "Unlimited distance", cat, "unlimited", function()
		if cat.unlimited then
			-- visually push the slider to max so the state is obvious
			cat.maxDistance = 3000
			refreshUI()
		end
	end)

	UI.section(parent, "Colours")

	UI.section(parent, "Chams")
	UI.toggle(parent, "Chams", cat.chams, "on")
	UI.color(parent, "Cham colour", cat.chams)
	UI.slider(parent, "Fill opacity", cat.chams, "fill", 0, 100, 1, "%")
	UI.slider(parent, "Outline opacity", cat.chams, "outline", 0, 100, 1, "%")
	UI.toggle(parent, "Through walls", cat.chams, "throughWalls")

	UI.section(parent, "Box")
	UI.toggle(parent, "Box", cat.box, "on")
	UI.color(parent, "Box colour", cat.box)
	UI.dropdown(parent, "Style", cat.box, "mode", { "Corners", "Full" })
	UI.slider(parent, "Corner length", cat.box, "corner", 5, 100, 5, "%")
	UI.slider(parent, "Box thickness", cat.box, "thickness", 1, 6, 1, "px")
	UI.slider(parent, "Box opacity", cat.box, "alpha", 0, 100, 1, "%")
	UI.note(parent, "Corner length 100% = full frame")

	UI.section(parent, "Fill")
	UI.toggle(parent, "Box fill", cat.fill, "on")
	UI.color(parent, "Fill colour", cat.fill)
	UI.slider(parent, "Fill opacity", cat.fill, "alpha", 0, 100, 1, "%")

	-- character-only features ----------------------------------------------
	if opts.character then
		UI.section(parent, "Skeleton")
		UI.toggle(parent, "Skeleton", cat.skeleton, "on")
		UI.color(parent, "Bone colour", cat.skeleton)
		UI.slider(parent, "Skeleton opacity", cat.skeleton, "alpha", 0, 100, 1, "%")
		UI.slider(parent, "Bone thickness", cat.skeleton, "thickness", 1, 5, 1, "px")
		UI.toggle(parent, "Health tint", cat.skeleton, "healthTint")

		UI.section(parent, "Health")
		UI.toggle(parent, "Health bar", cat.healthBar, "on")
		UI.color(parent, "Bar colour", cat.healthBar)
		UI.slider(parent, "Bar opacity", cat.healthBar, "alpha", 0, 100, 1, "%")
		UI.slider(parent, "Bar width", cat.healthBar, "width", 1, 8, 1, "px")
		UI.toggle(parent, "Colour by health", cat.healthBar, "tint")
		UI.toggle(parent, "Health number", cat.healthText, "on")
		UI.color(parent, "Number colour", cat.healthText)
		UI.toggle(parent, "Number health tint", cat.healthText, "tint")

		UI.section(parent, "Text")
		UI.toggle(parent, "Name", cat.name, "on")
		UI.color(parent, "Name colour", cat.name)
		UI.slider(parent, "Name size", cat.name, "size", 8, 32, 1, "px")
		UI.slider(parent, "Name opacity", cat.name, "alpha", 0, 100, 1, "%")
		UI.toggle(parent, "Name health tint", cat.name, "healthTint")

		UI.toggle(parent, "Distance", cat.distance, "on")
		UI.color(parent, "Distance colour", cat.distance)
		UI.slider(parent, "Distance opacity", cat.distance, "alpha", 0, 100, 1, "%")
		UI.toggle(parent, "Show in metres", cat.distance, "meters")

		UI.toggle(parent, "Weapon", cat.weapon, "on")
		UI.color(parent, "Weapon colour", cat.weapon)
		UI.slider(parent, "Weapon opacity", cat.weapon, "alpha", 0, 100, 1, "%")
		UI.toggle(parent, "Hide when unarmed", cat.weapon, "hideUnarmed")

		UI.section(parent, "Markers")
		UI.toggle(parent, "Head dot", cat.headDot, "on")
		UI.color(parent, "Head dot colour", cat.headDot)
		UI.slider(parent, "Head dot size", cat.headDot, "size", 2, 12, 1, "px")

		UI.toggle(parent, "Tracer", cat.tracer, "on")
		UI.color(parent, "Tracer colour", cat.tracer)
		UI.slider(parent, "Tracer opacity", cat.tracer, "alpha", 0, 100, 1, "%")
		UI.slider(parent, "Tracer thickness", cat.tracer, "thickness", 1, 4, 1, "px")
		UI.dropdown(parent, "Tracer origin", cat.tracer, "origin", { "Bottom", "Top", "Left", "Right", "Center", "Mouse" })
	else
		UI.section(parent, "Text")
		UI.toggle(parent, "Name", cat.name, "on")
		UI.color(parent, "Name colour", cat.name)
		UI.slider(parent, "Name size", cat.name, "size", 8, 32, 1, "px")
		UI.slider(parent, "Name opacity", cat.name, "alpha", 0, 100, 1, "%")

		UI.toggle(parent, "Distance", cat.distance, "on")
		UI.color(parent, "Distance colour", cat.distance)
		UI.toggle(parent, "Show in metres", cat.distance, "meters")

		UI.section(parent, "Markers")
		UI.toggle(parent, "Tracer", cat.tracer, "on")
		UI.color(parent, "Tracer colour", cat.tracer)
		UI.slider(parent, "Tracer opacity", cat.tracer, "alpha", 0, 100, 1, "%")
		UI.slider(parent, "Tracer thickness", cat.tracer, "thickness", 1, 4, 1, "px")
		UI.dropdown(parent, "Tracer origin", cat.tracer, "origin", { "Bottom", "Top", "Left", "Right", "Center", "Mouse" })
	end
end

local function buildFiltersPage(parent)
	UI.section(parent, "NPC filter")
	UI.dropdown(parent, "Mode", CFG.filters, "npcMode", { "Whitelist", "Blacklist", "All" }, onFiltersChanged)
	UI.input(parent, "Names", CFG.filters, "npcList", onFiltersChanged)
	UI.note(parent, "Comma separated, * works as a wildcard")

	UI.section(parent, "Node filter")
	UI.dropdown(parent, "Mode", CFG.filters, "nodeMode", { "Whitelist", "Blacklist" }, onFiltersChanged)
	UI.input(parent, "Names", CFG.filters, "nodeList", onFiltersChanged)
	UI.note(parent, "Whitelist: only these names. Blacklist: everything else")

	UI.section(parent, "Toggles")
	UI.toggle(parent, "Ignore dead", CFG.filters, "ignoreDead")
	UI.toggle(parent, "Team check", CFG.filters, "teamCheck")
	UI.toggle(parent, "Show yourself", CFG.filters, "showLocal")
	UI.slider(parent, "Max tracked nodes", CFG.filters, "maxTrackedNodes", 25, 2000, 25, "")

	UI.section(parent, "Actions")
	UI.button(parent, "Apply filters / rescan", THEME.accent, function()
		onFiltersChanged()
	end)
	UI.button(parent, "Clear all targets", THEME.warn, function()
		untrackAll()
		fullScan()
	end)
	UI.button(parent, "Unload script", THEME.bad, function()
		if _G.ESP_Suite and _G.ESP_Suite.unload then _G.ESP_Suite.unload() end
	end)
end

local function buildSettingsPage(parent)
	UI.section(parent, "Units & scale")
	UI.slider(parent, "Studs per metre", CFG.misc, "studsPerMeter", 1, 10, 0.001, "", function()
		CFG.misc.studsPerMeter = clamp(CFG.misc.studsPerMeter, 0.1, 100)
	end)
	UI.slider(parent, "Box scale", CFG.misc, "boxScale", 50, 200, 5, "%")
	UI.slider(parent, "Render budget", CFG.misc, "maxObjects", 20, 500, 10, " objs")
	UI.slider(parent, "Rescan interval", CFG.misc, "rescanEvery", 2, 60, 1, " s")

	UI.section(parent, "Menu")
	UI.toggle(parent, "Show pill button", CFG.menu, "showButton")
	UI.button(parent, "Toggle menu (RightShift)", THEME.accent, function()
		UI.toggleMenu()
	end)
	UI.button(parent, "Save to file", THEME.accent, function()
		local ok = saveConfig()
		if ok then
			print("[ESP] settings saved to " .. CONFIG_FILE)
		else
			warn("[ESP] this executor has no writefile/readfile support")
		end
	end)
	UI.button(parent, "Load from file", THEME.accent, function()
		if not loadConfig() then
			warn("[ESP] no saved settings found")
		end
	end)
	UI.button(parent, "Reset all settings", THEME.warn, function()
		mergeInto(CFG, deepcopy(DEFAULTS))
		sanitize()
		rebuildFilters()
		untrackAll()
		fullScan()
		refreshUI()
	end)

	UI.section(parent, "Status")
	local statusText = label("", 11, THEME.muted, new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = #parent:GetChildren() * 10,
		Parent = parent,
	}))
	statusText.Size = UDim2.fromScale(1, 1)
	statusText.TextWrapped = true
	statusText.Position = UDim2.new(0, 2, 0, 0)
	refreshers[#refreshers + 1] = function()
		statusText.Text = string.format(
			"ESP %s  ·  drawing %s\n%d players · %d npcs · %d nodes",
			VERSION,
			DRAWING_OK and "ok" or "unavailable",
			trackedCount.player or 0, trackedCount.npc or 0, trackedCount.node or 0
		)
	end
end

-- ══════════════════════════════════════════════════════════════════════════
--  ASSEMBLE THE WINDOW
-- ══════════════════════════════════════════════════════════════════════════

local menu = nil
local pill = nil
local menuOpen = false

local function buildMenu()
	if not screen then return end

	menu = new("Frame", {
		Name = "ESP_Menu",
		BackgroundColor3 = THEME.bg,
		Size = UDim2.fromOffset(MENU_W, MENU_H),
		Position = UDim2.fromOffset(CFG.menu.x or 60, CFG.menu.y or 60),
		Active = true,
		ClipsDescendants = true,
		BorderSizePixel = 0,
		Parent = screen,
	})
	corner(10, menu)
	stroke(Color3.fromRGB(48, 52, 64), 1, menu)

	local glow = new("UIStroke", {
		Color = THEME.accent,
		Thickness = 1,
		Transparency = 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = menu,
	})

	-- title bar -------------------------------------------------------------
	local bar = new("Frame", {
		Name = "TitleBar",
		BackgroundColor3 = THEME.panel,
		Size = UDim2.new(1, 0, 0, 34),
		Active = true,
		Parent = menu,
	})
	corner(10, bar)
	new("Frame", { -- square off the bottom corners of the title bar
		BackgroundColor3 = THEME.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -10),
		Parent = bar,
	})

	local title = label("ESP SUITE", 13, THEME.text, bar, true)
	title.Size = UDim2.new(0.6, 0, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)

	local sub = label("v" .. VERSION, 10, THEME.muted, bar)
	sub.Size = UDim2.new(0.4, -40, 1, 0)
	sub.Position = UDim2.new(0.6, 0, 0, 0)
	sub.TextXAlignment = Enum.TextXAlignment.Right

	local close = new("TextButton", {
		Text = "×",
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 18,
		TextColor3 = THEME.muted,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -34, 0, 2),
		Parent = bar,
	})
	close.MouseEnter:Connect(function() close.TextColor3 = THEME.bad end)
	close.MouseLeave:Connect(function() close.TextColor3 = THEME.muted end)
	close.MouseButton1Click:Connect(function()
		UI.setMenuOpen(false)
	end)

	-- dragging --------------------------------------------------------------
	local dragging, dragStart, startPos = false, nil, nil
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = menu.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			local pos = UDim2.fromOffset(
				math.max(0, startPos.X.Offset + delta.X),
				math.max(0, startPos.Y.Offset + delta.Y)
			)
			menu.Position = pos
			CFG.menu.x = pos.X.Offset
			CFG.menu.y = pos.Y.Offset
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)

	-- tab bar ---------------------------------------------------------------
	local tabBar = new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = THEME.panel,
		Size = UDim2.new(1, 0, 0, TAB_H + 8),
		Position = UDim2.new(0, 0, 0, 34),
		Parent = menu,
	})
	local tabLayout = new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = tabBar,
	})
	pad(4, tabBar)

	-- pages -----------------------------------------------------------------
	local pageHolder = new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -2 * PAD, 1, -(34 + TAB_H + 8) - PAD),
		Position = UDim2.new(0, PAD, 0, 34 + TAB_H + 8),
		Parent = menu,
	})

	local tabDefs = {
		{ name = "Players", build = function(p) buildCategoryPage(p, "players", { character = true }) end },
		{ name = "NPCs", build = function(p) buildCategoryPage(p, "npcs", { character = true }) end },
		{ name = "Nodes", build = function(p) buildCategoryPage(p, "nodes", { character = false }) end },
		{ name = "Filters", build = buildFiltersPage },
		{ name = "Settings", build = buildSettingsPage },
	}

	for i, def in ipairs(tabDefs) do
		local btn = new("TextButton", {
			Text = def.name,
			AutoButtonColor = false,
			BackgroundColor3 = THEME.bg,
			Font = FONT,
			TextSize = 11,
			TextColor3 = THEME.muted,
			Size = UDim2.new(1 / #tabDefs, -4, 0, TAB_H),
			LayoutOrder = i,
			Parent = tabBar,
		})
		corner(5, btn)

		local page = new("ScrollingFrame", {
			Name = def.name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = THEME.stroke,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = false,
			Parent = pageHolder,
		})
		listLayout(page, ROW_GAP)
		pad(0, page)
		page.UIListLayout.Padding = UDim.new(0, ROW_GAP)

		local ok, err = pcall(def.build, page)
		if not ok then
			warn("[ESP] failed to build tab " .. def.name .. ": " .. tostring(err))
		end

		btn.MouseButton1Click:Connect(function()
			for _, other in ipairs(pageHolder:GetChildren()) do
				if other:IsA("ScrollingFrame") then other.Visible = false end
			end
			for _, other in ipairs(tabBar:GetChildren()) do
				if other:IsA("TextButton") then
					other.BackgroundColor3 = THEME.bg
					other.TextColor3 = THEME.muted
				end
			end
			page.Visible = true
			btn.BackgroundColor3 = THEME.row
			btn.TextColor3 = THEME.accent
			activeTab = page
			markSort(page)
		end)

		tabs[#tabs + 1] = { button = btn, page = page, name = def.name }
	end

	if tabs[1] then
		tabs[1].button.BackgroundColor3 = THEME.row
		tabs[1].button.TextColor3 = THEME.accent
		tabs[1].page.Visible = true
		activeTab = tabs[1].page
	end

	-- footer ----------------------------------------------------------------
	local footer = label("RightShift toggles the menu", 10, THEME.muted, menu)
	footer.Size = UDim2.new(1, -20, 0, 14)
	footer.Position = UDim2.new(0, PAD, 1, -16)

	menuOpen = true
end

local function buildPill()
	if not screen then return end

	pill = new("TextButton", {
		Name = "ESP_Pill",
		Text = "ESP",
		AutoButtonColor = false,
		BackgroundColor3 = THEME.panel,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = THEME.accent,
		Size = UDim2.fromOffset(44, 24),
		Position = UDim2.new(0, 60, 0, 60 + MENU_H + 10),
		Visible = CFG.menu.showButton,
		Parent = screen,
	})
	corner(6, pill)
	stroke(THEME.accent, 1, pill)
	pill.MouseButton1Click:Connect(function()
		UI.toggleMenu()
	end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  MENU VISIBILITY / KEYBIND
-- ══════════════════════════════════════════════════════════════════════════

function UI.setMenuOpen(open)
	menuOpen = open
	if menu then
		menu.Visible = open
	end
	if pill then
		pill.Visible = CFG.menu.showButton
		pill.Position = open and UDim2.new(0, 60, 0, 60 + MENU_H + 10) or UDim2.new(0, 60, 0, 60)
	end
end

function UI.toggleMenu()
	UI.setMenuOpen(not menuOpen)
end

if screen then
	buildMenu()
	buildPill()
	UI.setMenuOpen(CFG.menu.open ~= false)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		local key = input.KeyCode
		if key == Enum.KeyCode.RightShift then
			UI.toggleMenu()
		elseif key == Enum.KeyCode.RightControl or key == Enum.KeyCode.Delete then
			UI.setMenuOpen(false)
		end
	end)

	-- the pill follows the showButton toggle
	refreshers[#refreshers + 1] = function()
		if pill then pill.Visible = CFG.menu.showButton end
	end

	task.spawn(function()
		while menu and menu.Parent do
			applySorts()
			refreshUI()
			waitFn(0.5)
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  PUBLIC API
-- ══════════════════════════════════════════════════════════════════════════

local function unload()
	renderEnabled = false

	if renderConn then pcall(function() renderConn:Disconnect() end) end
	for i = 1, #connections do pcall(function() connections[i]:Disconnect() end) end
	connections = {}

	untrackAll()

	if cleardrawcache then pcall(cleardrawcache) end
	if gui then pcall(function() gui:Destroy() end) end

	if _G.ESP_Suite == API then
		_G.ESP_Suite = nil
	end
	if _G.EspUnload == unload then
		_G.EspUnload = nil
	end
end

local function exportConfig()
	local ok, json = pcall(function()
		return HttpService:JSONEncode(CFG)
	end)
	if not ok then return nil end
	if setclipboard then pcall(setclipboard, json) end
	return json
end

local function importConfig(json)
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok or type(data) ~= "table" then return false end
	mergeInto(CFG, data)
	sanitize()
	rebuildFilters()
	refreshUI()
	return true
end

-- ── persistence (executor file APIs, both optional) ───────────────────────
local CONFIG_FILE = "esp_suite_config.json"

local function saveConfig()
	if type(writefile) ~= "function" or type(exportConfig) ~= "function" then return false end
	local json = exportConfig()
	if not json then return false end
	local ok = pcall(writefile, CONFIG_FILE, json)
	return ok
end

local function loadConfig()
	if type(isfile) ~= "function" or type(readfile) ~= "function" then return false end
	local exists = false
	pcall(function() exists = isfile(CONFIG_FILE) end)
	if not exists then return false end
	local ok, contents = pcall(readfile, CONFIG_FILE)
	if not ok or type(contents) ~= "string" then return false end
	return importConfig(contents)
end

local function setDistance(catKey, studs)
	local cat = CFG[catKey]
	if not cat then return end
	cat.maxDistance = clamp(tonumber(studs) or 400, 10, 3000)
end

local function setColor(catKey, feature, r, g, b)
	local cat = CFG[catKey]
	if not cat or not cat[feature] or not cat[feature].color then return end
	cat[feature].color = { r or 255, g or 255, b or 255 }
end

local API = {
	version = VERSION,
	config = CFG,
	defaults = DEFAULTS,
	theme = THEME,
	ui = UI,

	unload = unload,
	toggleMenu = function()
		UI.toggleMenu()
	end,
	setMenuOpen = function(open)
		UI.setMenuOpen(open ~= false)
	end,

	setDistance = setDistance,
	setColor = setColor,
	exportConfig = exportConfig,
	importConfig = importConfig,
	saveConfig = saveConfig,
	loadConfig = loadConfig,
	refreshUI = refreshUI,
	rescan = function()
		onFiltersChanged()
	end,

	tracked = function()
		return tracked
	end,
	counts = function()
		return shallowCopy(trackedCount)
	end,
}

_G.ESP_Suite = API
_G.EspUnload = unload

-- restore saved settings (silently ignored when the executor has no files)
if not loadConfig() then
	-- nothing saved yet, keep defaults
end

-- one automatic pass so the world is populated before the first frame ------
fullScan()

print(string.format("[ESP] v%s loaded — %d players, %d npcs, %d nodes tracked (RightShift = menu)",
	VERSION, trackedCount.player or 0, trackedCount.npc or 0, trackedCount.node or 0))
