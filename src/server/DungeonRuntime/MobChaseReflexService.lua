--[[
	Infinity Islands - MobChaseReflexService V1

	Purpose:
	Remove the "slow reflex" feeling from melee chase without replacing
	SlimeController's attack/state logic.

	The existing SlimeController:
	- thinks every ~0.12s;
	- converts the player's actual position to the nearest authored island cell;
	- only treats a destination as changed after several studs;
	- can keep a path for ~0.75s.

	This service adds a high-frequency steering layer ONLY while AIState == "Chase".

	Behavior:
	- reads TargetUserId / AggroUserId every update;
	- predicts the target slightly from AssemblyLinearVelocity;
	- projects that position safely onto the current island;
	- steers the Humanoid every ~0.04s;
	- refuses to steer toward a point that is not grounded on the same island;
	- stops immediately when AIState changes (Melee, Stunned, Dash, etc.).

	Attack logic remains owned by SlimeController.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Service = {}

local UPDATE_INTERVAL = 0.04 -- 25 Hz
local TARGET_PREDICTION_SECONDS = 0.08
local MAX_PREDICTION_STUDS = 3.5

local GROUND_CAST_HEIGHT = 12
local GROUND_CAST_DEPTH = 40
local FORWARD_SAFETY_DISTANCE = 3.0

local MIN_STEER_DISTANCE = 0.45
local STOP_DISTANCE = 2.2

local started = false
local accumulated = 0
local tracked = setmetatable({}, { __mode = "k" })

local VALID_STATES = {
	Chase = true,
}

local function validPlayer(player)
	return player
		and player:IsA("Player")
		and player.Parent == Players
end

local function livingRoot(player)
	if not validPlayer(player) then
		return nil
	end

	local character = player.Character
	local humanoid =
		character
		and character:FindFirstChildOfClass("Humanoid")
	local root =
		character
		and character:FindFirstChild("HumanoidRootPart")

	if not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return nil
	end

	if player:GetAttribute("IsDowned") == true
		or player:GetAttribute("InvisibleToEnemies") == true
	then
		return nil
	end

	local protectionUntil =
		tonumber(
			player:GetAttribute(
				"DungeonEntryProtectionUntil"
			)
		) or 0

	if protectionUntil
		> workspace:GetServerTimeNow()
	then
		return nil
	end

	return root
end

local function getMobParts(model)
	if not model or not model:IsA("Model") then
		return nil, nil
	end

	local humanoid =
		model:FindFirstChildWhichIsA(
			"Humanoid",
			true
		)

	local root =
		model:FindFirstChild(
			"HumanoidRootPart",
			true
		)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA(
			"BasePart",
			true
		)

	if not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return nil, nil
	end

	return humanoid, root
end

local function findIsland(model)
	local wantedIndex =
		tonumber(
			model:GetAttribute(
				"GlobalIslandIndex"
			)
		)

	local current = model.Parent

	while current
		and current ~= workspace
	do
		if current:IsA("Model") then
			if current:GetAttribute(
				"IsSkyIsland"
			) == true
			then
				return current
			end

			local index =
				tonumber(
					current:GetAttribute(
						"GlobalIslandIndex"
					)
				)

			if wantedIndex
				and index == wantedIndex
				and current ~= model
			then
				return current
			end
		end

		current = current.Parent
	end

	return nil
end

local function targetPlayer(model)
	local userId =
		model:GetAttribute("TargetUserId")
		or model:GetAttribute("AggroUserId")
		or model:GetAttribute(
			"LastDamagedByUserId"
		)

	if typeof(userId) ~= "number" then
		return nil
	end

	return Players:GetPlayerByUserId(userId)
end

local function sameCombatIsland(
	model,
	player
)
	local mobIndex =
		tonumber(
			model:GetAttribute(
				"GlobalIslandIndex"
			)
		)

	local playerIndex =
		tonumber(
			player:GetAttribute(
				"CurrentGlobalIslandIndex"
			)
		)

	if mobIndex and playerIndex then
		return mobIndex == playerIndex
	end

	return true
end

local function groundPoint(
	model,
	island,
	targetCharacter,
	position
)
	if not island
		or not island.Parent
	then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local excludes = {
		model,
	}

	if targetCharacter then
		table.insert(
			excludes,
			targetCharacter
		)
	end

	params.FilterDescendantsInstances =
		excludes

	local origin =
		position
		+ Vector3.new(
			0,
			GROUND_CAST_HEIGHT,
			0
		)

	local result =
		workspace:Raycast(
			origin,
			Vector3.new(
				0,
				-GROUND_CAST_DEPTH,
				0
			),
			params
		)

	if not result
		or not result.Instance
		or not result.Instance:IsA(
			"BasePart"
		)
	then
		return nil
	end

	if not result.Instance:IsDescendantOf(
		island
	)
	then
		return nil
	end

	if result.Normal.Y < 0.5 then
		return nil
	end

	return result.Position
end

local function safeForwardStep(
	model,
	island,
	targetCharacter,
	root,
	direction
)
	if direction.Magnitude < 0.01 then
		return true
	end

	local testPosition =
		root.Position
		+ direction.Unit
			* FORWARD_SAFETY_DISTANCE

	return groundPoint(
		model,
		island,
		targetCharacter,
		testPosition
	) ~= nil
end

local function predictedTargetPosition(
	targetRoot
)
	local velocity =
		targetRoot.AssemblyLinearVelocity

	local horizontalVelocity =
		Vector3.new(
			velocity.X,
			0,
			velocity.Z
		)

	local prediction =
		horizontalVelocity
			* TARGET_PREDICTION_SECONDS

	if prediction.Magnitude
		> MAX_PREDICTION_STUDS
	then
		prediction =
			prediction.Unit
			* MAX_PREDICTION_STUDS
	end

	return targetRoot.Position
		+ prediction
end

local function clearOverride(model)
	if not model or not model.Parent then
		return
	end

	if model:GetAttribute(
		"ResponsiveChaseActive"
	) == true
	then
		model:SetAttribute(
			"ResponsiveChaseActive",
			false
		)
	end
end

local function steer(model)
	if not model
		or not model.Parent
	then
		return
	end

	if model:GetAttribute(
		"AIController"
	) ~= "Slime"
		or model:GetAttribute(
			"TutorialPassive"
		) == true
	then
		clearOverride(model)
		return
	end

	local aiState =
		tostring(
			model:GetAttribute(
				"AIState"
			) or ""
		)

	if not VALID_STATES[aiState]
		or model:GetAttribute(
			"CombatStunned"
		) == true
		or model:GetAttribute(
			"SimulationActive"
		) == false
	then
		clearOverride(model)
		return
	end

	local humanoid, root =
		getMobParts(model)

	if not humanoid or not root then
		clearOverride(model)
		return
	end

	local player =
		targetPlayer(model)

	if not player
		or not sameCombatIsland(
			model,
			player
		)
	then
		clearOverride(model)
		return
	end

	local targetRoot =
		livingRoot(player)

	if not targetRoot then
		clearOverride(model)
		return
	end

	local island =
		findIsland(model)

	if not island then
		clearOverride(model)
		return
	end

	local predicted =
		predictedTargetPosition(
			targetRoot
		)

	local safeDestination =
		groundPoint(
			model,
			island,
			player.Character,
			predicted
		)

	if not safeDestination then
		-- Let SlimeController's existing pathfinding own this situation.
		clearOverride(model)
		return
	end

	local flatOffset =
		Vector3.new(
			safeDestination.X
				- root.Position.X,
			0,
			safeDestination.Z
				- root.Position.Z
		)

	local distance =
		flatOffset.Magnitude

	if distance <= STOP_DISTANCE then
		clearOverride(model)
		return
	end

	if distance < MIN_STEER_DISTANCE then
		return
	end

	local direction =
		flatOffset.Unit

	if not safeForwardStep(
		model,
		island,
		player.Character,
		root,
		direction
	)
	then
		-- Edge/gap ahead: do not override the safe pathfinder.
		clearOverride(model)
		return
	end

	model:SetAttribute(
		"ResponsiveChaseActive",
		true
	)
	model:SetAttribute(
		"ResponsiveChaseTargetUserId",
		player.UserId
	)
	model:SetAttribute(
		"ResponsiveChaseLastUpdateAt",
		workspace:GetServerTimeNow()
	)
	model:SetAttribute(
		"ResponsiveChasePredictionSeconds",
		TARGET_PREDICTION_SECONDS
	)

	humanoid.AutoRotate = true

	-- Humanoid:Move gives immediate steering every update and therefore does
	-- not wait for the old cached waypoint to become stale.
	humanoid:Move(
		direction,
		false
	)

	-- MoveTo keeps Roblox's humanoid locomotion pointed at the newest grounded
	-- target as well. The next 25 Hz pass continuously refreshes it.
	humanoid:MoveTo(
		safeDestination
	)
end

local function register(model)
	if not model
		or not model:IsA("Model")
	then
		return
	end

	tracked[model] = true
end

local function unregister(model)
	tracked[model] = nil
	clearOverride(model)
end

function Service.Start()
	if started then
		return false, "AlreadyStarted"
	end

	started = true

	CollectionService
		:GetInstanceAddedSignal(
			"CombatTarget"
		)
		:Connect(register)

	CollectionService
		:GetInstanceRemovedSignal(
			"CombatTarget"
		)
		:Connect(unregister)

	for _, model in ipairs(
		CollectionService:GetTagged(
			"CombatTarget"
		)
	) do
		register(model)
	end

	RunService.Heartbeat:Connect(
		function(dt)
			if not started then
				return
			end

			accumulated += dt

			if accumulated
				< UPDATE_INTERVAL
			then
				return
			end

			accumulated = 0

			for model in pairs(tracked) do
				if model.Parent then
					steer(model)
				else
					tracked[model] = nil
				end
			end
		end
	)

	workspace:SetAttribute(
		"DungeonMobChaseReflexReady",
		true
	)
	workspace:SetAttribute(
		"DungeonMobChaseReflexVersion",
		"MobChaseReflexV1"
	)
	workspace:SetAttribute(
		"DungeonMobChaseUpdateInterval",
		UPDATE_INTERVAL
	)
	workspace:SetAttribute(
		"DungeonMobChasePredictionSeconds",
		TARGET_PREDICTION_SECONDS
	)

	print(
		"[MobChaseReflexService] ativo: "
			.. "Chase steering a 25 Hz."
	)

	return true
end

return Service
