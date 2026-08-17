local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local AttackStyles = require(ReplicatedStorage:WaitForChild("AttackStyles"))
local PlayerDataService = require(
	ServerScriptService:WaitForChild("BlockParkour"):WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local UpgradeChoiceProtectionService = require(
	ServerScriptService:WaitForChild("MVPSystems"):WaitForChild("UpgradeChoiceProtectionService")
)
local choiceEvent = orbFolder:WaitForChild("OrbChoiceEvent")
local choiceRequest = orbFolder:WaitForChild("OrbChoiceRequest")

local queues = setmetatable({}, { __mode = "k" })
local queuedMilestones = setmetatable({}, { __mode = "k" })
local selecting = setmetatable({}, { __mode = "k" })
local offeredOptions = setmetatable({}, { __mode = "k" })
local random = Random.new()
local lastClearSerial = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonIslandClearFeedbackSerial")) or 0))
local saveScheduled = setmetatable({}, { __mode = "k" })

local function claimedAttribute(level)
	return string.format("OrbChoiceLevel%dClaimed", level)
end

local function getOrbLevel(player, orbName)
	local attribute = OrbConfig.GetLevelAttribute(orbName)
	return attribute and OrbConfig.CleanLevel(player:GetAttribute(attribute)) or 0
end

local function ownedOrbCount(player)
	local count = 0
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		if getOrbLevel(player, orbName) > 0 then
			count += 1
		end
	end
	return count
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

local function ensureMilestoneAbilities(player, orbName, level)
	for abilityLevel = 2, OrbConfig.CleanLevel(level) do
		local ability, rank = OrbConfig.GetMilestoneAbility(orbName, abilityLevel)
		if ability then
			local attribute = "OrbUpgrade_" .. ability.Id
			local currentRank = math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0))
			player:SetAttribute(attribute, math.max(currentRank, rank))
		end
	end
end

local function ownedEquippedOrbs(player)
	local result = {}
	local seen = {}
	for orbName in string.gmatch(tostring(player:GetAttribute("EquippedOrbs") or ""), "[^,]+") do
		if OrbConfig.GetOrb(orbName) and getOrbLevel(player, orbName) > 0 and not seen[orbName] and #result < (OrbConfig.MaxEquippedOrbs or 2) then
			seen[orbName] = true
			table.insert(result, orbName)
		end
	end
	return result
end

local function persistOrbProgression(player)
	local orbs = {}
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		local definition = OrbConfig.GetOrb(orbName)
		local abilities = {}
		for _, upgrade in ipairs(definition.SpecializedUpgrades or {}) do
			abilities[upgrade.Id] = math.max(0, math.floor(tonumber(player:GetAttribute("OrbUpgrade_" .. upgrade.Id)) or 0))
		end
		orbs[orbName] = {
			Level = getOrbLevel(player, orbName),
			XP = getOrbXP(player, orbName),
			Abilities = abilities,
		}
	end

	local claimedMilestones = {}
	for _, level in ipairs(OrbConfig.ChoiceLevels) do
		if player:GetAttribute(claimedAttribute(level)) == true then
			claimedMilestones[level] = true
		end
	end

	return PlayerDataService.SetOrbProgression(player, {
		Version = OrbConfig.Version,
		Orbs = orbs,
		EquippedOrbs = ownedEquippedOrbs(player),
		ClaimedMilestones = claimedMilestones,
		ChoicesCompleted = math.max(0, math.floor(tonumber(player:GetAttribute("OrbChoicesCompleted")) or 0)),
	})
end

local function scheduleOrbSave(player)
	if saveScheduled[player] then
		return
	end
	saveScheduled[player] = true
	task.delay(4, function()
		saveScheduled[player] = nil
		if persistOrbProgression(player) then
			PlayerDataService.Save(player, false)
		end
	end)
end

local function restoreOrbProgression(player)
	PlayerDataService.Load(player)
	local saved = PlayerDataService.GetOrbProgression(player)
	if not saved then
		return
	end

	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		local record = saved.Orbs[orbName] or {}
		setOrbLevel(player, orbName, record.Level)
		setOrbXP(player, orbName, record.XP)
		local definition = OrbConfig.GetOrb(orbName)
		for _, upgrade in ipairs(definition.SpecializedUpgrades or {}) do
			player:SetAttribute("OrbUpgrade_" .. upgrade.Id, math.max(0, math.floor(tonumber(record.Abilities and record.Abilities[upgrade.Id]) or 0)))
		end
	end

	for _, level in ipairs(OrbConfig.ChoiceLevels) do
		player:SetAttribute(claimedAttribute(level), saved.ClaimedMilestones[level] == true)
	end
	player:SetAttribute("OrbChoicesCompleted", saved.ChoicesCompleted)
	if #saved.EquippedOrbs > 0 then
		player:SetAttribute("EquippedOrbs", table.concat(saved.EquippedOrbs, ","))
		player:SetAttribute("EquippedOrb", saved.EquippedOrbs[1])
		player:SetAttribute("EquippedOrb2", saved.EquippedOrbs[2])
	end
end

-- A escolha de Orb nao deve modificar o Humanoid. A antiga protecao criava um
-- ForceField real, que bloqueava todo dano dos mobs e, ao restaurar estados
-- durante um congelamento, podia deixar o JumpHeight em 1.
local function removeLegacyChoiceForceField(player)
	local character = player.Character
	local forceField = character and character:FindFirstChild("OrbChoiceProtection")
	if forceField and forceField:IsA("ForceField") then
		forceField:Destroy()
	end
end

local function restoreChoiceProtection(player)
	removeLegacyChoiceForceField(player)
	player:SetAttribute("OrbChoiceProtected", false)
	UpgradeChoiceProtectionService.End(player, "OrbChoice")
end

local function applyChoiceProtection(player)
	-- Mantem somente o estado logico para pausar o Orb enquanto a escolha esta
	-- aberta. Nao cria ForceField nem salva/restaura WalkSpeed ou pulo.
	removeLegacyChoiceForceField(player)
	player:SetAttribute("OrbChoiceProtected", true)
	UpgradeChoiceProtectionService.Begin(player, "OrbChoice")
end

local function initializePlayer(player)
	restoreOrbProgression(player)
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
		ensureMilestoneAbilities(player, orbName, getOrbLevel(player, orbName))
	end
	for _, level in ipairs(OrbConfig.ChoiceLevels) do
		local attribute = claimedAttribute(level)
		if player:GetAttribute(attribute) == nil then player:SetAttribute(attribute, false) end
	end
	if player:GetAttribute("OrbChoicesCompleted") == nil then player:SetAttribute("OrbChoicesCompleted", 0) end
	if player:GetAttribute("OrbChoiceSerial") == nil then player:SetAttribute("OrbChoiceSerial", 0) end
	if player:GetAttribute("PendingOrbChoiceLevel") == nil then player:SetAttribute("PendingOrbChoiceLevel", 0) end
	if player:GetAttribute("OrbChoiceState") == nil then player:SetAttribute("OrbChoiceState", "None") end
	if player:GetAttribute("OrbChoiceSafeMomentSerial") == nil then player:SetAttribute("OrbChoiceSafeMomentSerial", 0) end
	if player:GetAttribute("OrbChoiceLastPresentedSafeMomentSerial") == nil then player:SetAttribute("OrbChoiceLastPresentedSafeMomentSerial", 0) end
	if player:GetAttribute("OrbChoiceSafeIslandIndex") == nil then player:SetAttribute("OrbChoiceSafeIslandIndex", 0) end
	removeLegacyChoiceForceField(player)
	player:SetAttribute("OrbChoiceProtected", false)
	player:SetAttribute("OrbProgressionVersion", OrbConfig.Version)
	player:SetAttribute("OrbProgressionPolicy", "FirstOrbGuaranteed_RareAdditionalOrb")
	player:SetAttribute("OrbFirstChoiceLevel", 2)
	player:SetAttribute("OrbFirstChoiceGuaranteed", true)
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

local function choiceIsSafe(player)
	local transportState = tostring(player:GetAttribute("DungeonAssistedTransportState") or "Idle")
	if transportState == "Flying"
		or transportState == "Landing"
		or player:GetAttribute("DungeonAssistedTransportActive") == true
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
	then
		return false
	end

	local safeMomentSerial = math.max(0, math.floor(tonumber(player:GetAttribute("OrbChoiceSafeMomentSerial")) or 0))
	local presentedMomentSerial = math.max(0, math.floor(tonumber(player:GetAttribute("OrbChoiceLastPresentedSafeMomentSerial")) or 0))
	local currentIsland = math.max(0, math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0))
	local safeIsland = math.max(0, math.floor(tonumber(player:GetAttribute("OrbChoiceSafeIslandIndex")) or 0))
	return safeMomentSerial > presentedMomentSerial
		and currentIsland > 0
		and currentIsland == safeIsland
end

local function buildOptions(player)
	local options = {}
	local ownedCount = 0
	local newOrbCandidates = {}
	local maxEquippedOrbs = OrbConfig.MaxEquippedOrbs or 2
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		if getOrbLevel(player, orbName) > 0 then
			ownedCount += 1
		end
	end

	for _, styleId in ipairs(AttackStyles.Order) do
		local style = AttackStyles.Get(styleId)
		local orbName = style and style.OrbName
		local definition = orbName and OrbConfig.GetOrb(orbName)
		if style and definition then
			local currentLevel = getOrbLevel(player, orbName)
			if currentLevel == 0 and ownedCount < maxEquippedOrbs then
				table.insert(newOrbCandidates, { style = style, orbName = orbName, definition = definition })
			elseif currentLevel > 0 and currentLevel < OrbConfig.MaxOrbLevel then
				table.insert(options, {
					ChoiceType = "MilestoneUpgrade",
					StyleId = style.Id,
					AttackType = style.AttackType,
					Orb = orbName,
					AssetName = definition.AssetName,
					DisplayName = definition.DisplayName,
					Description = definition.Description,
					Icon = style.Icon,
					Color = style.Color,
					CurrentLevel = currentLevel,
					NextLevel = currentLevel + 1,
					XPCost = 0,
					Kind = "UPGRADE DE NIVEL",
					AttributeLabel = "RECOMPENSA DE LEVEL UP",
					Available = true,
				})
			end
		end
	end

	-- A primeira escolha sempre apresenta os Orbs disponiveis. A partir do
	-- segundo, somente uma recompensa rara pode acrescentar um novo Orb.
	if ownedCount == 0 then
		for _, candidate in ipairs(newOrbCandidates) do
			table.insert(options, createNewOrbOption(candidate.style, candidate.orbName, candidate.definition))
		end
	elseif ownedCount < maxEquippedOrbs and #newOrbCandidates > 0 then
		local chance = math.clamp(tonumber(OrbConfig.AdditionalOrbChancePerMilestone) or 0.015, 0, 1)
		if random:NextNumber() < chance then
			local candidate = newOrbCandidates[random:NextInteger(1, #newOrbCandidates)]
			table.insert(options, createNewOrbOption(candidate.style, candidate.orbName, candidate.definition))
		end
	end
	return options
end

local function presentNext(player)
	if player.Parent ~= Players or (tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0) > 0 then return end
	local queue = queues[player]
	if not queue or #queue == 0 then return end
	if not choiceIsSafe(player) then
		player:SetAttribute("OrbChoiceState", "WaitingForSafeMoment")
		return
	end
	while queue and #queue > 0 do
		local milestone = table.remove(queue, 1)
		local options = buildOptions(player)
		local set = queuedMilestones[player]
		if #options == 0 then
			-- Nao ha melhoria disponivel e a tentativa rara nao aconteceu. Esta
			-- recompensa e consumida sem abrir uma tela vazia para o jogador.
			player:SetAttribute(claimedAttribute(milestone), true)
			if set then set[milestone] = nil end
			continue
		end

		local serial = (tonumber(player:GetAttribute("OrbChoiceSerial")) or 0) + 1
		local byOrb = {}
		for _, option in ipairs(options) do
			byOrb[option.Orb] = option
		end
		offeredOptions[player] = { Serial = serial, ByOrb = byOrb }
		player:SetAttribute("PendingOrbChoiceLevel", milestone)
		player:SetAttribute("OrbChoiceSerial", serial)
		player:SetAttribute("OrbChoiceState", "WaitingForSelection")
		player:SetAttribute("OrbChoiceLastPresentedSafeMomentSerial", player:GetAttribute("OrbChoiceSafeMomentSerial"))
		applyChoiceProtection(player)
		choiceEvent:FireClient(player, { Action = "Offer", MilestoneLevel = milestone, Serial = serial, Options = options })
		return
	end
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
		if currentLevel >= milestone and player:GetAttribute(claimedAttribute(milestone)) ~= true then
			-- Migracao segura: quem ja possui um Orb nao recebe uma melhoria extra
			-- apenas porque a primeira escolha passou a acontecer no nivel 2.
			if milestone == 2 and ownedOrbCount(player) > 0 then
				player:SetAttribute(claimedAttribute(milestone), true)
			else
				enqueueMilestone(player, milestone)
			end
		end
	end
end

local function bindPlayer(player)
	initializePlayer(player)
	queues[player] = queues[player] or {}
	queuedMilestones[player] = queuedMilestones[player] or {}
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		player:GetAttributeChangedSignal(OrbConfig.GetLevelAttribute(orbName)):Connect(function()
			scheduleOrbSave(player)
		end)
		player:GetAttributeChangedSignal(OrbConfig.GetOrbLevelXPAttribute(orbName)):Connect(function()
			scheduleOrbSave(player)
		end)
		for _, upgrade in ipairs((OrbConfig.GetOrb(orbName).SpecializedUpgrades or {})) do
			player:GetAttributeChangedSignal("OrbUpgrade_" .. upgrade.Id):Connect(function()
				scheduleOrbSave(player)
			end)
		end
	end
	for _, level in ipairs(OrbConfig.ChoiceLevels) do
		player:GetAttributeChangedSignal(claimedAttribute(level)):Connect(function()
			scheduleOrbSave(player)
		end)
	end
	for _, attribute in ipairs({ "EquippedOrbs", "EquippedOrb", "EquippedOrb2", "OrbChoicesCompleted" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			scheduleOrbSave(player)
		end)
	end
	player.CharacterAdded:Connect(function(character)
		if (tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0) > 0 then character:WaitForChild("Humanoid", 5); applyChoiceProtection(player) end
	end)
	player:GetAttributeChangedSignal("PlayerLevel"):Connect(function() synchronizeMilestones(player) end)
	player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(function() synchronizeMilestones(player) end)
	task.defer(synchronizeMilestones, player)
end

workspace:GetAttributeChangedSignal("DungeonIslandClearFeedbackSerial"):Connect(function()
	local serial = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonIslandClearFeedbackSerial")) or 0))
	if serial <= lastClearSerial then return end
	lastClearSerial = serial
	local clearedIsland = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonIslandClearFeedbackIsland")) or 0))
	if clearedIsland <= 0 then return end

	for _, player in ipairs(Players:GetPlayers()) do
		local currentIsland = math.max(0, math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0))
		if currentIsland == clearedIsland then
			player:SetAttribute("OrbChoiceSafeMomentSerial", serial)
			player:SetAttribute("OrbChoiceSafeIslandIndex", clearedIsland)
			task.defer(presentNext, player)
		end
	end
end)

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
	if pendingLevel <= 0 or requestedLevel ~= pendingLevel or requestedSerial ~= serial or not styleId or not style or not orbName then
		choiceEvent:FireClient(player, { Action = "Rejected", Reason = "InvalidOrExpiredChoice" }); restoreChoiceProtection(player); selecting[player] = nil; return
	end
	local currentLevel = getOrbLevel(player, orbName)
	local choiceType = request.ChoiceType
	-- Compatibilidade com uma interface que ainda envia somente o nome do Orb.
	if choiceType == nil then
		choiceType = currentLevel == 0 and "NewOrb" or "MilestoneUpgrade"
	end
	local offer = offeredOptions[player]
	local offeredOption = offer and offer.Serial == serial and offer.ByOrb[orbName]
	if not offeredOption or offeredOption.ChoiceType ~= choiceType then
		choiceEvent:FireClient(player, { Action = "Rejected", Reason = "ChoiceNotOffered" })
		selecting[player] = nil
		return
	end
	local upgrade = choiceType == "SpecializedUpgrade" and OrbConfig.GetSpecializedUpgrade(orbName, request.UpgradeId) or nil
	local milestoneAbility
	if choiceType == "MilestoneUpgrade" then
		milestoneAbility = OrbConfig.GetMilestoneAbility(orbName, currentLevel + 1)
	end
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
	elseif choiceType == "MilestoneUpgrade" then
		if currentLevel <= 0 or currentLevel >= OrbConfig.MaxOrbLevel or not milestoneAbility then choiceEvent:FireClient(player, { Action = "Rejected", Reason = "InvalidMilestoneUpgrade" }); restoreChoiceProtection(player); selecting[player] = nil; return end
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
	if choiceType == "MilestoneUpgrade" then
		ensureMilestoneAbilities(player, orbName, currentLevel + 1)
	end
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
	player:SetAttribute("LastOrbChoiceUpgradeId", choiceType == "SpecializedUpgrade" and upgrade.Id or (milestoneAbility and milestoneAbility.Id or nil))
	player:SetAttribute("LastOrbChoiceLevel", currentLevel + 1)
	player:SetAttribute("LastOrbChoiceAt", workspace:GetServerTimeNow())
	player:SetAttribute("PendingOrbChoiceLevel", 0)
	player:SetAttribute("OrbChoiceState", "Selected")
	offeredOptions[player] = nil
	restoreChoiceProtection(player)
	persistOrbProgression(player)
	scheduleOrbSave(player)
	local set = queuedMilestones[player]
	if set then set[pendingLevel] = nil end
	choiceEvent:FireClient(player, { Action = "Selected", StyleId = styleId, AttackType = style.AttackType, Orb = orbName, OrbLevel = currentLevel + 1, ChoiceType = choiceType, UpgradeId = choiceType == "SpecializedUpgrade" and upgrade.Id or (milestoneAbility and milestoneAbility.Id or nil), MilestoneLevel = pendingLevel })
	selecting[player] = nil
	task.defer(presentNext, player)
end)

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	persistOrbProgression(player)
	PlayerDataService.Save(player, true)
	restoreChoiceProtection(player)
	queues[player] = nil
	queuedMilestones[player] = nil
	selecting[player] = nil
	offeredOptions[player] = nil
	saveScheduled[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
workspace:SetAttribute("DungeonOrbProgressionReady", true)
workspace:SetAttribute("DungeonOrbProgressionVersion", OrbConfig.Version)
workspace:SetAttribute("DungeonOrbChoiceLevels", table.concat(OrbConfig.ChoiceLevels, ","))
workspace:SetAttribute("DungeonOrbFirstChoiceLevel", 2)
print("[OrbProgression] Primeiro Orb garantido; Orbs adicionais sao raros")
