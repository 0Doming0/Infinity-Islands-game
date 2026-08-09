--[[
	Infinity Islands - Task 24
	EarlyCombatTTKService V1

	Two responsibilities that belong to the same tuning experiment:

	1. Starter sword tuning
	   ClassicSword BaseDamage has a minimum floor of 24.

	2. TTK telemetry
	   For IslandCombatManaged mobs, measure:
	   first accepted player damage -> mob death.

	This service does NOT:
	- change enemy health;
	- change PlayerLevel;
	- grant XP;
	- change attack speed;
	- auto attack;
	- create HUD.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.EarlyCombatTTKConfig
)

local WeaponReadinessConfig = require(
	ReplicatedStorage.Shared.Configs.WeaponReadinessConfig
)

local Service = {}

local started = false

local toolConnections =
	setmetatable({}, { __mode = "k" })

local playerConnections =
	setmetatable({}, { __mode = "k" })

local weaponStates =
	setmetatable({}, { __mode = "k" })

local mobStates =
	setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function telemetryBaseline(player)
	return tonumber(
		player:GetAttribute(
			"DungeonInstantControlReadyAt"
		)
			or player:GetAttribute(
				"DungeonDirectEntryStartedAt"
			)
	)
end

local function insideTelemetryWindow(player)
	local baseline =
		telemetryBaseline(player)

	if not baseline then
		return false
	end

	return now() - baseline
		<= Config.TelemetryWindowSeconds
end

local function isStarterSword(tool)
	if not tool
		or not tool:IsA("Tool")
	then
		return false
	end

	if Config.StarterSwordNames[
		tool.Name
	] == true
		or WeaponReadinessConfig
			.StarterSwordNames[
				tool.Name
			] == true
	then
		return true
	end

	for _, attributeName in ipairs({
		"ItemId",
		"WeaponId",
		"SwordId",
	}) do
		local value =
			tool:GetAttribute(
				attributeName
			)

		if value ~= nil
			and (
				Config.StarterSwordIds[
					tostring(value)
				] == true
					or WeaponReadinessConfig
						.StarterSwordIds[
							tostring(value)
						] == true
			)
		then
			return true
		end
	end

	return false
end

local function tuneStarterSword(
	player,
	tool
)
	if not isStarterSword(tool) then
		return false
	end

	local current =
		tonumber(
			tool:GetAttribute(
				"BaseDamage"
			)
		)

	local desired =
		math.max(
			current or 0,
			Config.StarterSwordBaseDamage
		)

	if current == nil
		or current < desired
	then
		tool:SetAttribute(
			"BaseDamage",
			desired
		)
	end

	tool:SetAttribute(
		"EarlyCombatTTKVersion",
		Config.Version
	)

	tool:SetAttribute(
		"EarlyCombatTTKTuned",
		true
	)

	tool:SetAttribute(
		"EarlyCombatTTKMinimumBaseDamage",
		Config.StarterSwordBaseDamage
	)

	if player
		and player.Parent == Players
	then
		player:SetAttribute(
			"StarterSwordBaseDamage",
			desired
		)

		player:SetAttribute(
			"StarterSwordTTKTuned",
			true
		)

		player:SetAttribute(
			"StarterSwordTTKVersion",
			Config.Version
		)
	end

	return true
end

local function equippedTool(character)
	if not character then
		return nil
	end

	for _, child in ipairs(
		character:GetChildren()
	) do
		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

local function publishWeaponReady(
	player,
	state,
	tool,
	reason
)
	if not player
		or player.Parent ~= Players
		or not state
	then
		return
	end

	local timestamp = now()

	if state.WeaponReadyAt == nil then
		state.WeaponReadyAt = timestamp

		player:SetAttribute(
			"DungeonWeaponReadyAt",
			timestamp
		)

		player:SetAttribute(
			"DungeonWeaponReadyFromCharacterSeconds",
			math.max(
				0,
				timestamp
					- (
						tonumber(
							state.CharacterSpawnedAt
						) or timestamp
					)
			)
		)

		local entryAt =
			tonumber(
				player:GetAttribute(
					"DungeonDirectEntryStartedAt"
				)
			)

		if entryAt then
			player:SetAttribute(
				"DungeonWeaponReadyFromEntrySeconds",
				math.max(
					0,
					timestamp - entryAt
				)
			)
		end
	end

	player:SetAttribute(
		"DungeonWeaponReady",
		true
	)

	player:SetAttribute(
		"DungeonWeaponReadyTool",
		tool and tool.Name or "ClassicSword"
	)

	player:SetAttribute(
		"DungeonWeaponReadyReason",
		tostring(reason or "Ready")
	)

	player:SetAttribute(
		"DungeonWeaponReadinessVersion",
		WeaponReadinessConfig.Version
	)
end

local function tryAutoEquipStarter(
	player,
	tool,
	reason
)
	if WeaponReadinessConfig.AutoEquipEnabled
		~= true
		or not isStarterSword(tool)
	then
		return false,
			"NotStarterSword"
	end

	local state =
		weaponStates[player]

	if not state
		or state.AutoEquipConsumed == true
	then
		return false,
			"AutoEquipAlreadyConsumed"
	end

	local character =
		player.Character

	if not character
		or character ~= state.Character
		or not character.Parent
	then
		return false,
			"CharacterMismatch"
	end

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0
	then
		return false,
			"HumanoidUnavailable"
	end

	if now()
		> (
			state.CharacterSpawnedAt
				+ WeaponReadinessConfig
					.AutoEquipWindowSeconds
		)
	then
		state.AutoEquipConsumed = true

		player:SetAttribute(
			"DungeonWeaponAutoEquipResult",
			"WindowExpired"
		)

		return false,
			"WindowExpired"
	end

	local currentlyEquipped =
		equippedTool(character)

	if currentlyEquipped then
		if currentlyEquipped == tool
			or isStarterSword(
				currentlyEquipped
			)
		then
			state.AutoEquipConsumed = true
			state.AutoEquippedTool =
				currentlyEquipped

			publishWeaponReady(
				player,
				state,
				currentlyEquipped,
				"AlreadyEquipped"
			)

			player:SetAttribute(
				"DungeonWeaponAutoEquipResult",
				"AlreadyEquipped"
			)

			return true,
				"AlreadyEquipped"
		end

		-- Player/another system intentionally equipped something else.
		state.AutoEquipConsumed = true

		player:SetAttribute(
			"DungeonWeaponAutoEquipResult",
			"OtherToolAlreadyEquipped"
		)

		return false,
			"OtherToolAlreadyEquipped"
	end

	if tool.Parent ~= player.Backpack then
		return false,
			"StarterNotInBackpack"
	end

	state.AutoEquipConsumed = true
	state.AutoEquippedTool = tool

	humanoid:EquipTool(tool)

	player:SetAttribute(
		"DungeonWeaponAutoEquipCount",
		(
			tonumber(
				player:GetAttribute(
					"DungeonWeaponAutoEquipCount"
				)
			) or 0
		) + 1
	)

	player:SetAttribute(
		"DungeonWeaponAutoEquipResult",
		"Equipped"
	)

	player:SetAttribute(
		"DungeonWeaponAutoEquipReason",
		tostring(reason or "StarterAvailable")
	)

	publishWeaponReady(
		player,
		state,
		tool,
		"AutoEquipped"
	)

	return true,
		"Equipped"
end

local function refreshWeaponReadyState(player)
	local state =
		weaponStates[player]

	if not state
		or not state.Character
	then
		return
	end

	local current =
		equippedTool(
			state.Character
		)

	if current
		and isStarterSword(current)
	then
		publishWeaponReady(
			player,
			state,
			current,
			"EquippedObserved"
		)
	end
end

local function bindToolContainer(
	player,
	container
)
	if not container
		or toolConnections[container]
	then
		return
	end

	local connections = {}

	table.insert(
		connections,
		container.ChildAdded:Connect(
			function(child)
				if child:IsA("Tool") then
					task.defer(function()
						tuneStarterSword(
							player,
							child
						)

						if container
							== player.Backpack
						then
							tryAutoEquipStarter(
								player,
								child,
								"BackpackChildAdded"
							)
						else
							refreshWeaponReadyState(
								player
							)
						end
					end)
				end
			end
		)
	)

	toolConnections[container] =
		connections

	for _, child in ipairs(
		container:GetChildren()
	) do
		if child:IsA("Tool") then
			tuneStarterSword(
				player,
				child
			)

			if container == player.Backpack then
				tryAutoEquipStarter(
					player,
					child,
					"InitialContainerScan"
				)
			end
		end
	end
end

local function bindPlayer(player)
	if playerConnections[player] then
		return
	end

	local connections = {}

	player:SetAttribute(
		"StarterSwordTTKVersion",
		Config.Version
	)

	player:SetAttribute(
		"EarlyCombatTTKTargetSeconds",
		Config.EarlyKillTargetSeconds
	)

	local backpack =
		player:FindFirstChildOfClass(
			"Backpack"
		)
			or player:WaitForChild(
				"Backpack",
				10
			)

	if backpack then
		bindToolContainer(
			player,
			backpack
		)
	end

	table.insert(
		connections,
		player.CharacterAdded:Connect(
			function(character)
				weaponStates[player] = {
					Character = character,
					CharacterSpawnedAt = now(),
					AutoEquipConsumed = false,
					AutoEquippedTool = nil,
					WeaponReadyAt = nil,
				}

				player:SetAttribute(
					"DungeonWeaponReady",
					false
				)

				player:SetAttribute(
					"DungeonWeaponAutoEquipResult",
					"WaitingForStarter"
				)

				bindToolContainer(
					player,
					character
				)

				for _, child in ipairs(
					character:GetChildren()
				) do
					if child:IsA("Tool") then
						tuneStarterSword(
							player,
							child
						)
					end
				end

				local backpack =
					player:FindFirstChildOfClass(
						"Backpack"
					)

				if backpack then
					bindToolContainer(
						player,
						backpack
					)

					for _, child in ipairs(
						backpack:GetChildren()
					) do
						if child:IsA("Tool") then
							tuneStarterSword(
								player,
								child
							)

							local equipped =
								tryAutoEquipStarter(
									player,
									child,
									"CharacterAddedScan"
								)

							if equipped then
								break
							end
						end
					end
				end

				task.delay(
					WeaponReadinessConfig
						.ReadinessCheckTimeoutSeconds,
					function()
						local state =
							weaponStates[player]

						if player.Parent ~= Players
							or not state
							or state.Character
								~= character
							or player:GetAttribute(
								"DungeonWeaponReady"
							) == true
						then
							return
						end

						player:SetAttribute(
							"DungeonWeaponReady",
							false
						)

						player:SetAttribute(
							"DungeonWeaponAutoEquipResult",
							"StarterSwordNotReady"
						)

						player:SetAttribute(
							"DungeonWeaponReadinessTimedOutAt",
							now()
						)
					end
				)
			end
		)
	)

	if player.Character then
		weaponStates[player] = {
			Character = player.Character,
			CharacterSpawnedAt = now(),
			AutoEquipConsumed = false,
			AutoEquippedTool = nil,
			WeaponReadyAt = nil,
		}

		bindToolContainer(
			player,
			player.Character
		)

		if backpack then
			for _, child in ipairs(
				backpack:GetChildren()
			) do
				if child:IsA("Tool") then
					local equipped =
						tryAutoEquipStarter(
							player,
							child,
							"ExistingCharacterScan"
						)

					if equipped then
						break
					end
				end
			end
		end
	end

	player:SetAttribute(
		"DungeonWeaponReadinessVersion",
		WeaponReadinessConfig.Version
	)

	player:SetAttribute(
		"DungeonWeaponReadinessPolicy",
		WeaponReadinessConfig.Policy
	)

	playerConnections[player] =
		connections
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

	weaponStates[player] = nil
end

local function livingPlayerFromUserId(userId)
	local clean =
		math.floor(
			tonumber(userId) or 0
		)

	if clean <= 0 then
		return nil
	end

	local player =
		Players:GetPlayerByUserId(
			clean
		)

	return player
		and player.Parent == Players
		and player
		or nil
end

local function publishKillTTK(
	player,
	model,
	state,
	ttk
)
	if not player
		or not model
		or ttk == nil
	then
		return
	end

	local hitCount =
		math.max(
			1,
			math.floor(
				tonumber(
					state.PlayerDamageHitCount
				) or 1
			)
		)

	player:SetAttribute(
		"LastMobEngagementTTKSeconds",
		ttk
	)

	player:SetAttribute(
		"LastMobEngagementHitCount",
		hitCount
	)

	player:SetAttribute(
		"LastMobEngagementVariant",
		tostring(
			model:GetAttribute(
				"SlimeVariant"
			)
				or model:GetAttribute(
					"MonsterId"
				)
				or model.Name
		)
	)

	player:SetAttribute(
		"LastMobEngagementMobLevel",
		tonumber(
			model:GetAttribute(
				"MobLevel"
			)
		) or 1
	)

	player:SetAttribute(
		"LastMobEngagementIsland",
		tonumber(
			model:GetAttribute(
				"GlobalIslandIndex"
			)
		)
	)

	player:SetAttribute(
		"LastMobEngagementTTKOnTarget",
		ttk
			<= Config
				.EarlyKillTargetSeconds
	)

	player:SetAttribute(
		"LastMobEngagementTTKAt",
		now()
	)

	if not insideTelemetryWindow(player) then
		return
	end

	local count =
		(
			tonumber(
				player:GetAttribute(
					"EarlyCombatTTKKillCount90s"
				)
			) or 0
		) + 1

	local total =
		(
			tonumber(
				player:GetAttribute(
					"EarlyCombatTTKTotalSeconds90s"
				)
			) or 0
		) + ttk

	local onTargetCount =
		tonumber(
			player:GetAttribute(
				"EarlyCombatTTKOnTargetKills90s"
			)
		) or 0

	if ttk
		<= Config.EarlyKillTargetSeconds
	then
		onTargetCount += 1
	end

	player:SetAttribute(
		"EarlyCombatTTKKillCount90s",
		count
	)

	player:SetAttribute(
		"EarlyCombatTTKTotalSeconds90s",
		total
	)

	player:SetAttribute(
		"EarlyCombatTTKAverageSeconds90s",
		total / count
	)

	player:SetAttribute(
		"EarlyCombatTTKOnTargetKills90s",
		onTargetCount
	)

	player:SetAttribute(
		"EarlyCombatTTKOnTargetRatio90s",
		onTargetCount / count
	)

	local maximum =
		math.max(
			tonumber(
				player:GetAttribute(
					"EarlyCombatTTKMaxSeconds90s"
				)
			) or 0,
			ttk
		)

	player:SetAttribute(
		"EarlyCombatTTKMaxSeconds90s",
		maximum
	)

	if player:GetAttribute(
		"EarlyCombatFirstKillTTKSeconds"
	) == nil
	then
		player:SetAttribute(
			"EarlyCombatFirstKillTTKSeconds",
			ttk
		)

		player:SetAttribute(
			"EarlyCombatFirstKillHitCount",
			hitCount
		)

		player:SetAttribute(
			"EarlyCombatFirstKillTTKOnTarget",
			ttk
				<= Config
					.EarlyKillTargetSeconds
		)
	end
end

local function bindManagedMob(model)
	if not model
		or not model:IsA("Model")
		or mobStates[model]
	then
		return
	end

	if model:GetAttribute(
		"IslandCombatManaged"
	) ~= true
	then
		return
	end

	local humanoid =
		model:FindFirstChildWhichIsA(
			"Humanoid",
			true
		)

	if not humanoid then
		return
	end

	local state = {
		LastHealth = humanoid.Health,
		FirstPlayerDamageAt = nil,
		FirstPlayerUserId = nil,
		PlayerDamageHitCount = 0,
	}

	mobStates[model] = state

	model:SetAttribute(
		"EarlyCombatTTKVersion",
		Config.Version
	)

	state.HealthConnection =
		humanoid.HealthChanged:Connect(
			function(newHealth)
				if mobStates[model]
					~= state
				then
					return
				end

				local previous =
					tonumber(
						state.LastHealth
					) or newHealth

				local lost =
					math.max(
						0,
						previous - newHealth
					)

				state.LastHealth =
					newHealth

				if lost <= 0 then
					return
				end

				local userId =
					math.floor(
						tonumber(
							model:GetAttribute(
								"LastDamagedByUserId"
							)
						) or 0
					)

				if userId <= 0 then
					return
				end

				state.PlayerDamageHitCount += 1

				if not state.FirstPlayerDamageAt then
					state.FirstPlayerDamageAt =
						now()

					state.FirstPlayerUserId =
						userId

					model:SetAttribute(
						"FirstPlayerDamageAt",
						state.FirstPlayerDamageAt
					)

					model:SetAttribute(
						"FirstPlayerDamageUserId",
						userId
					)
				end

				model:SetAttribute(
					"PlayerDamageHitCount",
					state.PlayerDamageHitCount
				)
			end
		)

	state.DiedConnection =
		humanoid.Died:Connect(function()
			if mobStates[model]
				~= state
			then
				return
			end

			local firstAt =
				tonumber(
					state.FirstPlayerDamageAt
				)

			if firstAt then
				local userId =
					math.floor(
						tonumber(
							model:GetAttribute(
								"LastDamagedByUserId"
							)
						)
							or state
								.FirstPlayerUserId
							or 0
					)

				local player =
					livingPlayerFromUserId(
						userId
					)

				if player then
					publishKillTTK(
						player,
						model,
						state,
						math.max(
							0,
							now() - firstAt
						)
					)
				end
			end
		end)

	state.AncestryConnection =
		model.AncestryChanged:Connect(
			function(_, parent)
				if parent ~= nil then
					return
				end

				if state.HealthConnection then
					state.HealthConnection
						:Disconnect()
				end

				if state.DiedConnection then
					state.DiedConnection
						:Disconnect()
				end

				if state.AncestryConnection then
					state.AncestryConnection
						:Disconnect()
				end

				mobStates[model] = nil
			end
		)
end

function Service.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonEarlyCombatTTKReady",
		true
	)

	workspace:SetAttribute(
		"DungeonEarlyCombatTTKVersion",
		Config.Version
	)

	workspace:SetAttribute(
		"DungeonEarlyCombatTTKPolicy",
		Config.Policy
	)

	workspace:SetAttribute(
		"DungeonWeaponReadinessVersion",
		WeaponReadinessConfig.Version
	)

	workspace:SetAttribute(
		"DungeonWeaponReadinessPolicy",
		WeaponReadinessConfig.Policy
	)

	workspace:SetAttribute(
		"DungeonStarterSwordAutoEquipEnabled",
		WeaponReadinessConfig.AutoEquipEnabled
	)

	workspace:SetAttribute(
		"DungeonStarterSwordAutoEquipWindowSeconds",
		WeaponReadinessConfig.AutoEquipWindowSeconds
	)

	workspace:SetAttribute(
		"DungeonStarterSwordBaseDamage",
		Config.StarterSwordBaseDamage
	)

	workspace:SetAttribute(
		"DungeonEarlyCombatTTKTargetSeconds",
		Config.EarlyKillTargetSeconds
	)

	workspace:SetAttribute(
		"DungeonExpectedGreenL1Hits",
		2
	)

	workspace:SetAttribute(
		"DungeonExpectedFirstGreenL2HitsAtPlayerL2",
		3
	)

	workspace:SetAttribute(
		"DungeonExpectedGreenL2HitsAtPlayerL3",
		2
	)

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

	CollectionService
		:GetInstanceAddedSignal(
			"CombatTarget"
		)
		:Connect(function(instance)
			task.defer(
				bindManagedMob,
				instance
			)
		end)

	for _, model in ipairs(
		CollectionService:GetTagged(
			"CombatTarget"
		)
	) do
		task.defer(
			bindManagedMob,
			model
		)
	end

	return true
end

return Service
