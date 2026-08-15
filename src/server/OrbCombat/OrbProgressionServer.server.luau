local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local AttackStyles = require(ReplicatedStorage:WaitForChild("AttackStyles"))
local choiceEvent = orbFolder:WaitForChild("OrbChoiceEvent")
local choiceRequest = orbFolder:WaitForChild("OrbChoiceRequest")

local queues = setmetatable({}, { __mode = "k" })
local queuedMilestones = setmetatable({}, { __mode = "k" })
local selecting = setmetatable({}, { __mode = "k" })
local protectedStates = setmetatable({}, { __mode = "k" })
local random = Random.new()

local function claimedAttribute(level)
	return string.format("OrbChoiceLevel%dClaimed", level)
end

local function getOrbLevel(player, orbName)
	local attribute = OrbConfig.GetLevelAttribute(orbName)
	return attribute and OrbConfig.CleanLevel(player:GetAttribute(attribute)) or 0
end

local function setOrbLevel(player, orbName, level)
	local attribute = OrbConfig.GetLevelAttribute(orbName)
	if attribute then
		player:SetAttribute(attribute, OrbConfig.CleanLevel(level))
	end
end

local function getOrbXP(player, orbName)
	local attribute = OrbConfig.GetOrbLevelXPAttribute(orbName)
	return attribute and math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0)) or 0
end

local function setOrbXP(player, orbName, value)
	local attribute = OrbConfig.GetOrbLevelXPAttribute(orbName)
	if attribute then
		player:SetAttribute(attribute, math.max(0, math.floor(tonumber(value) or 0)))
	end
end

local function restoreChoiceProtection(player)
	local state = protectedStates[player]
	if not state then
		player:SetAttribute("OrbChoiceProtected", false)
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local restoredWalkSpeed = tonumber(state.WalkSpeed) or 0
		if restoredWalkSpeed <= 0 then
			restoredWalkSpeed = tonumber(humanoid:GetAttribute("SprintBaseWalkSpeed")) or 16
		end
		humanoid.WalkSpeed = restoredWalkSpeed
		humanoid.AutoRotate = state.AutoRotate ~= false
		humanoid.PlatformStand = false
		humanoid.Sit = false
		if humanoid.UseJumpPower then
			humanoid.JumpPower = math.max(tonumber(state.JumpPower) or 0, 1)
		else
			humanoid.JumpHeight = math.max(tonumber(state.JumpHeight) or 0, 1)
		end
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if character then
		local forceField = character:FindFirstChild("OrbChoiceProtection")
		if forceField then forceField:Destroy() end
	end
	protectedStates[player] = nil
	player:SetAttribute("OrbChoiceProtected", false)
	workspace:SetAttribute(
		"DungeonCombatReacquireSerial",
		(tonumber(workspace:GetAttribute("DungeonCombatReacquireSerial")) or 0) + 1
	)
	player:SetAttribute(
		"DungeonCombatReacquireUserId",
		player.UserId
	)
end

local function applyChoiceProtection(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	if not protectedStates[player] then
		protectedStates[player] = {
			WalkSpeed = humanoid.WalkSpeed,
			AutoRotate = humanoid.AutoRotate,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
		}
	end
	if humanoid.PlatformStand then
		humanoid.PlatformStand = false
	end
	if not character:FindFirstChild("OrbChoiceProtection") then
		local forceField = Instance.new("ForceField")
		forceField.Name = "OrbChoiceProtection"
		forceField.Visible = false
		forceField.Parent = character
	end
	player:SetAttribute("OrbChoiceProtected", true)
end

local function initializePlayer(player)
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		if player:GetAttribute(OrbConfig.GetLevelAttribute(orbName)) == nil then
			setOrbLevel(player, orbName, 0)
		end
		if player:GetAttribute(OrbConfig.GetOrbLevelXPAttribute(orbName)) == nil then
			setOrbXP(player, orbName, 0)
		end
		local orb = OrbConfig.GetOrb(orbName)
		for _, upgrade in ipairs(orb.SpecializedUpgrades or {}) do
			local attribute = "OrbUpgrade_" .. upgrade.Id
			if player:GetAttribute(attribute) == nil then player:SetAttribute(attribute, 0) end
		end
	end
	for _, level in ipairs(OrbConfig.ChoiceLevels) do
		local attribute = claimedAttribute(level)
		if player:GetAttribute(attribute) == nil then player:SetAttribute(attribute, false) end
	end
	if player:GetAttribute("OrbChoicesCompleted") == nil then player:SetAttribute("OrbChoicesCompleted", 0) end
	if player:GetAttribute("OrbChoiceSerial") == nil then player:SetAttribute("OrbChoiceSerial", 0) end
	if player:GetAttribute("PendingOrbChoiceLevel") == nil then player:SetAttribute("PendingOrbChoiceLevel", 0) end
	if player:GetAttribute("OrbChoiceState") == nil then player:SetAttribute("OrbChoiceState", "None") end
	player:SetAttribute("OrbChoiceProtected", false)
	player:SetAttribute("OrbProgressionVersion", OrbConfig.Version)
	player:SetAttribute("OrbProgressionPolicy", "WeightedNewOrbChancePerLevel")
	if player:GetAttribute("EquippedOrbs") == nil then
		local equippedOrbNames = {}
		for _, orbName in ipairs(OrbConfig.OrbOrder) do
			if getOrbLevel(player, orbName) > 0 and #equippedOrbNames < (OrbConfig.MaxEquippedOrbs or 2) then
				table.insert(equippedOrbNames, orbName)
			end
		end
		player:SetAttribute("EquippedOrbs", table.concat(equippedOrbNames, ","))
		player:SetAttribute("EquippedOrb", equippedOrbNames[1])
		player:SetAttribute("EquippedOrb2", equippedOrbNames[2])
	end
end

local function createNewOrbOption(style, orbName, definition)
	return { ChoiceType = "NewOrb", StyleId = style.Id, AttackType = style.AttackType, Orb = orbName, AssetName = definition.AssetName, DisplayName = style.DisplayName, Description = style.Description .. string.format("  |  CUSTO: %d XP", OrbConfig.GetOrbLevelXPCost(0)), Icon = style.Icon, Color = style.Color, CurrentLevel = 0, NextLevel = 1, XPCost = OrbConfig.GetOrbLevelXPCost(0), Kind = "NOVO ORB", AttributeLabel = "NOVA HABILIDADE", Available = true }
end

local function createUpgradeOption(style, orbName, definition, currentLevel, upgrade)
	local current = tonumber(upgrade.CurrentValue) or 0
	local nextValue = tonumber(upgrade.NextValue) or 0
	local xpCost = OrbConfig.GetOrbLevelXPCost(currentLevel)
	return { ChoiceType = "SpecializedUpgrade", UpgradeId = upgrade.UpgradeId, StyleId = style.Id, AttackType = style.AttackType, Orb = orbName, AssetName = definition.AssetName, DisplayName = upgrade.Name, Description = upgrade.Description .. "  " .. string.format("%g → %g", current, nextValue) .. string.format("  |  CUSTO: %d XP", xpCost), Icon = style.Icon, Color = upgrade.Color or style.Color, CurrentLevel = currentLevel, NextLevel = currentLevel + 1, XPCost = xpCost, Kind = "UPGRADE ESPECIALIZADO", AttributeLabel = upgrade.AttributeLabel, Available = true }
end

local function buildOptions(player)
	local upgradeOptions = {}
	local newOrbOptions = {}
	for _, styleId in ipairs(AttackStyles.Order) do
		local style = AttackStyles.Get(styleId)
		local orbName = style and style.OrbName
		local definition = orbName and OrbConfig.GetOrb(orbName)
		if style and definition then
			local currentLevel = getOrbLevel(player, orbName)
			if currentLevel > 0 and currentLevel < OrbConfig.MaxOrbLevel then
				for _, upgrade in ipairs(OrbConfig.GetUpgradeOptions(orbName, currentLevel, player)) do table.insert(upgradeOptions, createUpgradeOption(style, orbName, definition, currentLevel, upgrade)) end
			elseif currentLevel == 0 then
				table.insert(newOrbOptions, createNewOrbOption(style, orbName, definition))
			end
		end
	end
	local options = {}
	local function takeRandom(source)
		if #source == 0 then return nil end
		return table.remove(source, random:NextInteger(1, #source))
	end
	while #options < 3 and #upgradeOptions > 0 do table.insert(options, takeRandom(upgradeOptions)) end
	local ownedCount = 0
	for _, orbName in ipairs(OrbConfig.OrbOrder) do if getOrbLevel(player, orbName) > 0 then ownedCount += 1 end end
	local maxEquippedOrbs = OrbConfig.MaxEquippedOrbs or 2
	local newChance = ({ [0] = 1, [1] = 0.025 })[ownedCount] or 0
	if ownedCount >= maxEquippedOrbs then
		table.clear(newOrbOptions)
	end
	if ownedCount == 0 then
		while #options < 3 and #newOrbOptions > 0 do
			table.insert(options, takeRandom(newOrbOptions))
		end
		return options
	end
	local newOrbAllowed = #newOrbOptions > 0 and random:NextNumber() <= newChance
	if newOrbAllowed then
		table.insert(options, takeRandom(newOrbOptions))
	end
	while #options < 3 and #upgradeOptions > 0 do
		table.insert(options, takeRandom(upgradeOptions))
	end
	return options
end

local function presentNext(player)
	if player.Parent ~= Players or (tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0) > 0 then return end
	local queue = queues[player]
	local milestone = queue and table.remove(queue, 1)
	if not milestone then return end
	local serial = (tonumber(player:GetAttribute("OrbChoiceSerial")) or 0) + 1
	player:SetAttribute("PendingOrbChoiceLevel", milestone)
	player:SetAttribute("OrbChoiceSerial", serial)
	player:SetAttribute("OrbChoiceState", "WaitingForSelection")
	applyChoiceProtection(player)
	choiceEvent:FireClient(player, { Action = "Offer", MilestoneLevel = milestone, Serial = serial, Options = buildOptions(player) })
end

local function enqueueMilestone(player, milestone)
	if player:GetAttribute(claimedAttribute(milestone)) == true then return end
	local set = queuedMilestones[player] or {}
	queuedMilestones[player] = set
	if set[milestone] then return end
	set[milestone] = true
	local queue = queues[player] or {}
	queues[player] = queue
	table.insert(queue, milestone)
	table.sort(queue)
	presentNext(player)
end

local function synchronizeMilestones(player)
	local currentLevel = math.max(1, math.floor(tonumber(player:GetAttribute("PlayerLevel")) or 1))
	for _, milestone in ipairs(OrbConfig.ChoiceLevels) do
		if currentLevel >= milestone and player:GetAttribute(claimedAttribute(milestone)) ~= true then enqueueMilestone(player, milestone) end
	end
end

local function bindPlayer(player)
	initializePlayer(player)
	queues[player] = queues[player] or {}
	queuedMilestones[player] = queuedMilestones[player] or {}
	player.CharacterAdded:Connect(function(character)
		if (tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0) > 0 then character:WaitForChild("Humanoid", 5); applyChoiceProtection(player) end
	end)
	player:GetAttributeChangedSignal("PlayerLevel"):Connect(function() synchronizeMilestones(player) end)
	player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(function() synchronizeMilestones(player) end)
	task.defer(synchronizeMilestones, player)
end

choiceRequest.OnServerEvent:Connect(function(player, request)
	if selecting[player] or type(request) ~= "table" then return end
	selecting[player] = true
	local pendingLevel = math.floor(tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0)
	local serial = math.floor(tonumber(player:GetAttribute("OrbChoiceSerial")) or 0)
	local requestedLevel = math.floor(tonumber(request.MilestoneLevel) or 0)
	local requestedSerial = math.floor(tonumber(request.Serial) or 0)
	local styleId = AttackStyles.Normalize(request.StyleId)
	local style = styleId and AttackStyles.Get(styleId)
	local orbName = style and OrbConfig.NormalizeOrb(style.OrbName)
	if not orbName then orbName = OrbConfig.NormalizeOrb(request.Orb); style = orbName and AttackStyles.GetByOrbName(orbName); styleId = style and style.Id end
	local choiceType = request.ChoiceType
	local upgrade = choiceType == "SpecializedUpgrade" and OrbConfig.GetSpecializedUpgrade(orbName, request.UpgradeId) or nil
	if pendingLevel <= 0 or requestedLevel ~= pendingLevel or requestedSerial ~= serial or not styleId or not style or not orbName then
		choiceEvent:FireClient(player, { Action = "Rejected", Reason = "InvalidOrExpiredChoice" }); restoreChoiceProtection(player); selecting[player] = nil; return
	end
	local currentLevel = getOrbLevel(player, orbName)
	local upgradeXPCost = OrbConfig.GetOrbLevelXPCost(currentLevel)
	local orbXP = getOrbXP(player, orbName)
	local equippedCount = 0
	for _, ownedOrbName in ipairs(OrbConfig.OrbOrder) do
		if getOrbLevel(player, ownedOrbName) > 0 then
			equippedCount += 1
		end
	end
	if choiceType == "NewOrb" then
		if currentLevel ~= 0 or equippedCount >= (OrbConfig.MaxEquippedOrbs or 2) then choiceEvent:FireClient(player, { Action = "Rejected", Reason = "OrbAlreadyOwned" }); restoreChoiceProtection(player); selecting[player] = nil; return end
	elseif choiceType == "SpecializedUpgrade" then
		local upgradeAttribute = "OrbUpgrade_" .. request.UpgradeId
		local upgradeCount = math.floor(tonumber(player:GetAttribute(upgradeAttribute)) or 0)
		if not upgrade or currentLevel <= 0 or currentLevel >= OrbConfig.MaxOrbLevel or upgradeCount >= currentLevel then choiceEvent:FireClient(player, { Action = "Rejected", Reason = "InvalidSpecializedUpgrade" }); restoreChoiceProtection(player); selecting[player] = nil; return end
		if orbXP < upgradeXPCost then choiceEvent:FireClient(player, { Action = "Rejected", Reason = "InsufficientOrbXP" }); restoreChoiceProtection(player); selecting[player] = nil; return end
	else
		choiceEvent:FireClient(player, { Action = "Rejected", Reason = "InvalidChoiceType" }); restoreChoiceProtection(player); selecting[player] = nil; return
	end
	if choiceType == "NewOrb" then
		setOrbXP(player, orbName, 0)
	elseif choiceType == "SpecializedUpgrade" then
		setOrbXP(player, orbName, orbXP - upgradeXPCost)
	end
	setOrbLevel(player, orbName, currentLevel + 1)
	if choiceType == "SpecializedUpgrade" then player:SetAttribute("OrbUpgrade_" .. upgrade.Id, math.floor(tonumber(player:GetAttribute("OrbUpgrade_" .. upgrade.Id)) or 0) + 1) end
	local equippedOrbNames = {}
	for _, ownedOrbName in ipairs(OrbConfig.OrbOrder) do
		if getOrbLevel(player, ownedOrbName) > 0 then
			table.insert(equippedOrbNames, ownedOrbName)
		end
	end
	player:SetAttribute("EquippedOrbs", table.concat(equippedOrbNames, ","))
	player:SetAttribute("EquippedOrb", equippedOrbNames[1] or orbName)
	player:SetAttribute("EquippedOrb2", equippedOrbNames[2])
	player:SetAttribute(claimedAttribute(pendingLevel), true)
	player:SetAttribute("OrbChoicesCompleted", (tonumber(player:GetAttribute("OrbChoicesCompleted")) or 0) + 1)
	player:SetAttribute("LastOrbChoice", orbName)
	player:SetAttribute("LastOrbChoiceKind", choiceType)
	player:SetAttribute("LastOrbChoiceUpgradeId", choiceType == "SpecializedUpgrade" and upgrade.Id or nil)
	player:SetAttribute("LastOrbChoiceLevel", currentLevel + 1)
	player:SetAttribute("LastOrbChoiceAt", workspace:GetServerTimeNow())
	workspace:SetAttribute("DungeonCombatReacquireSerial", (workspace:GetAttribute("DungeonCombatReacquireSerial") or 0) + 1)
	player:SetAttribute("PendingOrbChoiceLevel", 0)
	player:SetAttribute("OrbChoiceState", "Selected")
	restoreChoiceProtection(player)
	local set = queuedMilestones[player]
	if set then set[pendingLevel] = nil end
	choiceEvent:FireClient(player, { Action = "Selected", StyleId = styleId, AttackType = style.AttackType, Orb = orbName, OrbLevel = currentLevel + 1, ChoiceType = choiceType, UpgradeId = choiceType == "SpecializedUpgrade" and upgrade.Id or nil, MilestoneLevel = pendingLevel })
	selecting[player] = nil
	task.defer(presentNext, player)
end)

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	restoreChoiceProtection(player)
	queues[player] = nil
	queuedMilestones[player] = nil
	selecting[player] = nil
	protectedStates[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
workspace:SetAttribute("DungeonOrbProgressionReady", true)
workspace:SetAttribute("DungeonOrbProgressionVersion", OrbConfig.Version)
workspace:SetAttribute("DungeonOrbChoiceLevels", table.concat(OrbConfig.ChoiceLevels, ","))
print("[OrbProgression] Weighted multi-level Orb choices ready")