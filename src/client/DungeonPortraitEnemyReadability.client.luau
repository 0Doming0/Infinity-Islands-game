-- Mobile Dungeon Mode — Task 10: Portrait Enemy Readability Pass.
--
-- Camada local que adapta o EnemyStatusBillboard existente somente no
-- DungeonMobileMode. O servidor, IA, dano e hitbox nao sao alterados.
--
-- Objetivos:
-- - menos poluicao no portrait;
-- - leitura rapida de funcao/perigo;
-- - explicar alvos protegidos;
-- - sinalizar windups perigosos dentro da tela.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local VERSION = "DungeonPortraitEnemyReadabilityV1"
local UPDATE_INTERVAL = 0.12
local COMMON_MAX_DISTANCE = 48
local IMPORTANT_MAX_DISTANCE = 76

local COLORS = {
	Text = Color3.fromRGB(247, 251, 255),
	Muted = Color3.fromRGB(177, 200, 218),
	Ranged = Color3.fromRGB(99, 220, 255),
	Mortar = Color3.fromRGB(255, 157, 63),
	Danger = Color3.fromRGB(255, 91, 104),
	Elite = Color3.fromRGB(255, 216, 92),
	Boss = Color3.fromRGB(255, 103, 126),
	Protected = Color3.fromRGB(132, 177, 255),
	Objective = Color3.fromRGB(178, 139, 255),
	Glass = Color3.fromRGB(10, 20, 31),
}

local active = false
local elapsed = 0
local records = setmetatable({}, { __mode = "k" })

local function textScale()
	return math.clamp(
		tonumber(player:GetAttribute("DungeonMobileTextUserScale")) or 1,
		0.90,
		1.25
	)
end

local function scaledText(base)
	return math.max(7, math.floor(base * textScale() + 0.5))
end

local function reducedEffects()
	return player:GetAttribute("ClientSetting_ReducedEffects") == true
		or player:GetAttribute("ReducedMotion") == true
		or player:GetAttribute("ReduceMotion") == true
end

local function getRoot(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getHumanoid(model)
	return model and model:FindFirstChildWhichIsA("Humanoid", true)
end

local function playerRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function roleInfo(model)
	if model:GetAttribute("ObjectiveMechanicActorType") == "GuardWard"
		or CollectionService:HasTag(model, "DungeonGuardWard")
	then
		return "CRISTAL • QUEBRE PRIMEIRO", COLORS.Objective, true
	end

	if model:GetAttribute("IsBoss") == true
		or CollectionService:HasTag(model, "DungeonBoss")
	then
		return "BOSS", COLORS.Boss, true
	end

	if model:GetAttribute("EliteShielded") == true then
		return "🔒 DERROTE OS SUPORTES", COLORS.Protected, true
	end

	if model:GetAttribute("GuardWardProtected") == true then
		return "🔒 QUEBRE OS CRISTAIS", COLORS.Protected, true
	end

	if model:GetAttribute("IsElite") == true then
		return "★ ELITE", COLORS.Elite, true
	end

	local behavior = tostring(model:GetAttribute("SlimeBehavior") or "")
	if string.find(behavior, "Mortar", 1, true) then
		return "MORTEIRO", COLORS.Mortar, true
	end
	if string.find(behavior, "Ranged", 1, true) then
		return "RANGED", COLORS.Ranged, true
	end

	local role = string.lower(tostring(
		model:GetAttribute("MonsterRole")
			or model:GetAttribute("ObjectiveRole")
			or model:GetAttribute("CombatRole")
			or ""
	))
	if string.find(role, "guard", 1, true) then
		return "GUARDA", COLORS.Protected, true
	end
	if string.find(role, "ranged", 1, true) then
		return "RANGED", COLORS.Ranged, true
	end

	return nil, nil, false
end

local function dangerInfo(model)
	local state = tostring(model:GetAttribute("AIState") or "")
	if state == "DashWindup" then
		return "⚠ ESQUIVE", COLORS.Danger
	elseif state == "Mortar" then
		return "⚠ IMPACTO", COLORS.Mortar
	end

	local bossAttack = tostring(model:GetAttribute("BossAttack") or "")
	if model:GetAttribute("IsBoss") == true
		and bossAttack ~= ""
		and bossAttack ~= "Idle"
	then
		return "⚠ " .. string.upper(bossAttack), COLORS.Boss
	end

	return nil, nil
end

local function saveProperty(record, object, key)
	record.Original[object] = record.Original[object] or {}
	if record.Original[object][key] == nil then
		record.Original[object][key] = object[key]
	end
end

local function setProperty(record, object, key, value)
	if not object then
		return
	end
	saveProperty(record, object, key)
	object[key] = value
end

local function restoreRecord(record)
	if record.DangerTween then
		record.DangerTween:Cancel()
		record.DangerTween = nil
	end

	if record.DangerHighlight and record.DangerHighlight.Parent then
		record.DangerHighlight:Destroy()
	end
	record.DangerHighlight = nil

	if record.RoleBadge and record.RoleBadge.Parent then
		record.RoleBadge:Destroy()
	end
	record.RoleBadge = nil

	for object, properties in pairs(record.Original) do
		if object and object.Parent then
			for key, value in pairs(properties) do
				pcall(function()
					object[key] = value
				end)
			end
		end
	end
	table.clear(record.Original)
end

local function ensureRoleBadge(record, billboard)
	if record.RoleBadge and record.RoleBadge.Parent == billboard then
		return record.RoleBadge
	end

	local badge = billboard:FindFirstChild("PortraitRoleBadge")
	if badge and not badge:IsA("TextLabel") then
		badge:Destroy()
		badge = nil
	end
	if not badge then
		badge = Instance.new("TextLabel")
		badge.Name = "PortraitRoleBadge"
		badge.Position = UDim2.fromOffset(4, 41)
		badge.Size = UDim2.new(1, -8, 0, 14)
		badge.BackgroundColor3 = COLORS.Glass
		badge.BackgroundTransparency = 0.22
		badge.BorderSizePixel = 0
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 8
		badge.TextColor3 = COLORS.Text
		badge.TextStrokeTransparency = 0.55
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.TextTruncate = Enum.TextTruncate.AtEnd
		badge.ZIndex = 3
		badge.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = badge
	end

	record.RoleBadge = badge
	return badge
end

local function stopDanger(record)
	if record.DangerTween then
		record.DangerTween:Cancel()
		record.DangerTween = nil
	end
	if record.DangerHighlight and record.DangerHighlight.Parent then
		record.DangerHighlight:Destroy()
	end
	record.DangerHighlight = nil
	record.LastDangerText = nil
end

local function updateDanger(record, model, text, color)
	if not text then
		stopDanger(record)
		return
	end

	if not record.DangerHighlight or not record.DangerHighlight.Parent then
		local highlight = Instance.new("Highlight")
		highlight.Name = "PortraitDangerReadability"
		highlight.Adornee = model
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.93
		highlight.OutlineTransparency = 0.08
		highlight.Parent = model
		record.DangerHighlight = highlight
	end

	local highlight = record.DangerHighlight
	highlight.FillColor = color
	highlight.OutlineColor = color

	if record.LastDangerText ~= text then
		record.LastDangerText = text
		if record.DangerTween then
			record.DangerTween:Cancel()
			record.DangerTween = nil
		end

		if not reducedEffects() then
			highlight.OutlineTransparency = 0.08
			local tween = TweenService:Create(
				highlight,
				TweenInfo.new(
					0.32,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true
				),
				{ OutlineTransparency = 0.48 }
			)
			record.DangerTween = tween
			tween:Play()
		else
			highlight.OutlineTransparency = 0.20
		end
	end
end

local function findBillboard(model)
	local billboard = model:FindFirstChild("EnemyStatusBillboard")
	return billboard and billboard:IsA("BillboardGui") and billboard or nil
end

local function createRecord(model)
	local record = {
		Model = model,
		Original = setmetatable({}, { __mode = "k" }),
		RoleBadge = nil,
		DangerHighlight = nil,
		DangerTween = nil,
		LastDangerText = nil,
	}
	records[model] = record
	return record
end

local function adaptBillboard(record, model, billboard, important)
	local name = billboard:FindFirstChild("EnemyName")
	local track = billboard:FindFirstChild("HealthTrack")
	local healthText = billboard:FindFirstChild("HealthText")

	setProperty(record, billboard, "Size", UDim2.fromOffset(important and 174 or 154, important and 58 or 48))
	setProperty(record, billboard, "MaxDistance", important and IMPORTANT_MAX_DISTANCE or COMMON_MAX_DISTANCE)

	if name and name:IsA("TextLabel") then
		setProperty(record, name, "TextSize", scaledText(important and 13 or 11))
		setProperty(record, name, "Size", UDim2.new(1, -4, 0, important and 18 or 16))
		setProperty(record, name, "TextStrokeTransparency", important and 0.18 or 0.28)
	end

	if track and track:IsA("Frame") then
		setProperty(record, track, "Position", UDim2.fromOffset(important and 11 or 12, important and 21 or 19))
		setProperty(record, track, "Size", UDim2.new(1, important and -22 or -24, 0, important and 10 or 8))
	end

	if healthText and healthText:IsA("TextLabel") then
		setProperty(record, healthText, "Position", UDim2.fromOffset(2, important and 31 or 29))
		setProperty(record, healthText, "TextSize", scaledText(important and 9 or 8))
	end
end

local function shouldShow(record, model, billboard, important)
	local avatarRoot = playerRoot()
	local targetRoot = getRoot(model)
	local humanoid = getHumanoid(model)
	if not avatarRoot or not targetRoot or not humanoid or humanoid.Health <= 0 then
		return false
	end

	if model:GetAttribute("ObjectiveAmbushHidden") == true
		or model:GetAttribute("SimulationActive") == false
		or model:GetAttribute("ObjectiveTargetCompleted") == true
	then
		return false
	end

	local distance = (targetRoot.Position - avatarRoot.Position).Magnitude
	local maximum = important and IMPORTANT_MAX_DISTANCE or COMMON_MAX_DISTANCE
	return distance <= maximum
end

local function updateModel(model)
	if not active or not model.Parent or not model:IsA("Model") then
		return
	end
	if Players:GetPlayerFromCharacter(model) then
		return
	end

	local billboard = findBillboard(model)
	if not billboard then
		return
	end

	local record = records[model] or createRecord(model)
	local roleText, roleColor, important = roleInfo(model)
	local dangerText, dangerColor = dangerInfo(model)
	if dangerText then
		important = true
	end

	adaptBillboard(record, model, billboard, important)

	local badge = ensureRoleBadge(record, billboard)
	badge.TextSize = scaledText(8)
	if dangerText then
		badge.Visible = true
		badge.Text = dangerText
		badge.TextColor3 = dangerColor
		badge.BackgroundTransparency = 0.08
	elseif roleText then
		badge.Visible = true
		badge.Text = roleText
		badge.TextColor3 = roleColor
		badge.BackgroundTransparency = 0.22
	else
		badge.Visible = false
	end

	updateDanger(record, model, dangerText, dangerColor)
	billboard.Enabled = shouldShow(record, model, billboard, important)
end

local function updateAll()
	for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
		updateModel(model)
	end

	for model, record in pairs(records) do
		if not model.Parent then
			stopDanger(record)
			records[model] = nil
		end
	end
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	active = true
	player:SetAttribute("DungeonPortraitEnemyReadabilityReady", true)
	player:SetAttribute("DungeonPortraitEnemyReadabilityActive", true)
	player:SetAttribute("DungeonPortraitEnemyReadabilityVersion", VERSION)
	player:SetAttribute(
		"DungeonPortraitEnemyReadabilityPolicy",
		"RoleBadgeProtectedReasonDangerWindupDistanceV1"
	)
	updateAll()
end

local function deactivate()
	if not active then
		return
	end

	active = false
	for model, record in pairs(records) do
		restoreRecord(record)
		records[model] = nil
	end

	player:SetAttribute("DungeonPortraitEnemyReadabilityActive", false)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(function(model)
	if active then
		task.defer(function()
			-- EnemyCombatFeedback cria o Billboard localmente apos a tag;
			-- alguns frames de folga evitam corrida de inicializacao.
			for _ = 1, 12 do
				if not model.Parent then
					return
				end
				if findBillboard(model) then
					updateModel(model)
					return
				end
				task.wait(0.05)
			end
		end)
	end
end)

CollectionService:GetInstanceRemovedSignal("CombatTarget"):Connect(function(model)
	local record = records[model]
	if record then
		restoreRecord(record)
		records[model] = nil
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

RunService.Heartbeat:Connect(function(deltaTime)
	if not active then
		return
	end

	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0

	updateAll()
end)

player:SetAttribute("DungeonPortraitEnemyReadabilityControllerLoaded", true)
player:SetAttribute("DungeonPortraitEnemyReadabilityVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal(
		"DungeonInputProfileReady"
	):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(deactivate)
