-- ══════════════════════════════════════════════════════════════════════════
--  Headless test suite for ESP.lua
--  run: lua tests/run_tests.lua      (from the repo root)
-- ══════════════════════════════════════════════════════════════════════════

package.path = "./tests/?.lua;" .. package.path
local Mock = dofile("tests/roblox_mock.lua")
Mock.installGlobals()

local passed, failed = 0, 0

local function check(name, cond, extra)
	if cond then
		passed = passed + 1
		print("  ok   " .. name)
	else
		failed = failed + 1
		print("  FAIL " .. name .. (extra and ("  -> " .. tostring(extra)) or ""))
	end
end

local function section(name)
	print("\n== " .. name .. " ==")
end

-- load the script under test -------------------------------------------------
local function loadEsp()
	local chunk, err = loadfile("ESP.lua")
	if not chunk then
		print("compile error: " .. tostring(err))
		os.exit(1)
	end
	local ok, runErr = pcall(chunk)
	if not ok then
		print("runtime error: " .. tostring(runErr))
		os.exit(1)
	end
	return _G.ESP_Suite
end

-- ── world setup ───────────────────────────────────────────────────────────
Mock.addPlayer("Enemy1", Vector3.new(0, 0, -50), "R15", 100)
Mock.addPlayer("Enemy2", Vector3.new(20, 0, -80), "R6", 45)
Mock.spawnNpc("Guard", Vector3.new(-30, 0, -60), "R15", 100)
Mock.spawnNpc("Scavenger", Vector3.new(10, 0, -40), "R15", 70)
Mock.spawnNpc("NotFiltered", Vector3.new(0, 0, -30), "R15", 100)
Mock.spawnNode("MetalNode", Vector3.new(5, 0, -25))
Mock.spawnNode("Tree", Vector3.new(-5, 0, -35))
Mock.spawnNode("RandomPart", Vector3.new(0, 0, -20))

-- ── tests ─────────────────────────────────────────────────────────────────
section("load")
local ESP = loadEsp()
check("script loads without erroring", ESP ~= nil)
check("no errors during load", #Mock.errors == 0, table.concat(Mock.errors, " | "))

section("tracking")
local counts = ESP.counts()
check("2 players tracked", counts.player == 2, counts.player)
check("only whitelisted npcs tracked (2)", counts.npc == 2, counts.npc)
check("only whitelisted nodes tracked (2)", counts.node == 2, counts.node)
local tracked = ESP.tracked()
local hasUnfiltered = false
for inst in pairs(tracked) do
	if inst.Name == "NotFiltered" or inst.Name == "RandomPart" then hasUnfiltered = true end
end
check("unlisted npc/node not tracked", not hasUnfiltered)

section("chams")
local function highlightFor(modelName)
	local inst = nil
	for i in pairs(tracked) do
		if i.Name == modelName then inst = i end
	end
	if not inst then return nil end
	for _, c in ipairs(inst._children) do
		if c.ClassName == "Highlight" then return c end
	end
	return nil
end
Mock.stepRender(2)   -- highlights are attached lazily by the render pass
local hl = highlightFor("Enemy1")
check("player highlight created", hl ~= nil)
check("highlight adornes the character", hl ~= nil and hl.Adornee ~= nil)
check("highlight colour follows config",
	hl and math.abs(hl.FillColor.R - 120 / 255) < 0.01, hl and tostring(hl.FillColor))
check("npc highlight colour follows config", (function()
	local h = highlightFor("Guard")
	return h and math.abs(h.FillColor.R - 1) < 0.01 and math.abs(h.FillColor.G - 80 / 255) < 0.01
end)())

section("re-enabled chams")
-- NOTE: do not reset the drawing counters here, the ESP keeps using the
-- objects it already allocated.

section("box rendering")
check("box lines visible for on-screen players", Mock.countVisible("Line") > 0, Mock.countVisible("Line"))

local function lineCount()
	return Mock.countVisible("Line")
end

local before = lineCount()
ESP.config.players.box.on = false
Mock.stepRender(2)
local afterHide = lineCount()
check("box toggle hides player box lines", afterHide < before, before .. " -> " .. afterHide)
ESP.config.players.box.on = true
Mock.stepRender(2)
check("box toggle restores lines", lineCount() >= afterHide)

section("distance limit")
local lineBefore = lineCount()
ESP.config.players.maxDistance = 10      -- every enemy is >= 50 studs away
Mock.stepRender(2)
local lineFar = lineCount()
check("distance slider limits far players", lineFar < lineBefore, lineBefore .. " -> " .. lineFar)

ESP.config.players.maxDistance = 400
Mock.stepRender(2)
check("distance slider restores players", lineCount() > lineFar)

section("colour customisation")
ESP.config.players.box.color = { 255, 0, 0 }
Mock.stepRender(2)
local foundRed = false
for _, o in ipairs(Mock.drawingObjects) do
	if o.ClassName == "Line" and o.Visible and math.abs(o.Color.R - 1) < 0.001 and o.Color.G < 0.001 then
		foundRed = true
	end
end
check("box colour applies to drawn lines", foundRed)

ESP.config.players.chams.color = { 0, 255, 0 }
Mock.stepRender(2)
local g = highlightFor("Enemy1")
check("chams colour applies live", g and g.FillColor.G > 0.99 and g.FillColor.R < 0.01, g and tostring(g.FillColor))

section("skeleton")
local function boneLinesVisible()
	local c = 0
	for _, o in ipairs(Mock.drawingObjects) do
		if o.ClassName == "Line" and o.Visible then c = c + 1 end
	end
	return c
end
ESP.config.players.box.on = false
ESP.config.players.fill.on = false
ESP.config.players.tracer.on = false
ESP.config.players.name.on = false
ESP.config.players.distance.on = false
ESP.config.players.weapon.on = false
ESP.config.players.healthBar.on = false
ESP.config.players.headDot.on = false
Mock.stepRender(2)
local skelOnly = boneLinesVisible()
check("skeleton draws lines on its own", skelOnly > 0, skelOnly)
check("R15 produces 14 bone lines", skelOnly >= 14, skelOnly)

local function playerSkeletonVisible()
	local n = 0
	for inst, esp in pairs(ESP.tracked()) do
		if esp.kind == "player" then
			for i = 1, #esp.skeleton do
				if esp.skeleton[i] and esp.skeleton[i].Visible then n = n + 1 end
			end
		end
	end
	return n
end
check("player skeleton visible", playerSkeletonVisible() > 0, playerSkeletonVisible())
ESP.config.players.skeleton.on = false
Mock.stepRender(2)
check("skeleton toggle hides player bones", playerSkeletonVisible() == 0, playerSkeletonVisible())
ESP.config.players.skeleton.on = true
Mock.stepRender(2)

-- restore defaults for later checks
ESP.config.players.box.on = true
ESP.config.players.name.on = true
ESP.config.players.distance.on = true
ESP.config.players.healthBar.on = true
ESP.config.players.weapon.on = true

section("health + text")
ESP.config.players.healthBar.on = true
Mock.stepRender(2)
local fg = 0
for _, o in ipairs(Mock.drawingObjects) do
	if o.ClassName == "Square" and o.Visible then fg = fg + 1 end
end
check("health bar squares drawn", fg > 0, fg)

ESP.config.players.name.on = true
ESP.config.players.distance.on = true
Mock.stepRender(2)
local texts = {}
for _, o in ipairs(Mock.drawingObjects) do
	if o.ClassName == "Text" and o.Visible then texts[o.Text] = true end
end
check("player name rendered", texts["Enemy1"] == true)
check("distance rendered", (function()
	for t in pairs(texts) do
		if t:match("^%d+s$") then return true end
	end
	return false
end)())

section("nodes")
Mock.stepRender(2)
local nodeText = false
for _, o in ipairs(Mock.drawingObjects) do
	if o.ClassName == "Text" and o.Visible and (o.Text == "MetalNode" or o.Text == "Tree") then nodeText = true end
end
check("node names rendered", nodeText)

ESP.config.nodes.enabled = false
Mock.stepRender(2)
local nodeText2 = false
for _, o in ipairs(Mock.drawingObjects) do
	if o.ClassName == "Text" and o.Visible and (o.Text == "MetalNode" or o.Text == "Tree") then nodeText2 = true end
end
check("nodes category toggle hides nodes", not nodeText2)
ESP.config.nodes.enabled = true

section("menu")
local gui = nil
for _, svc in ipairs({ game:GetService("CoreGui"), game:GetService("Players"):FindFirstChild("PlayerGui") }) do
	if svc then
		for _, c in ipairs(svc._children) do
			if tostring(c.Name):match("^ESP_Suite_") then gui = c end
		end
	end
end
check("ScreenGui created", gui ~= nil)

if gui then
	local root = gui:FindFirstChild("Root")
	check("menu root exists", root ~= nil)
	local menu = root and root:FindFirstChild("ESP_Menu")
	check("menu frame built", menu ~= nil)
	local tabButtons = 0
	if menu then
		for _, c in ipairs(menu:FindFirstChild("Tabs")._children) do
			if c.ClassName == "TextButton" then tabButtons = tabButtons + 1 end
		end
	end
	check("menu has 5 tabs", tabButtons == 5, tabButtons)
	local pages = menu and menu:FindFirstChild("Pages")
	pagesRoot = pages
	menuRoot = menu
	local count = 0
	for _, p in ipairs(pages._children) do
		if p.ClassName == "ScrollingFrame" then count = count + 1 end
	end
	check("5 pages built", count == 5, count)

	-- widgets exist on each page
	local function widgetCount(page)
		return #page._children
	end
	for _, p in ipairs(pages._children) do
		if p.ClassName == "ScrollingFrame" then
			check("page '" .. p.Name .. "' populated (" .. widgetCount(p) .. " widgets)", widgetCount(p) > 5)
		end
	end

	-- simulate clicking the first toggle on the Players page
	local playersPage = nil
	for _, p in ipairs(pages._children) do
		if p.Name == "Players" then playersPage = p end
	end
	if playersPage then
		local toggles = {}
		for _, c in ipairs(playersPage._children) do
			if c.ClassName == "TextButton" and tostring(c.Name):match("^Toggle_") then toggles[#toggles + 1] = c end
		end
		check("players page has toggles", #toggles > 5, #toggles)
		local first = toggles[1]
		local before = ESP.config.players.enabled
		first._events.MouseButton1Click:Fire()
		check("toggle click flips config", ESP.config.players.enabled ~= before,
			tostring(before) .. " -> " .. tostring(ESP.config.players.enabled))
		first._events.MouseButton1Click:Fire()
		-- the first toggle is "Category enabled" -> restore it
		ESP.config.players.enabled = true
		Mock.stepRender(2)
	end
end

section("colour picker")
local pages = pagesRoot
local playersPage2 = nil
for _, p in ipairs(pages._children) do
	if p.Name == "Players" then playersPage2 = p end
end
local colourRow = nil
for _, c in ipairs(playersPage2._children) do
	if tostring(c.Name) == "Color_Box colour" then colourRow = c end
end
check("colour row exists", colourRow ~= nil)
colourRow._events.MouseButton1Click:Fire()
local pickerFrame = nil
for _, c in ipairs(colourRow._children) do
	if c.Name == "ColorPicker" then pickerFrame = c end
end
check("picker opens", pickerFrame ~= nil)
if pickerFrame then
	local hexBox = nil
	for _, c in ipairs(pickerFrame._children) do
		if c.ClassName == "TextBox" then hexBox = c end
	end
	check("picker has hex field", hexBox ~= nil)
	if hexBox then
		hexBox.Text = "#00FF00"
		hexBox._events.FocusLost:Fire()
		check("hex edit writes the config",
			ESP.config.players.box.color[1] == 0 and ESP.config.players.box.color[2] == 255,
			table.concat(ESP.config.players.box.color, ","))
		Mock.stepRender(2)
		local green = false
		for _, o in ipairs(Mock.drawingObjects) do
			if o.ClassName == "Line" and o.Visible and o.Color.G > 0.99 and o.Color.R < 0.01 then green = true end
		end
		check("new colour reaches the renderer", green)
	end
	-- clicking the row again closes it
	colourRow._events.MouseButton1Click:Fire()
	local stillOpen = false
	for _, c in ipairs(colourRow._children) do
		if c.Name == "ColorPicker" then stillOpen = true end
	end
	check("clicking again closes the picker", not stillOpen)
end

section("dropdown")
local styleRow = nil
for _, c in ipairs(playersPage2._children) do
	if tostring(c.Name) == "Dropdown_Style" then styleRow = c end
end
check("style dropdown exists", styleRow ~= nil)
if styleRow then
	styleRow._events.MouseButton1Click:Fire()
	local opts = styleRow:FindFirstChild("Options")
	check("dropdown opens", opts ~= nil)
	if opts then
		local fullBtn = nil
		for _, c in ipairs(opts._children) do
			for _, t in ipairs(c._children) do
				if t.ClassName == "TextLabel" and t.Text == "Full" then fullBtn = c end
			end
		end
		check("dropdown lists options", fullBtn ~= nil)
		if fullBtn then
			fullBtn._events.MouseButton1Click:Fire()
			check("selecting an option writes the config", ESP.config.players.box.mode == "Full",
				tostring(ESP.config.players.box.mode))
		end
	end
end

section("api")
check("exportConfig returns a string", type(ESP.exportConfig()) == "string")
ESP.setDistance("players", 1234)
check("setDistance works", ESP.config.players.maxDistance == 1234, ESP.config.players.maxDistance)
ESP.setDistance("players", 99999)
check("setDistance clamps", ESP.config.players.maxDistance <= 3000, ESP.config.players.maxDistance)
ESP.setColor("players", "box", 10, 20, 30)
check("setColor works", ESP.config.players.box.color[1] == 10 and ESP.config.players.box.color[3] == 30)

section("config persistence")
local vfs = {}
writefile = function(path, contents) vfs[path] = contents end
readfile = function(path) return vfs[path] end
isfile = function(path) return vfs[path] ~= nil end

ESP.config.players.maxDistance = 777
ESP.config.players.box.color = { 1, 2, 3 }
ESP.config.filters.npcList = { "Alpha", "Beta" }
local savedOk = ESP.saveConfig()
check("saveConfig writes a file", savedOk == true and vfs["esp_suite_config.json"] ~= nil)
check("loadConfig restores settings", ESP.loadConfig() == true)

ESP.config.players.maxDistance = 400
ESP.config.players.box.color = { 120, 200, 255 }
ESP.config.filters.npcList = { "Guard" }
ESP.loadConfig()
check("distance restored from file", ESP.config.players.maxDistance == 777, ESP.config.players.maxDistance)
check("colour restored from file",
	ESP.config.players.box.color[1] == 1 and ESP.config.players.box.color[3] == 3,
	table.concat(ESP.config.players.box.color, ","))
check("lists replace (no leftovers)", #ESP.config.filters.npcList == 2,
	table.concat(ESP.config.filters.npcList, ","))

writefile, readfile, isfile = nil, nil, nil
check("saveConfig degrades without writefile", ESP.saveConfig() == false)

-- put the default filter lists back for the lifecycle tests below
ESP.config.filters.npcList = { "Guard", "Scavenger", "Soldier" }
ESP.config.filters.nodeList = { "MetalNode", "StoneNode", "SulfurNode", "Tree" }
ESP.rescan()

section("defaults reset")
ESP.config.players.enabled = false
ESP.config.nodes.maxDistance = 42
-- simulate reset button behaviour through the public import path
check("importConfig accepts the exported blob", ESP.importConfig(ESP.exportConfig()) == true)

section("player lifecycle")
local p3, c3 = Mock.addPlayer("Late", Vector3.new(0, 0, -100), "R15", 100)
Mock.playersService.PlayerAdded:Fire(p3)
Mock.runPending()
Mock.stepRender(2)
check("late player gets tracked", ESP.tracked()[c3] ~= nil, ESP.counts().player)

c3:Destroy()
Mock.playersService.PlayerRemoving:Fire(p3)
Mock.stepRender(2)
check("departed player untracked", ESP.tracked()[c3] == nil)

section("npc lifecycle")
local npc = Mock.spawnNpc("Soldier", Vector3.new(15, 0, -55), "R15", 100)
task.wait(0.2)
Mock.runPending()
Mock.stepRender(2)
check("spawned npc tracked via DescendantAdded", ESP.tracked()[npc] ~= nil)
npc:Destroy()
Mock.stepRender(2)
check("destroyed npc untracked", ESP.tracked()[npc] == nil)

section("filters live edit")
ESP.config.filters.nodeList = { "RandomPart" }
ESP.rescan()
Mock.stepRender(2)
local randomTracked = false
for inst in pairs(ESP.tracked()) do
	if inst.Name == "RandomPart" then randomTracked = true end
end
check("editing the node whitelist re-scans", randomTracked)
ESP.config.filters.nodeList = { "MetalNode", "StoneNode", "SulfurNode", "Tree" }
ESP.rescan()

section("unload")
ESP.unload()
Mock.stepRender(2)
check("no tracked instances after unload", next(ESP.tracked()) == nil)
local left = Mock.liveDrawings()
check("all drawing objects removed", left == 0, left)
check("no lingering highlights", (function()
	for _, inst in ipairs(Mock.workspace:GetDescendants()) do
		for _, c in ipairs(inst._children) do
			if c.ClassName == "Highlight" then return false end
		end
	end
	return true
end)())
check("menu destroyed", (function()
	for _, c in ipairs(game:GetService("CoreGui")._children) do
		if tostring(c.Name):match("^ESP_Suite_") then return false end
	end
	return true
end)())

section("runtime errors")
check("no signal/render errors during the run", #Mock.errors == 0,
	#Mock.errors > 0 and table.concat(Mock.errors, " | ") or "")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
