--[[
	Infinity Islands - Task 07
	PlayerLevelService V1

	Authoritative run-level progression.

	Player Attributes:
	- PlayerLevel
	- PlayerXP
	- PlayerXPToNextLevel
	- PlayerXPProgress
	- PlayerTotalXP
	- PlayerLevelDamageMultiplier
	- PlayerLevelHealthMultiplier
	- PlayerLevelVersion

	Damage integration:
	The current CombatDamageService already reads:
		RunDamageDealtMultiplier

	For the simplified MVP, PlayerLevel owns that compatibility attribute.
	This prevents us from modifying every weapon/ability separately.

	Health integration:
	The service applies the level multiplier directly to the character Humanoid.
	Base health is captured once per character and never compounded.

	The mob XP pipeline calls:
		PlayerLevelService.AwardXP(player, amount, reason)

	This service intentionally does NOT award XP by itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerLevelConfig = require(
	ReplicatedStorage.Shared.Configs.PlayerLevelConfig
)
local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local UpgradeChoiceProtectionService = require(
	ServerScriptService.MVPSystems:WaitForChild("UpgradeChoiceProtectionService")
)

local PlayerLevelService = {}

local started = false
local generation = 0
local options = {}

local playerConnections =
	setmetatable({}, { __mode = "k" })

local characterConnections =
	setmetatable({}, { __mode = "k" })

local humanoidConnections =
	setmetatable({}, { __mode = "k" })

local damageAttributeGuards =
	setmetatable({}, { __mode = "k" })

local healthPropertyGuards =
	setmetatable({}, { __mode = "k" })

local levelUpSerial = 0
local xpGrantSerial = 0

local function cleanLevel(value)
	return math.clamp(
		math.floor(
			tonumber(value)
				or PlayerLevelConfig.StartingLevel
		),
		PlayerLevelConfig.StartingLevel,
		PlayerLevelConfig.MaximumLevel
	)
end

local function cleanXP(value)
	return math.max(
		0,
		math.floor(tonumber(value) or 0)
	)
end

local function validPlayer(player)
	return player
		and player:IsA("Player")
		and player.Parent == Players
end

local function currentLevel(player)
	return cleanLevel(
		player:GetAttribute("PlayerLevel")
	)
end

local function currentXP(player)
	return cleanXP(
		player:GetAttribute("PlayerXP")
	)
end

local function expectedDamageMultiplier(player)
	return PlayerLevelConfig.GetDamageMultiplier(
		currentLevel(player)
	)
end

local function expectedHealthMultiplier(player)
	return PlayerLevelConfig.GetHealthMultiplier(
		currentLevel(player)
	)
end

local function publishPlayer(player)
	if not validPlayer(player) then
		return
	end

	local level = currentLevel(player)
	local xp = currentXP(player)

	local xpToNext =
		PlayerLevelConfig.GetXPToNextLevel(
			level
		)

	local damageMultiplier =
		PlayerLevelConfig.GetDamageMultiplier(
			level
		)

	local healthMultiplier =
		PlayerLevelConfig.GetHealthMultiplier(
			level
		)

	player:SetAttribute(
		"PlayerLevel",
		level
	)
	player:SetAttribute(
		"PlayerXP",
		xp
	)
	player:SetAttribute(
		"PlayerXPToNextLevel",
		xpToNext
	)
	player:SetAttribute(
		"PlayerXPProgress",
		PlayerLevelConfig.GetProgressRatio(
			level,
			xp
		)
	)

	player:SetAttribute(
		"PlayerLevelDamageMultiplier",
		damageMultiplier
	)
	player:SetAttribute(
		"PlayerLevelHealthMultiplier",
		healthMultiplier
	)

	player:SetAttribute(
		"PlayerLevelVersion",
		PlayerLevelConfig.Version
	)
	player:SetAttribute(
		"PlayerLevelPersistencePolicy",
		PlayerLevelConfig.PersistencePolicy
	)
	player:SetAttribute(
		"PlayerLevelPowerSource",
		"XPLevel"
	)
end

local function enforceDamageMultiplier(player)
	if not validPlayer(player)
		or damageAttributeGuards[player]
	then
		return
	end

	local expected =
		expectedDamageMultiplier(player)

	local current =
		tonumber(
			player:GetAttribute(
				"RunDamageDealtMultiplier"
			)
		)

	if current
		and math.abs(current - expected)
			< 0.0001
	then
		return
	end

	damageAttributeGuards[player] = true

	player:SetAttribute(
		"RunDamageDealtMultiplier",
		expected
	)

	player:SetAttribute(
		"RunDamageDealtMultiplierSource",
		PlayerLevelConfig.Version
	)

	player:SetAttribute(
		"LegacyRunUpgradeDamageSuppressed",
		true
	)

	damageAttributeGuards[player] = nil
end

local function humanoidBaseHealth(humanoid)
	local base =
		tonumber(
			humanoid:GetAttribute(
				"PlayerLevelBaseMaxHealth"
			)
		)

	if base and base > 0 then
		return base
	end

	-- The old RunUpgrade service may have already captured the true pre-upgrade
	-- health. If available, prefer it instead of accidentally treating an old
	-- temporary upgrade as the new baseline.
	local oldRunBase =
		tonumber(
			humanoid:GetAttribute(
				"RunUpgradeBaseMaxHealth"
			)
		)

	if oldRunBase and oldRunBase > 0 then
		base = oldRunBase
	else
		base = math.max(
			1,
			tonumber(humanoid.MaxHealth)
				or 100
		)
	end

	humanoid:SetAttribute(
		"PlayerLevelBaseMaxHealth",
		base
	)

	return base
end

local function desiredMaxHealth(player, humanoid)
	return math.max(
		1,
		math.floor(
			humanoidBaseHealth(humanoid)
				* expectedHealthMultiplier(player)
				+ 0.5
		)
	)
end

local function applyHealth(
	player,
	humanoid,
	healGainedMaximum
)
	if not validPlayer(player)
		or not humanoid
		or not humanoid:IsA("Humanoid")
		or not humanoid.Parent
		or healthPropertyGuards[humanoid]
	then
		return false
	end

	local desired =
		desiredMaxHealth(
			player,
			humanoid
		)

	local currentMax =
		math.max(
			1,
			tonumber(humanoid.MaxHealth)
				or 1
		)

	local currentHealth =
		math.max(
			0,
			tonumber(humanoid.Health)
				or 0
		)

	if desired == currentMax then
		humanoid:SetAttribute(
			"PlayerLevelHealthMultiplier",
			expectedHealthMultiplier(player)
		)
		humanoid:SetAttribute(
			"PlayerLevelApplied",
			currentLevel(player)
		)
		return true
	end

	healthPropertyGuards[humanoid] = true

	local wasAlive =
		currentHealth > 0

	local ratio =
		math.clamp(
			currentHealth / currentMax,
			0,
			1
		)

	local gainedMaximum =
		math.max(
			0,
			desired - currentMax
		)

	humanoid.MaxHealth = desired

	if wasAlive then
		if healGainedMaximum == true then
			humanoid.Health =
				math.min(
					desired,
					currentHealth
						+ gainedMaximum
				)
		else
			humanoid.Health =
				math.min(
					desired,
					math.max(
						1,
						desired * ratio
					)
				)
		end
	end

	humanoid:SetAttribute(
		"PlayerLevelHealthMultiplier",
		expectedHealthMultiplier(player)
	)
	humanoid:SetAttribute(
		"PlayerLevelApplied",
		currentLevel(player)
	)
	humanoid:SetAttribute(
		"PlayerLevelMaxHealth",
		desired
	)

	healthPropertyGuards[humanoid] = nil

	return true
end

local function disconnectHumanoid(humanoid)
	local connection =
		humanoidConnections[humanoid]

	if connection then
		connection:Disconnect()
		humanoidConnections[humanoid] = nil
	end
end

local function bindHumanoid(player, humanoid)
	if not humanoid
		or not humanoid:IsA("Humanoid")
	then
		return
	end

	disconnectHumanoid(humanoid)

	humanoidBaseHealth(humanoid)

	humanoidConnections[humanoid] =
		humanoid
			:GetPropertyChangedSignal(
				"MaxHealth"
			)
			:Connect(function()
				if healthPropertyGuards[humanoid] then
					return
				end

				-- PlayerLevel is the health authority during this MVP.
				task.defer(function()
					if started
						and validPlayer(player)
						and humanoid.Parent
					then
						applyHealth(
							player,
							humanoid,
							false
						)
					end
				end)
			end)

	-- Defer once so old character-init services can finish before the new
	-- level contract becomes authoritative.
	task.defer(function()
		if started
			and validPlayer(player)
			and humanoid.Parent
		then
			applyHealth(
				player,
				humanoid,
				false
			)
		end
	end)
end

local function bindCharacter(player, character)
	if not character then
		return
	end

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)
		or character:WaitForChild(
			"Humanoid",
			8
		)

	if humanoid
		and humanoid:IsA("Humanoid")
	then
		bindHumanoid(
			player,
			humanoid
		)
	end
end

local function applyPower(
	player,
	healGainedMaximum
)
	if not validPlayer(player) then
		return false
	end

	publishPlayer(player)
	enforceDamageMultiplier(player)

	local character =
		player.Character

	local humanoid =
		character
			and character
				:FindFirstChildOfClass(
					"Humanoid"
				)

	if humanoid then
		applyHealth(
			player,
			humanoid,
			healGainedMaximum
		)
	end

	return true
end

local function initializePlayerState(player)
	PlayerDataService.Load(player)
	local saved = PlayerDataService.GetLevelProgress(player)
	if saved then
		player:SetAttribute("PlayerLevel", cleanLevel(saved.Level))
		player:SetAttribute("PlayerXP", cleanXP(saved.XP))
		player:SetAttribute("PlayerTotalXP", cleanXP(saved.TotalXP))
		player:SetAttribute("PlayerLevelUpCount", math.max(0, cleanLevel(saved.Level) - 1))
	else
	local sameVersion =
		player:GetAttribute(
			"PlayerLevelVersion"
		) == PlayerLevelConfig.Version

	if not sameVersion then
		player:SetAttribute(
			"PlayerLevel",
			PlayerLevelConfig.StartingLevel
		)
		player:SetAttribute(
			"PlayerXP",
			0
		)
		player:SetAttribute(
			"PlayerTotalXP",
			0
		)
		player:SetAttribute(
			"PlayerLevelUpCount",
			0
		)
	end
	end

	publishPlayer(player)
end

local function bindPlayer(player)
	if not validPlayer(player) then
		return
	end

	if playerConnections[player] then
		return
	end

	initializePlayerState(player)

	local connections = {}

	table.insert(
		connections,
		player.CharacterAdded:Connect(
			function(character)
				bindCharacter(
					player,
					character
				)
			end
		)
	)

	table.insert(
		connections,
		player:GetAttributeChangedSignal(
			"RunDamageDealtMultiplier"
		):Connect(function()
			if damageAttributeGuards[player] then
				return
			end

			task.defer(function()
				if started
					and validPlayer(player)
				then
					enforceDamageMultiplier(
						player
					)
				end
			end)
		end)
	)

	playerConnections[player] = connections

	if player.Character then
		task.defer(
			bindCharacter,
			player,
			player.Character
		)
	end

	task.defer(
		applyPower,
		player,
		false
	)
end

local function unbindPlayer(player)
	local connections =
		playerConnections[player]

	if connections then
		for _, connection in ipairs(
			connections
		) do
			connection:Disconnect()
		end

		playerConnections[player] = nil
	end

	local character = player.Character
	local humanoid =
		character
			and character
				:FindFirstChildOfClass(
					"Humanoid"
				)

	if humanoid then
		disconnectHumanoid(humanoid)
	end

	damageAttributeGuards[player] = nil
end

local function safeLevelUpCallback(
	player,
	oldLevel,
	newLevel,
	levelsGained,
	reason
)
	local callback = options.OnLevelUp

	if type(callback) ~= "function" then
		return
	end

	local ok, err =
		pcall(
			callback,
			player,
			{
				OldLevel = oldLevel,
				NewLevel = newLevel,
				LevelsGained =
					levelsGained,
				Reason = reason,
				Snapshot =
					PlayerLevelService
						.GetSnapshot(
							player
						),
			}
		)

	if not ok then
		workspace:SetAttribute(
			"DungeonPlayerLevelCallbackError",
			tostring(err)
		)

		warn(
			"[PlayerLevelService] OnLevelUp falhou: "
				.. tostring(err)
		)
	end
end

local function publishWorkspace()
	workspace:SetAttribute(
		"DungeonPlayerLevelReady",
		started
	)
	workspace:SetAttribute(
		"DungeonPlayerLevelVersion",
		PlayerLevelConfig.Version
	)
	workspace:SetAttribute(
		"DungeonPlayerLevelPersistencePolicy",
		PlayerLevelConfig.PersistencePolicy
	)
	workspace:SetAttribute(
		"DungeonPlayerXPBaseRequirement",
		PlayerLevelConfig.BaseXPToNextLevel
	)
	workspace:SetAttribute(
		"DungeonPlayerXPRequirementPerLevel",
		PlayerLevelConfig.XPIncreasePerLevel
	)
	workspace:SetAttribute(
		"DungeonPlayerDamagePerLevel",
		PlayerLevelConfig.DamagePerLevel
	)
	workspace:SetAttribute(
		"DungeonPlayerHealthPerLevel",
		PlayerLevelConfig.HealthPerLevel
	)
	workspace:SetAttribute(
		"DungeonPlayerLevelDamageAuthority",
		"RunDamageDealtMultiplierCompatibility"
	)
	workspace:SetAttribute(
		"DungeonPlayerLevelHealthAuthority",
		"HumanoidMaxHealth"
	)
	workspace:SetAttribute(
		"DungeonPlayerLevelUpSerial",
		levelUpSerial
	)
	workspace:SetAttribute(
		"DungeonPlayerXPGrantSerial",
		xpGrantSerial
	)
end

function PlayerLevelService.Start(startOptions)
	if started then
		return false, "AlreadyStarted"
	end

	PlayerLevelConfig.Validate()

	started = true
	generation += 1

	options =
		type(startOptions) == "table"
			and startOptions
			or {}

	local token = generation

	Players.PlayerAdded:Connect(
		bindPlayer
	)

	Players.PlayerRemoving:Connect(
		unbindPlayer
	)

	for _, player in ipairs(
		Players:GetPlayers()
	) do
		bindPlayer(player)
	end

	publishWorkspace()

	-- Low-frequency reconciliation is intentional. It protects the new MVP
	-- contract while old RunUpgrade code still exists in the repository.
	task.spawn(function()
		while started
			and generation == token
		do
			for _, player in ipairs(
				Players:GetPlayers()
			) do
				applyPower(
					player,
					false
				)
			end

			publishWorkspace()

			task.wait(1)
		end
	end)

	return true
end

function PlayerLevelService.AwardXP(
	player,
	amount,
	reason
)
	if not started then
		return false, "ServiceNotStarted"
	end

	if not validPlayer(player) then
		return false, "InvalidPlayer"
	end

	amount =
		math.clamp(
			math.floor(
				tonumber(amount) or 0
			),
			0,
			PlayerLevelConfig
				.MaximumSingleXPGrant
		)

	if amount <= 0 then
		return false, "InvalidXPAmount"
	end

	-- Quem visita a rota de um amigo pode ajudar e continuar evoluindo, mas nao
	-- recebe a economia completa de uma ilha muito acima do proprio checkpoint.
	local reasonText = tostring(reason or "")
	if string.sub(reasonText, 1, #"MobDefeated:") == "MobDefeated:"
		or string.sub(reasonText, 1, #"XPCollectible:") == "XPCollectible:"
	then
		local modifier = math.clamp(tonumber(player:GetAttribute("PartyCoopXPModifier")) or 1, 0.05, 1)
		if modifier < 1 then
			amount = math.max(1, math.floor(amount * modifier + 0.5))
			player:SetAttribute("LastPartyCoopXPModifier", modifier)
		end
	end

	local oldLevel =
		currentLevel(player)

	local level = oldLevel
	local xp = currentXP(player)

	local totalXP =
		cleanXP(
			player:GetAttribute(
				"PlayerTotalXP"
			)
		)

	totalXP += amount
	xp += amount

	local orbProgression = ReplicatedStorage:FindFirstChild("OrbCombat")
	local orbConfig = orbProgression and require(orbProgression:WaitForChild("OrbConfig"))
	if orbConfig then
		local orbNames = orbConfig.OrbOrder or {}
		local equipped = player:GetAttribute("EquippedOrbs")
		local awardedOrbName
		if typeof(equipped) == "string" and equipped ~= "" then
			for orbName in string.gmatch(equipped, "[^,]+") do
				if orbConfig.GetOrb(orbName) then
					awardedOrbName = orbName
					break
				end
			end
		end
		if awardedOrbName then
			local xpAttribute = orbConfig.GetOrbLevelXPAttribute(awardedOrbName)
			if xpAttribute then
				player:SetAttribute(xpAttribute, math.max(0, math.floor(tonumber(player:GetAttribute(xpAttribute)) or 0)) + amount)
			end
		end
	end

	local levelsGained = 0

	while level
			< PlayerLevelConfig.MaximumLevel
	do
		local needed =
			PlayerLevelConfig.GetXPToNextLevel(
				level
			)

		if needed <= 0 or xp < needed then
			break
		end

		xp -= needed
		level += 1
		levelsGained += 1
	end

	if level
		>= PlayerLevelConfig.MaximumLevel
	then
		level =
			PlayerLevelConfig.MaximumLevel
		xp = 0
	end

	player:SetAttribute(
		"PlayerLevel",
		level
	)
	player:SetAttribute(
		"PlayerXP",
		xp
	)
	player:SetAttribute(
		"PlayerTotalXP",
		totalXP
	)
	PlayerDataService.SetLevelProgress(player, level, xp, totalXP)

	xpGrantSerial += 1

	player:SetAttribute(
		"LastXPGain",
		amount
	)
	player:SetAttribute(
		"LastXPReason",
		tostring(reason or "Unknown")
	)
	player:SetAttribute(
		"LastXPGainAt",
		workspace:GetServerTimeNow()
	)
	player:SetAttribute(
		"PlayerXPGrantSerial",
		xpGrantSerial
	)

	if levelsGained > 0 then
		levelUpSerial += 1

		player:SetAttribute(
			"PlayerLevelUpCount",
			cleanXP(
				player:GetAttribute(
					"PlayerLevelUpCount"
				)
			)
				+ levelsGained
		)

		player:SetAttribute(
			"LastLevelUpFrom",
			oldLevel
		)
		player:SetAttribute(
			"LastLevelUpTo",
			level
		)
		player:SetAttribute(
			"LastLevelUpAt",
			workspace:GetServerTimeNow()
		)
		player:SetAttribute(
			"PlayerLevelUpSerial",
			levelUpSerial
		)
		-- A apresentacao de level up dura cerca de 2.4 s no cliente. O pequeno
		-- excedente cobre latencia sem transformar a animacao em invencibilidade.
		UpgradeChoiceProtectionService.BeginTimed(
			player,
			"LevelUpPresentation",
			3
		)
	end

	applyPower(
		player,
		levelsGained > 0
	)

	publishWorkspace()

	if levelsGained > 0 then
		safeLevelUpCallback(
			player,
			oldLevel,
			level,
			levelsGained,
			reason
		)
	end

	return true,
		PlayerLevelService.GetSnapshot(
			player
		)
end

function PlayerLevelService.GetSnapshot(
	player
)
	if not validPlayer(player) then
		return nil
	end

	local level = currentLevel(player)
	local xp = currentXP(player)

	return {
		Version =
			PlayerLevelConfig.Version,
		PersistencePolicy =
			PlayerLevelConfig.PersistencePolicy,

		Level = level,
		XP = xp,
		XPToNextLevel =
			PlayerLevelConfig
				.GetXPToNextLevel(
					level
				),
		XPProgress =
			PlayerLevelConfig
				.GetProgressRatio(
					level,
					xp
				),
		TotalXP =
			cleanXP(
				player:GetAttribute(
					"PlayerTotalXP"
				)
			),

		DamageMultiplier =
			PlayerLevelConfig
				.GetDamageMultiplier(
					level
				),
		HealthMultiplier =
			PlayerLevelConfig
				.GetHealthMultiplier(
					level
				),
	}
end

-- Server-only balancing helper. There is intentionally no RemoteEvent for it.
function PlayerLevelService.SetLevelForTesting(
	player,
	level
)
	if not started then
		return false, "ServiceNotStarted"
	end

	if not validPlayer(player) then
		return false, "InvalidPlayer"
	end

	level = cleanLevel(level)

	player:SetAttribute(
		"PlayerLevel",
		level
	)
	player:SetAttribute(
		"PlayerXP",
		0
	)
	PlayerDataService.SetLevelProgress(
		player,
		level,
		0,
		cleanXP(player:GetAttribute("PlayerTotalXP"))
	)

	applyPower(
		player,
		true
	)

	return true,
		PlayerLevelService.GetSnapshot(
			player
		)
end

function PlayerLevelService.RefreshPlayer(
	player
)
	if not validPlayer(player) then
		return false
	end

	return applyPower(
		player,
		false
	)
end

function PlayerLevelService.Stop()
	if not started then
		return false
	end

	started = false
	generation += 1

	for player in pairs(
		playerConnections
	) do
		unbindPlayer(player)
	end

	options = {}

	publishWorkspace()

	return true
end

return PlayerLevelService
