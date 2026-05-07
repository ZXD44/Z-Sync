--[[
	Roblox ZXD44 Plugin v2.0 - Project-Based Two-Way Sync
	==========================================================
	Single file containing everything - no external require() needed.

	Features:
		- Polls GET /sync every 1.5s to receive file-change actions
		- Push Map: serialize ALL services and send to server (writes files to disk)
		- Auto-Push: periodically push map state (every 5s)
		- Two-way sync: edit .lua files on disk -> auto-updates scripts in Studio
		- Supported Actions: create, update, delete, rename, move, execute
]]

-- ── Services ────────────────────────────────────────────────────────────────
local HttpService          = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- ── Configuration ───────────────────────────────────────────────────────────
local SERVER_URL         = "http://localhost:3000"
local POLL_INTERVAL      = 1.5
local AUTO_PUSH_INTERVAL = 5

-- Services to sync with the local file system
local SYNC_SERVICES = {
	game:GetService("Workspace"),
	game:GetService("ServerScriptService"),
	game:GetService("ReplicatedStorage"),
	game:GetService("StarterGui"),
	game:GetService("StarterPlayer"),
	game:GetService("StarterPack"),
	game:GetService("Lighting"),
	game:GetService("SoundService"),
	game:GetService("ServerStorage"),
}

-- ═════════════════════════════════════════════════════════════════════════════
-- SERIALIZER
-- ═════════════════════════════════════════════════════════════════════════════

local Serializer = {}

local CLASS_PROPERTIES = {
	BasePart = {
		"Position","Size","CFrame","Orientation",
		"Color","BrickColor","Material","Transparency",
		"Anchored","CanCollide","CanTouch","CanQuery",
		"Shape","Reflectance","CastShadow",
	},
	MeshPart     = {"MeshId","TextureID"},
	Model        = {"PrimaryPart"},

	-- Tools & Characters
	Tool         = {"CanBeDropped","Enabled","Grip","ManualActivationOnly","RequiresHandle","ToolTip"},
	Backpack     = {},
	Humanoid     = {"Health","MaxHealth","WalkSpeed","JumpPower","JumpHeight","HipHeight","DisplayName","AutoRotate"},
	Accessory    = {"AttachmentPoint"},
	ShirtGraphic = {"Graphic"},
	Shirt        = {"ShirtTemplate"},
	Pants        = {"PantsTemplate"},
	BodyColors   = {"HeadColor3","LeftArmColor3","LeftLegColor3","RightArmColor3","RightLegColor3","TorsoColor3"},

	-- Lights
	PointLight   = {"Brightness","Color","Range","Enabled","Shadows"},
	SpotLight    = {"Brightness","Color","Range","Enabled","Shadows","Angle","Face"},
	SurfaceLight = {"Brightness","Color","Range","Enabled","Shadows","Angle","Face"},

	-- Scripts
	Script       = {"Source","Enabled","RunContext"},
	LocalScript  = {"Source","Enabled"},
	ModuleScript = {"Source"},

	-- GUI
	ScreenGui    = {"Enabled","ResetOnSpawn","IgnoreGuiInset","DisplayOrder"},
	BillboardGui = {"Size","StudsOffset","Enabled","AlwaysOnTop","MaxDistance"},
	SurfaceGui   = {"Face","Enabled","AlwaysOnTop","PixelsPerStud"},
	Frame        = {"Size","Position","BackgroundColor3","BackgroundTransparency","BorderSizePixel","Visible","LayoutOrder"},
	ScrollingFrame = {"Size","Position","CanvasSize","ScrollBarThickness","BackgroundTransparency","Visible"},
	TextLabel    = {"Size","Position","Text","TextColor3","TextSize","Font","BackgroundColor3","BackgroundTransparency","Visible","TextWrapped","RichText"},
	TextButton   = {"Size","Position","Text","TextColor3","TextSize","Font","BackgroundColor3","BackgroundTransparency","Visible"},
	TextBox      = {"Size","Position","Text","PlaceholderText","TextColor3","TextSize","Font","BackgroundColor3","BackgroundTransparency","Visible","ClearTextOnFocus"},
	ImageLabel   = {"Size","Position","Image","ImageColor3","BackgroundTransparency","Visible","ScaleType"},
	ImageButton  = {"Size","Position","Image","ImageColor3","BackgroundTransparency","Visible","ScaleType"},
	UIListLayout = {"FillDirection","HorizontalAlignment","VerticalAlignment","Padding","SortOrder"},
	UIGridLayout = {"CellSize","CellPadding","FillDirection","SortOrder"},
	UIPadding    = {"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"},
	UICorner     = {"CornerRadius"},
	UIStroke     = {"Color","Thickness","Transparency","ApplyStrokeMode"},

	-- Values
	StringValue  = {"Value"}, IntValue = {"Value"}, NumberValue = {"Value"},
	BoolValue    = {"Value"}, Color3Value = {"Value"}, Vector3Value = {"Value"},
	ObjectValue  = {},

	-- Effects & Visuals
	Decal        = {"Texture","Face","Transparency","Color3"},
	Texture      = {"Texture","Face","StudsPerTileU","StudsPerTileV"},
	Beam         = {"Attachment0","Attachment1","Color","Transparency","Width0","Width1","Enabled"},
	ParticleEmitter = {"Texture","Color","Size","Lifetime","Rate","Speed","Enabled","Shape"},
	Fire         = {"Color","SecondaryColor","Size","Heat","Enabled"},
	Smoke        = {"Color","Opacity","RiseVelocity","Size","Enabled"},
	Sparkles     = {"SparkleColor","Enabled"},
	Trail        = {"Attachment0","Attachment1","Color","Lifetime","Enabled"},
	Highlight    = {"FillColor","FillTransparency","OutlineColor","OutlineTransparency","Enabled"},

	-- Physics & Constraints
	Attachment   = {"CFrame","Visible"},
	Weld         = {"Part0","Part1","C0","C1"},
	WeldConstraint = {"Part0","Part1","Enabled"},
	Motor6D      = {"Part0","Part1","C0","C1"},
	HingeConstraint = {"ActuatorType","AngularSpeed","MotorMaxTorque","LimitsEnabled"},
	RopeConstraint  = {"Length","Visible","Thickness"},
	SpringConstraint = {"FreeLength","Stiffness","Damping","Visible"},
	AlignPosition   = {"Position","MaxForce","Responsiveness"},
	AlignOrientation = {"CFrame","MaxTorque","Responsiveness"},
	BodyVelocity = {"Velocity","MaxForce"},
	BodyPosition = {"Position","MaxForce"},

	-- Interaction
	ProximityPrompt = {"ActionText","ObjectText","MaxActivationDistance","HoldDuration","Enabled","RequiresLineOfSight"},
	ClickDetector   = {"MaxActivationDistance","CursorIcon"},

	-- Networking
	RemoteEvent    = {},
	RemoteFunction = {},
	BindableEvent    = {},
	BindableFunction = {},

	-- Audio
	Sound        = {"SoundId","Volume","Looped","PlaybackSpeed","Playing"},

	-- Camera
	Camera       = {"CFrame","FieldOfView","CameraType"},

	-- Containers
	Folder       = {},
	Configuration = {},

	-- Terrain / Spawn
	Terrain      = {},
	SpawnLocation = {
		"Position","Size","CFrame","Color","Material","Transparency","Anchored",
		"Duration","Enabled","Neutral","TeamColor",
	},
}

local BASE_PART_CLASSES = {
	Part=true, MeshPart=true, WedgePart=true, CornerWedgePart=true,
	TrussPart=true, SpawnLocation=true, Seat=true, VehicleSeat=true,
}

local function encodeValue(value)
	local t = typeof(value)
	if t == "Vector3" then
		return {_type="Vector3", X=value.X, Y=value.Y, Z=value.Z}
	elseif t == "CFrame" then
		return {_type="CFrame", components={value:GetComponents()}}
	elseif t == "Color3" then
		return {_type="Color3", R=math.floor(value.R*255), G=math.floor(value.G*255), B=math.floor(value.B*255)}
	elseif t == "BrickColor" then
		return {_type="BrickColor", Name=value.Name}
	elseif t == "UDim2" then
		return {_type="UDim2", XScale=value.X.Scale, XOffset=value.X.Offset, YScale=value.Y.Scale, YOffset=value.Y.Offset}
	elseif t == "UDim" then
		return {_type="UDim", Scale=value.Scale, Offset=value.Offset}
	elseif t == "EnumItem" then
		return {_type="Enum", EnumType=tostring(value.EnumType), Name=value.Name}
	elseif t == "Instance" then
		return {_type="Instance", Path=value:GetFullName()}
	elseif t == "number" or t == "string" or t == "boolean" then
		return value
	else
		return {_type=t, Value=tostring(value)}
	end
end

local function decodeValue(encoded)
	if type(encoded) ~= "table" or not encoded._type then return encoded end
	local t = encoded._type
	if t == "Vector3" then return Vector3.new(encoded.X, encoded.Y, encoded.Z)
	elseif t == "CFrame" then return CFrame.new(table.unpack(encoded.components))
	elseif t == "Color3" then return Color3.fromRGB(encoded.R, encoded.G, encoded.B)
	elseif t == "BrickColor" then return BrickColor.new(encoded.Name)
	elseif t == "UDim2" then return UDim2.new(encoded.XScale, encoded.XOffset, encoded.YScale, encoded.YOffset)
	elseif t == "UDim" then return UDim.new(encoded.Scale, encoded.Offset)
	elseif t == "Enum" then
		local ok, r = pcall(function() return Enum[encoded.EnumType][encoded.Name] end)
		return ok and r or nil
	end
	return nil
end

local function getPropsForClass(className)
	local props = {"Name"}
	if BASE_PART_CLASSES[className] then
		for _, p in ipairs(CLASS_PROPERTIES.BasePart) do table.insert(props, p) end
	end
	if CLASS_PROPERTIES[className] then
		for _, p in ipairs(CLASS_PROPERTIES[className]) do table.insert(props, p) end
	end
	return props
end

function Serializer.serialize(instance)
	local data = {ClassName=instance.ClassName, Name=instance.Name, Path=instance:GetFullName(), Properties={}, Children={}}
	for _, propName in ipairs(getPropsForClass(instance.ClassName)) do
		if propName ~= "Name" then
			local ok, value = pcall(function() return (instance :: any)[propName] end)
			if ok and value ~= nil then data.Properties[propName] = encodeValue(value) end
		end
	end
	return data
end

function Serializer.serializeTree(root)
	local data = Serializer.serialize(root)
	for _, child in ipairs(root:GetChildren()) do
		table.insert(data.Children, Serializer.serializeTree(child))
	end
	return data
end

function Serializer.applyProperties(instance, properties)
	for propName, enc in pairs(properties) do
		local value = decodeValue(enc)
		if value ~= nil then
			local ok, err = pcall(function() (instance :: any)[propName] = value end)
			if not ok then warn(("[ZXD44] Cannot set %s.%s: %s"):format(instance.Name, propName, tostring(err))) end
		end
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- PLUGIN UI
-- ═════════════════════════════════════════════════════════════════════════════

local toolbar = plugin:CreateToolbar("ZXD44")

local pushButton = toolbar:CreateButton("Push", "ส่งข้อมูลแมพไปที่คอม (เขียนไฟล์ลง disk)", "rbxassetid://6031075938")
local toggleButton = toolbar:CreateButton("Sync", "เปิด/ปิด การรับไฟล์จากคอม (Two-way sync)", "rbxassetid://6031075929")
local autoPushButton = toolbar:CreateButton("Auto", "ส่งข้อมูลแมพไปที่คอมอัตโนมัติทุก 5 วินาที", "rbxassetid://6031094678")
local statusButton = toolbar:CreateButton("Status", "เช็คสถานะเซิร์ฟเวอร์และโปรเจกต์", "rbxassetid://6031075931")

local isSyncing     = false
local isAutoPushing = false

-- ═════════════════════════════════════════════════════════════════════════════
-- HTTP HELPER
-- ═════════════════════════════════════════════════════════════════════════════

local function httpRequest(method, endpoint, body)
	local url = SERVER_URL .. endpoint
	local ok, response = pcall(function()
		if method == "GET" then
			return HttpService:GetAsync(url)
		else
			return HttpService:PostAsync(url, HttpService:JSONEncode(body or {}), Enum.HttpContentType.ApplicationJson)
		end
	end)
	if not ok then return false, response end
	local pOk, parsed = pcall(function() return HttpService:JSONDecode(response) end)
	return true, pOk and parsed or response
end

local function resolvePath(p)
	if not p or p == "" then return nil end
	local current = game
	for _, part in ipairs(string.split(p, ".")) do
		current = current:FindFirstChild(part)
		if not current then return nil end
	end
	return current
end

-- ═════════════════════════════════════════════════════════════════════════════
-- ACTION HANDLERS
-- ═════════════════════════════════════════════════════════════════════════════

local ActionHandlers = {}

function ActionHandlers.create(a)
	local className  = a.className or a.class
	local name       = a.name or className
	local parentPath = a.parent or "Workspace"
	local parent     = resolvePath(parentPath)
	if not parent then warn("[ZXD44] หาโฟลเดอร์ปลายทางไม่พบ:", parentPath) return end
	local ok, inst = pcall(Instance.new, className)
	if not ok then warn("[ZXD44] ไม่สามารถสร้างคลาสได้:", className) return end
	inst.Name = name
	if a.properties then Serializer.applyProperties(inst, a.properties) end
	inst.Parent = parent
	print(("[ZXD44] สร้าง %s '%s' ใน %s"):format(className, name, parentPath))
end

function ActionHandlers.update(a)
	if not a.target or not a.properties then warn("[ZXD44] update: ข้อมูลไม่ครบ") return end
	local inst = resolvePath(a.target)
	if not inst then warn("[ZXD44] หาเป้าหมายไม่พบ:", a.target) return end
	Serializer.applyProperties(inst, a.properties)
	print(("[ZXD44] อัปเดตคุณสมบัติ: '%s'"):format(a.target))
end

function ActionHandlers.delete(a)
	if not a.target then warn("[ZXD44] delete: ไม่ระบุเป้าหมาย") return end
	local inst = resolvePath(a.target)
	if not inst then warn("[ZXD44] หาเป้าหมายไม่พบ:", a.target) return end
	local fullName = inst:GetFullName()
	inst:Destroy()
	print(("[ZXD44] ลบสำเร็จ: '%s'"):format(fullName))
end

function ActionHandlers.rename(a)
	if not a.target or not a.name then warn("[ZXD44] rename: ข้อมูลไม่ครบ") return end
	local inst = resolvePath(a.target)
	if not inst then return end
	inst.Name = a.name
	print(("[ZXD44] เปลี่ยนชื่อ: '%s' -> '%s'"):format(a.target, a.name))
end

function ActionHandlers.move(a)
	if not a.target or not a.parent then warn("[ZXD44] move: ข้อมูลไม่ครบ") return end
	local inst   = resolvePath(a.target)
	local parent = resolvePath(a.parent)
	if not inst or not parent then return end
	inst.Parent = parent
	print(("[ZXD44] ย้ายตำแหน่ง: '%s' -> '%s'"):format(a.target, a.parent))
end

function ActionHandlers.execute(a)
	local source = a.source or a.code
	if not source then return end
	local fn, err = loadstring(source)
	if fn then
		local ok, rErr = pcall(fn)
		if ok then print("[ZXD44] รันสคริปต์สำเร็จ")
		else warn("[ZXD44] เกิดข้อผิดพลาดขณะรัน:", rErr) end
	else warn("[ZXD44] โค้ดมีข้อผิดพลาด:", err) end
end

local function processAction(action)
	local kind = string.lower(tostring(action.action or ""))
	local handler = ActionHandlers[kind]
	if handler then
		ChangeHistoryService:SetWaypoint("ZXD44: " .. kind)
		local ok, err = pcall(handler, action)
		if not ok then warn("[ZXD44] Handler error:", err) end
		ChangeHistoryService:SetWaypoint("ZXD44: " .. kind .. " done")
	else
		warn("[ZXD44] Unknown action:", kind)
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- PUSH MAP (Serialize ALL services -> POST /sync -> server writes files)
-- ═════════════════════════════════════════════════════════════════════════════

local function pushMapState(silent)
	if not silent then print("[ZXD44] กำลังแยกองค์ประกอบแมพ...") end

	local services = {}
	for _, service in ipairs(SYNC_SERVICES) do
		services[service.Name] = Serializer.serializeTree(service)
	end

	local payload = {
		timestamp = os.time(),
		services  = services,
	}

	local ok, res = httpRequest("POST", "/sync", payload)
	if ok then
		if not silent then
			print("[ZXD44] [OK] บันทึกแมพสำเร็จ!")
		end
	else
		warn("[ZXD44] [X] ส่งข้อมูลไม่สำเร็จ - เซิร์ฟเวอร์รันอยู่หรือไม่?")
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- SYNC / AUTO-PUSH LOOPS
-- ═════════════════════════════════════════════════════════════════════════════

local function startSyncLoop()
	isSyncing = true
	toggleButton:SetActive(true)
	print("[ZXD44] [>] เริ่มระบบ Sync (รับไฟล์ทุกๆ "..POLL_INTERVAL.." วินาที)")
	while isSyncing do
		local ok, res = httpRequest("GET", "/sync")
		if ok and type(res) == "table" and res.actions then
			for _, action in ipairs(res.actions) do
				processAction(action)
			end
		end
		task.wait(POLL_INTERVAL)
	end
end

local function stopSyncLoop()
	isSyncing = false
	toggleButton:SetActive(false)
	print("[ZXD44] [.] หยุดระบบ Sync")
end

local function startAutoPushLoop()
	isAutoPushing = true
	autoPushButton:SetActive(true)
	print("[ZXD44] [*] เริ่มระบบ Auto-Push (ส่งไฟล์ทุกๆ "..AUTO_PUSH_INTERVAL.." วินาที)")
	while isAutoPushing do
		pushMapState(true)
		task.wait(AUTO_PUSH_INTERVAL)
	end
end

local function stopAutoPushLoop()
	isAutoPushing = false
	autoPushButton:SetActive(false)
	print("[ZXD44] [.] หยุดระบบ Auto-Push")
end

-- ═════════════════════════════════════════════════════════════════════════════
-- STATUS CHECK
-- ═════════════════════════════════════════════════════════════════════════════

local function checkStatus()
	local ok, res = httpRequest("GET", "/status")
	if ok and type(res) == "table" then
		print("--------------------------------")
		print("[ZXD44] เซิร์ฟเวอร์: " .. (res.server or "Roblox Bridge"))
		print("[ZXD44] โปรเจกต์: " .. (res.project or "?"))
		print("[ZXD44] ระบบ Sync: " .. (isSyncing and "[เปิดอยู่]" or "[ปิดอยู่]"))
		print("[ZXD44] Auto-Push: " .. (isAutoPushing and "[เปิดอยู่]" or "[ปิดอยู่]"))
		print("[ZXD44] ที่อยู่โฟลเดอร์: " .. (res.projectDir or "?"))
		print("[ZXD44] รันมาแล้ว: " .. ("%.1f วินาที"):format(res.uptime or 0))
		print("[ZXD44] คำสั่งค้าง: " .. (res.pendingActions or 0))
		print("--------------------------------")
	else
		warn("[ZXD44] [X] เชื่อมต่อเซิร์ฟเวอร์ไม่ได้")
	end
end

-- BINDINGS



-- ═════════════════════════════════════════════════════════════════════════════
-- BUTTON BINDINGS
-- ═════════════════════════════════════════════════════════════════════════════

pushButton.Click:Connect(function() pushMapState(false) end)
toggleButton.Click:Connect(function()
	if isSyncing then stopSyncLoop() else task.spawn(startSyncLoop) end
end)
autoPushButton.Click:Connect(function()
	if isAutoPushing then stopAutoPushLoop() else task.spawn(startAutoPushLoop) end
end)
statusButton.Click:Connect(function() checkStatus() end)

plugin.Unloading:Connect(function()
	isSyncing = false
	isAutoPushing = false
end)

-- ═════════════════════════════════════════════════════════════════════════════
-- STARTUP
-- ═════════════════════════════════════════════════════════════════════════════
print("================================")
print("[ZXD44] ปลั๊กอินทำงานแล้ว! v2.0")
print("[ZXD44] เซิร์ฟเวอร์: "..SERVER_URL)
print("[ZXD44] Push      = ส่งข้อมูลแมพลงคอม")
print("[ZXD44] Sync      = เปิดรับไฟล์จากคอม")
print("[ZXD44] Auto      = ส่งข้อมูลอัตโนมัติ")
print("================================")


