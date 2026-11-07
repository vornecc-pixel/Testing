-- ══════════════════════════════════════════════════════════════════════════
--  Minimal Roblox API mock — lets ESP.lua run headless for testing.
--  Not a faithful engine; just enough surface area for the script.
-- ══════════════════════════════════════════════════════════════════════════

local M = { errors = {}, drawingObjects = {}, drawingCreated = 0, drawingRemoved = 0 }

-- ── value types ───────────────────────────────────────────────────────────
local Vec2 = {}
Vec2.__index = Vec2
local function v2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, Vec2) end
Vec2.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
Vec2.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
Vec2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
Vec2.__tostring = function(v) return string.format("(%.1f,%.1f)", v.X, v.Y) end

local Vec3 = {}
Vec3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then return v3(0, 0, 0) end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	return rawget(Vec3, k)
end
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vec3) end
Vec3.__add = function(a, b)
	if type(b) == "number" then return v3(a.X + b, a.Y + b, a.Z + b) end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vec3.__sub = function(a, b)
	if type(b) == "number" then return v3(a.X - b, a.Y - b, a.Z - b) end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vec3.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vec3.__tostring = function(v) return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z) end

local Col3 = {}
Col3.__index = Col3
Col3.new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Col3) end
function Col3.fromRGB(r, g, b)
	return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, Col3)
end
function Col3.fromHSV(h, s, v)
	h = (h % 1) * 6
	local c = v * s
	local x = c * (1 - math.abs((h % 2) - 1))
	local r, g, b = 0, 0, 0
	if h < 1 then r, g, b = c, x, 0
	elseif h < 2 then r, g, b = x, c, 0
	elseif h < 3 then r, g, b = 0, c, x
	elseif h < 4 then r, g, b = 0, x, c
	elseif h < 5 then r, g, b = x, 0, c
	else r, g, b = c, 0, x end
	local m = v - c
	return setmetatable({ R = r + m, G = g + m, B = b + m }, Col3)
end
function Col3.toHSV(c)
	local mx = math.max(c.R, c.G, c.B)
	local mn = math.min(c.R, c.G, c.B)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == c.R then h = ((c.G - c.B) / d) % 6
		elseif mx == c.G then h = (c.B - c.R) / d + 2
		else h = (c.R - c.G) / d + 4 end
		h = h / 6
	end
	local s = (mx == 0) and 0 or d / mx
	return h, s, mx
end
Col3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Col3.__tostring = function(c)
	return string.format("#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local UDimT = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
local UDim2T = {}
function UDim2T.new(xs, xo, ys, yo)
	return { X = UDimT.new(xs, xo), Y = UDimT.new(ys, yo) }
end
function UDim2T.fromScale(x, y) return UDim2T.new(x, 0, y, 0) end
function UDim2T.fromOffset(x, y) return UDim2T.new(0, x, 0, y) end

-- ── signals ───────────────────────────────────────────────────────────────
local Signal = {}
Signal.__index = Signal
local function newSignal(name) return setmetatable({ name = name, _fns = {} }, Signal) end
function Signal:Connect(fn)
	local conn = { Connected = true }
	self._fns[#self._fns + 1] = fn

	local function disconnect()
		conn.Connected = false
		for i = #self._fns, 1, -1 do
			if self._fns[i] == fn then table.remove(self._fns, i) end
		end
	end

	conn.Disconnect = disconnect
	function conn:Disconnect() disconnect() end
	return conn
end
function Signal:Fire(...)
	local snapshot = {}
	for i, fn in ipairs(self._fns) do snapshot[i] = fn end
	for _, fn in ipairs(snapshot) do
		local ok, err = pcall(fn, ...)
		if not ok then
			local msg = "[signal " .. tostring(self.name) .. "] " .. tostring(err)
			M.errors[#M.errors + 1] = msg
			if M.strict then error(msg, 0) end
		end
	end
end

-- ── instance class ────────────────────────────────────────────────────────
local Instance = {}
Instance.__index = Instance
M.classParents = {
	Part = { BasePart = true }, MeshPart = { BasePart = true }, UnionOperation = { BasePart = true },
	Humanoid = {}, Model = {}, Highlight = {},
	ScreenGui = { LayerCollector = true },
	Frame = { GuiObject = true }, TextLabel = { GuiObject = true }, TextButton = { GuiObject = true },
	TextBox = { GuiObject = true }, ScrollingFrame = { GuiObject = true },
	UIListLayout = {}, UICorner = {}, UIStroke = {}, UIPadding = {}, UIGradient = {},
	Tool = {}, Camera = {}, Folder = {}, Player = {}, Workspace = {}, Players = {}, PlayerGui = {},
	DataModel = {},
}

local EVENT_WORDS = {
	MouseEnter = true, MouseLeave = true, MouseButton1Click = true, MouseButton1Down = true,
	MouseButton1Up = true, InputBegan = true, InputChanged = true, InputEnded = true,
	Activated = true, FocusLost = true, Focused = true, Destroying = true, Changed = true,
	CharacterAdded = true, CharacterRemoving = true, PlayerAdded = true, PlayerRemoving = true,
	DescendantAdded = true, DescendantRemoving = true, ChildAdded = true, ChildRemoved = true,
	AncestryChanged = true,
}

local function copy(t)
	local out = {}
	for i = 1, #t do out[i] = t[i] end
	return out
end

local function findChildOfClass(node, cls)
	for _, c in ipairs(node._children) do
		if c.ClassName == cls then return c end
	end
	return nil
end

function Instance.new(className)
	if not M.classParents[className] then
		error("Unable to create an Instance of type \"" .. tostring(className) .. "\"", 2)
	end
	local obj = setmetatable({
		ClassName = className,
		Name = className,
		_children = {},
		_parent = nil,
		_events = {},
		_props = {},
	}, Instance)
	M.instances = (M.instances or 0) + 1

	if className == "Highlight" then
		obj.FillColor = Col3.fromRGB(255, 255, 255)
		obj.OutlineColor = Col3.fromRGB(255, 255, 255)
		obj.FillTransparency = 0.5
		obj.OutlineTransparency = 0.5
		obj.Enabled = true
		obj.Adornee = nil
	elseif className == "Part" or className == "MeshPart" then
		obj.Size = v3(1, 1, 1)
		obj.Position = v3(0, 0, 0)
		obj.Transparency = 0
	else
		obj.Size = UDim2T.fromOffset(100, 100)
		obj.Position = UDim2T.fromOffset(0, 0)
		obj.BackgroundColor3 = Col3.fromRGB(255, 255, 255)
		obj.BackgroundTransparency = 0
		obj.Text = ""
		obj.TextSize = 14
		obj.TextColor3 = Col3.fromRGB(0, 0, 0)
		obj.Visible = true
		obj.LayoutOrder = 0
		obj.ZIndex = 1
		obj.BorderSizePixel = 1
	end
	return obj
end

function Instance.__index(obj, key)
	if EVENT_WORDS[key] then
		if not obj._events[key] then obj._events[key] = newSignal(obj.Name .. "." .. key) end
		return obj._events[key]
	end

	local raw = rawget(obj, key)
	if raw ~= nil then return raw end

	if key == "Parent" then return obj._parent end
	if key == "AbsolutePosition" then return v2(0, 0) end
	if key == "AbsoluteSize" then return v2(100, 20) end
	if key == "ViewportSize" then return v2(1280, 720) end
	if key == "CanCanvasSize" then return UDim2T.new() end
	if key == "AbsoluteContentSize" then return v2(0, 0) end
	if key == "MouseButton1Down" then return newSignal("mb") end

	if key == "GetChildren" then return function(self) return copy(self._children) end end
	if key == "GetDescendants" then
		return function(self)
			local out = {}
			local function walk(node)
				for _, c in ipairs(node._children) do
					out[#out + 1] = c
					walk(c)
				end
			end
			walk(self)
			return out
		end
	end
	if key == "FindFirstChild" then
		return function(self, name)
			for _, c in ipairs(self._children) do
				if c.Name == name then return c end
			end
			return nil
		end
	end
	if key == "FindFirstChildWhichIsA" then
		return function(self, cls)
			for _, c in ipairs(self._children) do
				if c.ClassName == cls or (M.classParents[c.ClassName] or {})[cls] then return c end
			end
			return nil
		end
	end
	if key == "FindFirstChildOfClass" then return function(self, cls) return findChildOfClass(self, cls) end end
	if key == "IsA" then
		return function(self, cls)
			if self.ClassName == cls then return true end
			return (M.classParents[self.ClassName] or {})[cls] == true
		end
	end
	if key == "IsDescendantOf" then
		return function(self, anc)
			local p = self._parent
			while p do
				if p == anc then return true end
				p = p._parent
			end
			return false
		end
	end
	if key == "Destroy" then
		return function(self)
			local ev = self._events.Destroying
			if ev then ev:Fire() end
			Instance.SetParent(self, nil)
			self._destroyed = true
		end
	end
	if key == "Remove" then return function(self) self:Destroy() end end
	if key == "Clone" then return function(self) return Instance.new(self.ClassName) end end
	if key == "GetPropertyChangedSignal" then
		return function(self, prop)
			local k = "prop_" .. prop
			if not self._events[k] then self._events[k] = newSignal(prop) end
			return self._events[k]
		end
	end
	if key == "GetAttribute" then return function(self, name) return (self._attrs or {})[name] end end
	if key == "SetAttribute" then
		return function(self, name, value)
			self._attrs = self._attrs or {}
			self._attrs[name] = value
		end
	end
	if key == "IsFocused" then return function() return false end end
	if key == "GetBoundingBox" then
		return function(self)
			local root = nil
			for _, c in ipairs(self._children) do
				if c.Name == "HumanoidRootPart" then root = c break end
			end
			if not root then return nil end
			return { Position = root.Position, UpVector = v3(0, 1, 0) }, v3(2, 5, 1)
		end
	end
	if key == "WorldToScreenPoint" or key == "WorldToViewportPoint" then return M.worldToScreen end
	if key == "GetMouseLocation" then return function() return v2(400, 300) end end
	if key == "GetPlayers" then return function() return M.playersList end end
	if key == "GetPlayerFromCharacter" then
		return function(_, char)
			for _, p in ipairs(M.playersList) do
				if p.Character == char then return p end
			end
			return nil
		end
	end
	if key == "GetService" then return M.getService end
	if key == "FindFirstChildOfClass" and false then return nil end
	if key == "UIListLayout" or key == "UICorner" or key == "UIPadding" or key == "UIGradient" or key == "UIStroke" then
		for _, c in ipairs(obj._children) do
			if c.ClassName == key then return c end
		end
		return nil
	end
	if key == "FindFirstChild" and obj.ClassName == "Player" then
		return function(self, name)
			if name == "PlayerGui" then return playerGui end
			for _, c in ipairs(self._children) do
				if c.Name == name then return c end
			end
			return nil
		end
	end
	if key == "Create" then return function() return { Play = function() end } end end
	if key == "JSONEncode" then return function(_, t) return M.jsonEncode(t) end end
	if key == "JSONDecode" then return function(_, str) return M.jsonDecode(str) end end
	if key == "BindToRenderStep" then return function() end end

	-- permissive fallback for GUI property writes/reads (CoreGui protection etc.)
	if M.permissive then
		if obj._permissive == nil then obj._permissive = {} end
		if obj._permissive[key] == nil then obj._permissive[key] = key:match("^Get") and function() end or nil end
		return obj._permissive[key]
	end

	return nil
end

function Instance.__newindex(obj, key, value)
	if key == "Parent" then Instance.SetParent(obj, value) return end
	rawset(obj, key, value)
end

function Instance:SetParent(parent)
	local old = self._parent
	if old then
		for i, c in ipairs(old._children) do
			if c == self then table.remove(old._children, i) break end
		end
		local p = old
		while p do
			if rawget(p, "_firesDescendantEvents") then
				local ev = rawget(p, "_events") and rawget(p, "_events").DescendantRemoving
				if ev then ev:Fire(self) end
			end
			p = p._parent
		end
	end

	self._parent = parent

	if parent then
		parent._children[#parent._children + 1] = self
		local function announce(node)
			local p = parent
			while p do
				if rawget(p, "_firesDescendantEvents") then
					local ev = rawget(p, "_events") and rawget(p, "_events").DescendantAdded
					if ev then ev:Fire(node) end
				end
				p = p._parent
			end
		end
		announce(self)
		for _, child in ipairs(self:GetDescendants()) do
			announce(child)
		end
	end
end

-- ── world ─────────────────────────────────────────────────────────────────
M.camPos = v3(0, 0, 0)
M.worldToScreen = function(a, b)
	-- supports both Camera:WorldToScreenPoint(pos) and WorldToScreenPoint(pos)
	local pos = b or a
	local rel = pos - M.camPos
	local z = math.max(-rel.Z, 0.001)
	local scale = 600
	local sx = 640 + rel.X * scale / z
	local sy = 360 - rel.Y * scale / z
	-- Roblox returns Vector3 (X, Y screen; Z depth)
	return v3(sx, sy, z), true, v3(sx, sy, z), true
end

M.workspace = Instance.new("Workspace")
M.workspace.Name = "Workspace"
M.workspace._firesDescendantEvents = true
-- events live in the instance's event table so the __index handler finds them
rawset(M.workspace._events, "DescendantAdded", newSignal("Workspace.DescendantAdded"))
rawset(M.workspace._events, "DescendantRemoving", newSignal("Workspace.DescendantRemoving"))

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.CFrame = { Position = M.camPos, LookVector = v3(0, 0, -1) }
M.workspace.CurrentCamera = camera
M.camera = camera

local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"

local localPlayer = Instance.new("Player")
localPlayer.Name = "LocalPlayer"
localPlayer.Character = nil
localPlayer.CharacterAdded = newSignal("LocalPlayer.CharacterAdded")

local services = {}
local function service(name, inst)
	inst = inst or Instance.new(M.classParents[name] and name or "Folder")
	inst.Name = name
	services[name] = inst
	return inst
end

local playersService = Instance.new("Players")
playersService.Name = "Players"
playersService.LocalPlayer = localPlayer
playersService.PlayerAdded = newSignal("Players.PlayerAdded")
playersService.PlayerRemoving = newSignal("Players.PlayerRemoving")
services.Players = playersService

local runService = service("RunService")
runService.RenderStepped = newSignal("RenderStepped")
runService.Heartbeat = newSignal("Heartbeat")

local inputService = service("UserInputService")
inputService.InputBegan = newSignal("InputBegan")
inputService.InputChanged = newSignal("InputChanged")
inputService.InputEnded = newSignal("InputEnded")

service("TweenService")
service("HttpService")
service("CoreGui")
services.Workspace = M.workspace

localPlayer.CharacterAdded = localPlayer.CharacterAdded
playerGui.Parent = localPlayer

M.getService = function(_, name)
	if services[name] then return services[name] end
	local ok, inst = pcall(Instance.new, name)
	if not ok then inst = Instance.new("Folder") end
	inst.Name = name
	services[name] = inst
	return inst
end

M.game = Instance.new("DataModel")
M.game.Name = "Game"
M.game.GetService = M.getService

-- ── helpers ───────────────────────────────────────────────────────────────
M.playersList = {}
M.players = {}
M.playersService = playersService

local R15_NAMES = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local R6_NAMES = { "Head", "Torso", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
	"Left Foot", "Right Foot", "Left Hand", "Right Hand" }

function M.makeCharacter(name, pos, rigType, health)
	local model = Instance.new("Model")
	model.Name = name
	local names = (rigType == "R6") and R6_NAMES or R15_NAMES
	local parts = {}
	for i, n in ipairs(names) do
		local p = Instance.new("Part")
		p.Name = n
		p.Position = v3(pos.X, pos.Y + (i - 1) * 0.3, pos.Z)
		p.Size = v3(1, 1, 1)
		p.Parent = model
		parts[n] = p
	end
	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.Health = health or 100
	hum.MaxHealth = 100
	hum.RootPart = parts.HumanoidRootPart
	hum.RigType = rigType or "R15"
	hum.Parent = model
	model.PrimaryPart = parts.HumanoidRootPart
	model.Parts = parts
	model.Humanoid = hum
	return model
end

function M.addPlayer(name, pos, rigType, health)
	local p = Instance.new("Player")
	p.Name = name
	p.CharacterAdded = newSignal(name .. ".CharacterAdded")
	p.CharacterRemoving = newSignal(name .. ".CharacterRemoving")
	local char = M.makeCharacter(name, pos, rigType or "R15", health)
	p.Character = char
	M.playersList[#M.playersList + 1] = p
	M.players[name] = p
	char.Parent = M.workspace
	return p, char
end

function M.spawnNpc(name, pos, rigType, health)
	local model = M.makeCharacter(name, pos, rigType or "R15", health)
	model.Parent = M.workspace
	return model
end

function M.spawnNode(name, pos, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Position = pos
	part.Size = size or v3(3, 3, 3)
	part.Parent = M.workspace
	return part
end

function M.stepRender(n)
	for _ = 1, (n or 1) do runService.RenderStepped:Fire(0.016) end
end

function M.stepHeartbeat(n)
	for _ = 1, (n or 1) do runService.Heartbeat:Fire(0.016) end
end

function M.countVisible(class)
	local c = 0
	for _, o in ipairs(M.drawingObjects) do
		if (not class or o.ClassName == class) and o.Visible then c = c + 1 end
	end
	return c
end

function M.liveDrawings()
	local c = 0
	for _, o in ipairs(M.drawingObjects) do
		if not o._removed then c = c + 1 end
	end
	return c
end

function M.jsonEncode(t)
	if type(t) ~= "table" then
		if type(t) == "string" then return '"' .. t .. '"' end
		return tostring(t)
	end
	local parts = {}
	local isArray = #t > 0
	for k, v in pairs(t) do
		if isArray then
			parts[#parts + 1] = M.jsonEncode(v)
		else
			parts[#parts + 1] = '"' .. tostring(k) .. '":' .. M.jsonEncode(v)
		end
	end
	if isArray then return "[" .. table.concat(parts, ",") .. "]" end
	return "{" .. table.concat(parts, ",") .. "}"
end
function M.jsonDecode(str)
	str = tostring(str)
	local pos = 1
	local function skip()
		while pos <= #str do
			local c = str:sub(pos, pos)
			if c == " " or c == "\n" or c == "\r" or c == "\t" then pos = pos + 1 else break end
		end
	end
	local parseValue

	local function parseString()
		pos = pos + 1
		local out = {}
		while pos <= #str do
			local c = str:sub(pos, pos)
			if c == '"' then pos = pos + 1 return table.concat(out) end
			if c == "\\" then
				local n = str:sub(pos + 1, pos + 1)
				local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\" }
				out[#out + 1] = map[n] or n
				pos = pos + 2
			else
				out[#out + 1] = c
				pos = pos + 1
			end
		end
		error("unterminated string")
	end

	local function parseNumber()
		local s2 = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		pos = pos + #s2
		return tonumber(s2)
	end

	parseValue = function()
		skip()
		local c = str:sub(pos, pos)
		if c == "{" then
			pos = pos + 1
			local obj = {}
			skip()
			if str:sub(pos, pos) == "}" then pos = pos + 1 return obj end
			while true do
				skip()
				local key = parseString()
				skip()
				pos = pos + 1 -- colon
				obj[key] = parseValue()
				skip()
				local d = str:sub(pos, pos)
				pos = pos + 1
				if d == "}" then return obj end
			end
		elseif c == "[" then
			pos = pos + 1
			local arr = {}
			skip()
			if str:sub(pos, pos) == "]" then pos = pos + 1 return arr end
			while true do
				arr[#arr + 1] = parseValue()
				skip()
				local d = str:sub(pos, pos)
				pos = pos + 1
				if d == "]" then return arr end
			end
		elseif c == '"' then
			return parseString()
		elseif str:sub(pos, pos + 3) == "true" then
			pos = pos + 4 return true
		elseif str:sub(pos, pos + 4) == "false" then
			pos = pos + 5 return false
		elseif str:sub(pos, pos + 3) == "null" then
			pos = pos + 4 return nil
		else
			return parseNumber()
		end
	end

	local ok, result = pcall(parseValue)
	if not ok then return {} end
	return result
end

-- ── Drawing library ───────────────────────────────────────────────────────
M.Drawing = {
	new = function(class)
		M.drawingCreated = M.drawingCreated + 1
		local obj = {
			ClassName = class, Visible = false, Transparency = 0, Thickness = 1,
			Color = Col3.fromRGB(255, 255, 255), From = v2(0, 0), To = v2(0, 0),
			Position = v2(0, 0), Size = v2(0, 0), Filled = false, Text = "",
			Center = false, Outline = false, Font = 0,
		}
		function obj:Remove() M.drawingRemoved = M.drawingRemoved + 1 self._removed = true end
		function obj:Destroy() self:Remove() end
		M.drawingObjects[#M.drawingObjects + 1] = obj
		return obj
	end,
}

function M.installGlobals()
	rawset(_G, "Vector2", { new = function(x, y) return v2(x, y) end })
	rawset(_G, "Vector3", { new = function(x, y, z) return v3(x, y, z) end })
	Color3 = Col3
	UDim = UDimT
	UDim2 = UDim2T
	TweenInfo = { new = function() return {} end }
	rawset(_G, "Instance", Instance)
	rawset(_G, "ColorSequence", {
		new = function(a, b)
			if type(a) == "table" then
				return { keypoints = a, a = a[1] and a[1].Value, b = a[#a] and a[#a].Value }
			end
			return { a = a, b = b }
		end,
	})
	rawset(_G, "ColorSequenceKeypoint", {
		new = function(t, c) return { Time = t, Value = c } end,
	})
	rawset(_G, "NumberSequenceKeypoint", {
		new = function(t, v) return { Time = t, Value = v } end,
	})
	rawset(_G, "NumberSequence", {
		new = function(a, b)
			if type(a) == "table" then
				return { keypoints = a, a = a[1] and a[1].Value, b = a[#a] and a[#a].Value }
			end
			return { a = a, b = b }
		end,
	})
	Enum = setmetatable({}, {
		__index = function(t, name)
			local group = setmetatable({}, {
				__index = function(_, item) return { Name = item, Value = 0 } end,
			})
			rawset(t, name, group)
			return group
		end,
	})

	local pending = {}
	local threads = {}

	local function resume(co)
		local ok, err = coroutine.resume(co)
		if not ok then
			M.errors[#M.errors + 1] = "[task] " .. tostring(err)
		elseif coroutine.status(co) ~= "dead" then
			threads[#threads + 1] = co
		end
	end

	function M.runPending()
		local snapshot = pending
		pending = {}
		for _, entry in ipairs(snapshot) do
			local co = coroutine.create(entry.fn)
			resume(co)
		end
		-- resume every sleeping thread exactly once (time is ignored)
		local again = threads
		threads = {}
		for _, co in ipairs(again) do
			if coroutine.status(co) ~= "dead" then resume(co) end
		end
	end

	rawset(_G, "task", {
		spawn = function(fn, ...)
			local co = coroutine.create(fn)
			local ok, err = coroutine.resume(co, ...)
			if not ok then
				M.errors[#M.errors + 1] = "[task.spawn] " .. tostring(err)
			elseif coroutine.status(co) ~= "dead" then
				threads[#threads + 1] = co
			end
		end,
		wait = function(t)
			if coroutine.isyieldable and coroutine.isyieldable() then
				coroutine.yield(t)
			end
			return t or 0
		end,
		delay = function(_, fn, ...)
			pending[#pending + 1] = { fn = fn, args = { ... } }
		end,
		defer = function(fn, ...)
			pending[#pending + 1] = { fn = fn, args = { ... } }
		end,
	})

	rawset(_G, "wait", function(t)
		if coroutine.isyieldable and coroutine.isyieldable() then coroutine.yield(t) end
		return t or 0
	end)
	rawset(_G, "spawn", function(fn, ...) return task.spawn(fn, ...) end)
	rawset(_G, "delay", function(_, fn, ...) return task.delay(0, fn, ...) end)

	game = M.game
	workspace = M.workspace
	Drawing = M.Drawing
end

function M.resetDrawingCounters()
	M.drawingObjects = {}
	M.drawingCreated = 0
	M.drawingRemoved = 0
end

return M
