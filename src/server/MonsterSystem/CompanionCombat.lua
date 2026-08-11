--[[
	Infinity Islands - CompanionCombat V2
	Island Combat Guard

	Core rule:
	- companion may attack ONLY CombatTargets on the same PHYSICAL island
	  currently occupied by its owner;
	- if the owner is on a connector / bridge / path between islands,
	  the companion becomes peaceful;
	- entering another island automatically re-enables combat for that island;
	- ongoing melee/ranged/mortar/ability attacks are cancelled when the owner
	  leaves the island or when the target is not on the same island.

	This module preserves the public CompanionCombat API:
		GetStats(...)
		TryAttack(...)
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CompanionCatalog =
	require(ReplicatedStorage:WaitForChild("CompanionCatalog"))

local SlimeVariants =
	require(
		script.Parent.Parent.BlockParkour
			:WaitForChild("SlimeVariants")
	)

local DamageService =
	require(
		script.Parent.Parent.MVPSystems
			:WaitForChild("CombatDamageService")
	)

local MonsterAnimationLoader =
	require(script.Parent.MonsterAnimationLoader)

local MonsterConfig =
	require(script.Parent.MonsterConfig)

local CompanionCombat = {}

---------------------------------------------------------------------
-- Island guard configuration
---------------------------------------------------------------------

local ISLAND_PROBE_HEIGHT = 10
local ISLAND_PROBE_DEPTH = 26
local ISLAND_GUARD_INTERVAL = 0.05

local CONNECTOR_ATTRIBUTE_NAMES = {
	"IsConnector",
	"IsBridge",
	"IsPath",
	"IsWalkway",
	"CombatConnector",
	"DungeonConnector",
}

local CONNECTOR_NAME_FRAGMENTS = {
	"connector",
	"bridge",
	"walkway",
	"skywalk",
	"routepath",
	"routeconnector",
	"islandconnector",
}

local function horizontalDistance(left, right)
	local offset = left - right
	return Vector2.new(offset.X, offset.Z).Magnitude
end

local function cleanIndex(value)
	local number = tonumber(value)
	return number and math.floor(number) or nil
end

local function looksLikeConnector(instance, island)
	local current = instance

	while current
		and current ~= workspace
		and current ~= island
	do
		for _, attributeName in ipairs(
			CONNECTOR_ATTRIBUTE_NAMES
		) do
			if current:GetAttribute(attributeName) == true then
				return true
			end
		end

		local lowerName =
			string.lower(current.Name)

		for _, fragment in ipairs(
			CONNECTOR_NAME_FRAGMENTS
		) do
			if string.find(
				lowerName,
				fragment,
				1,
				true
			) then
				return true
			end
		end

		current = current.Parent
	end

	return false
end

local function islandAncestor(instance)
	local current = instance

	while current and current ~= workspace do
		if current:IsA("Model") then
			local index =
				cleanIndex(
					current:GetAttribute(
						"GlobalIslandIndex"
					)
				)

			if index
				and (
					current:GetAttribute(
						"CombatIsland"
					) == true
					or current:GetAttribute(
						"IsSkyIsland"
					) == true
					or current:GetAttribute(
						"IslandLevel"
					) ~= nil
				)
			then
				return current, index
			end
		end

		current = current.Parent
	end

	return nil, nil
end

local function physicalIslandForRoot(
	root,
	character,
	extraExclude
)
	if not root
		or not root.Parent
	then
		return nil, nil
	end

	local params = RaycastParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local excludes = {}

	if character then
		table.insert(excludes, character)
	end

	if extraExclude then
		table.insert(excludes, extraExclude)
	end

	params.FilterDescendantsInstances =
		excludes

	local result =
		workspace:Raycast(
			root.Position
				+ Vector3.new(
					0,
					ISLAND_PROBE_HEIGHT,
					0
				),
			Vector3.new(
				0,
				-(
					ISLAND_PROBE_HEIGHT
					+ ISLAND_PROBE_DEPTH
				),
				0
			),
			params
		)

	if not result
		or not result.Instance
	then
		return nil, nil
	end

	local island, index =
		islandAncestor(
			result.Instance
		)

	if not island then
		return nil, nil
	end

	-- A connector can physically be parented under an island model.
	-- In that case it must still count as "between islands", not "on island".
	if looksLikeConnector(
		result.Instance,
		island
	) then
		return nil, nil
	end

	return island, index
end

local function ownerPhysicalIsland(state)
	local owner = state.Owner

	if not owner
		or owner.Parent == nil
	then
		return nil, nil
	end

	local character = owner.Character
	local humanoid =
		character
		and character:FindFirstChildOfClass(
			"Humanoid"
		)
	local root =
		character
		and character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return nil, nil
	end

	return physicalIslandForRoot(
		root,
		character,
		state.Model
	)
end

local function targetIslandIndex(targetModel, targetRoot)
	if not targetModel then
		return nil
	end

	local attributeIndex =
		cleanIndex(
			targetModel:GetAttribute(
				"GlobalIslandIndex"
			)
		)

	if attributeIndex then
		return attributeIndex
	end

	if targetRoot then
		local _, index =
			physicalIslandForRoot(
				targetRoot,
				targetModel,
				nil
			)

		return index
	end

	return nil
end

local function targetMatchesOwnerIsland(
	state,
	targetModel,
	targetRoot
)
	local _, ownerIndex =
		ownerPhysicalIsland(state)

	if not ownerIndex then
		return false
	end

	local targetIndex =
		targetIslandIndex(
			targetModel,
			targetRoot
		)

	return targetIndex ~= nil
		and targetIndex == ownerIndex
end

local function setPassivePresentation(
	state,
	isPassive,
	islandIndex,
	reason
)
	if not state.Model
		or not state.Model.Parent
	then
		return
	end

	state.Model:SetAttribute(
		"CompanionIslandCombatPolicy",
		"OwnerPhysicalIslandOnlyV1"
	)

	state.Model:SetAttribute(
		"CompanionPeacefulBetweenIslands",
		isPassive == true
	)

	state.Model:SetAttribute(
		"CompanionOwnerPhysicalIslandIndex",
		islandIndex
	)

	state.Model:SetAttribute(
		"CompanionIslandCombatReason",
		tostring(reason or "")
	)
end

local function cancelCombat(
	state,
	reason,
	islandIndex
)
	if state.Busy then
		state.AttackSerial += 1
	end

	state.Busy = false
	state.Target = nil

	if state.Humanoid
		and state.Humanoid.Parent
		and state.Root
		and state.Root.Parent
	then
		state.Humanoid:MoveTo(
			state.Root.Position
		)
	end

	if state.Model
		and state.Model.Parent
	then
		state.Model:SetAttribute(
			"MonsterState",
			"Idle"
		)

		if state.IsSlime then
			state.Model:SetAttribute(
				"AIState",
				"Idle"
			)

			state.Model:SetAttribute(
				"IsMoving",
				false
			)
		elseif state.Humanoid then
			MonsterAnimationLoader.Play(
				state.Model,
				state.Humanoid,
				"Idle"
			)
		end
	end

	setPassivePresentation(
		state,
		true,
		islandIndex,
		reason
	)
end

local function restoreDetectionRange(state)
	if not state.CombatStats then
		return
	end

	local original =
		state._IslandGuardDetectionRange

	if typeof(original) == "number" then
		state.CombatStats.DetectionRange =
			original
	end
end

local function suppressDetectionRange(state)
	if not state.CombatStats then
		return
	end

	if typeof(
		state._IslandGuardDetectionRange
	) ~= "number"
	then
		state._IslandGuardDetectionRange =
			state.CombatStats.DetectionRange
	end

	state.CombatStats.DetectionRange = 0
end

local function guardedTargetValid(
	state,
	model
)
	if not model
		or not model.Parent
	then
		return false
	end

	local root =
		MonsterConfig.GetRoot(model)

	if not root then
		return false
	end

	if not targetMatchesOwnerIsland(
		state,
		model,
		root
	) then
		return false
	end

	local original =
		state._IslandGuardOriginalValidator

	if type(original) == "function" then
		return original(model)
	end

	return true
end

local function ensureIslandGuard(state)
	if state._IslandGuardInstalled then
		return
	end

	state._IslandGuardInstalled = true
	state._IslandGuardOriginalValidator =
		state.IsTargetValid

	if state.CombatStats then
		state._IslandGuardDetectionRange =
			state.CombatStats.DetectionRange
	end

	state.IsTargetValid =
		function(model)
			return guardedTargetValid(
				state,
				model
			)
		end

	task.spawn(function()
		local accumulated = 0

		while state.Model
			and state.Model.Parent
			and state.Root
			and state.Root.Parent
			and state.Humanoid
			and state.Humanoid.Health > 0
		do
			local dt =
				RunService.Heartbeat:Wait()

			accumulated += dt

			if accumulated
				< ISLAND_GUARD_INTERVAL
			then
				continue
			end

			accumulated = 0

			local _, ownerIndex =
				ownerPhysicalIsland(state)

			if not ownerIndex then
				suppressDetectionRange(state)

				cancelCombat(
					state,
					"OwnerBetweenIslands",
					nil
				)

				continue
			end

			restoreDetectionRange(state)

			local target =
				state.Target

			if target
				and target.Model
			then
				local root =
					target.Root
					or MonsterConfig.GetRoot(
						target.Model
					)

				if not targetMatchesOwnerIsland(
					state,
					target.Model,
					root
				) then
					cancelCombat(
						state,
						"TargetOnDifferentIsland",
						ownerIndex
					)

					continue
				end
			end

			setPassivePresentation(
				state,
				false,
				ownerIndex,
				"OwnerOnCombatIsland"
			)
		end
	end)
end

---------------------------------------------------------------------
-- Existing combat-stat behavior
---------------------------------------------------------------------

local function slimeDefinition(
	model,
	monsterId
)
	local variant =
		model:GetAttribute(
			"SlimeVariant"
		)

	if type(variant) == "string" then
		local definition =
			SlimeVariants.GetDefinition(
				variant
			)

		if definition then
			return definition
		end
	end

	variant =
		string.match(
			monsterId or "",
			"^(%a+)Slime$"
		)

	return variant
		and SlimeVariants.GetDefinition(
			variant
		)
		or nil
end

local function hasConfiguredAbility(
	model,
	abilityName
)
	if model:GetAttribute(
		"Has" .. abilityName
	) == true
	then
		return true
	end

	local encoded =
		model:GetAttribute(
			"Abilities"
		)

	if type(encoded) == "string" then
		for name in string.gmatch(
			encoded,
			"[^,%s]+"
		) do
			if name == abilityName then
				return true
			end
		end
	end

	local folder =
		model:FindFirstChild(
			"Abilities"
		)

	local value =
		folder
		and folder:FindFirstChild(
			abilityName
		)

	return value ~= nil
		and (
			not value:IsA("BoolValue")
			or value.Value
		)
end

function CompanionCombat.GetStats(
	model,
	monsterId,
	level,
	upgrades
)
	local config =
		MonsterConfig.Read(model)

	local definition =
		slimeDefinition(
			model,
			monsterId
		)

	local behavior =
		definition
			and definition.Behavior
			or config.AttackType

	local attackType =
		config.AttackType

	if behavior == "NeutralMelee"
		or behavior == "GoldenEscape"
		or behavior == "LightningDash"
	then
		attackType = "Melee"

	elseif behavior == "NeutralRanged"
		or behavior == "IceRanged"
	then
		attackType = "Ranged"

	elseif behavior == "HostileMortar"
		or behavior == "FireMortar"
	then
		attackType = "Mortar"
	end

	local baseDamage =
		tonumber(
			model:GetAttribute(
				"CompanionDamage"
			)
		)
		or (
			definition
			and definition.AttackDamage
		)
		or config.AttackDamage

	local baseRange =
		definition
			and definition.AttackRange
			or config.AttackRange

	local baseCooldown =
		definition
			and definition.AttackCooldown
			or config.AttackCooldown

	local humanoid =
		MonsterConfig.GetHumanoid(model)

	local baseWalkSpeed =
		tonumber(
			model:GetAttribute(
				"WalkSpeed"
			)
		)
		or (
			humanoid
			and humanoid.WalkSpeed
		)
		or config.WalkSpeed

	local movementMultiplier =
		definition
			and (
				definition
					.CombatSpeedMultiplier
				or definition
					.PassiveSpeedMultiplier
			)
			or 1

	local damagePoints =
		math.max(
			0,
			tonumber(
				upgrades
				and upgrades.Damage
			) or 0
		)

	local attackSpeedPoints =
		math.max(
			0,
			tonumber(
				upgrades
				and upgrades.AttackSpeed
			) or 0
		)

	local moveSpeedPoints =
		math.max(
			0,
			tonumber(
				upgrades
				and upgrades.MoveSpeed
			) or 0
		)

	local rangePoints =
		math.max(
			0,
			tonumber(
				upgrades
				and upgrades.Range
			) or 0
		)

	local damageMultiplier =
		1
		+ math.max(
			0,
			level - 1
		) * CompanionCatalog.LevelDamageBonus
		+ damagePoints
			* CompanionCatalog
				.Upgrades
				.Damage
				.BonusPerPoint

	local cooldownMultiplier =
		math.max(
			0.55,
			1
			- attackSpeedPoints
				* CompanionCatalog
					.Upgrades
					.AttackSpeed
					.BonusPerPoint
		)

	return {
		Behavior = behavior,
		AttackType = attackType,

		Damage =
			math.max(
				1,
				baseDamage
					* damageMultiplier
			),

		DamageMultiplier =
			damageMultiplier,

		AttackRange =
			math.max(
				1,
				baseRange
					+ rangePoints
						* CompanionCatalog
							.Upgrades
							.Range
							.BonusPerPoint
			),

		AttackCooldown =
			math.max(
				0.25,
				baseCooldown
					* cooldownMultiplier
			),

		AttackWindup =
			definition
				and (
					behavior
						== "NeutralMelee"
					and 0.2
					or 0.35
				)
				or config.AttackWindup,

		AttackRecovery =
			config.AttackRecovery,

		AttackHitboxSize =
			config.AttackHitboxSize,

		AttackOffset =
			config.AttackOffset,

		WalkSpeed =
			math.clamp(
				baseWalkSpeed
					* movementMultiplier
					* (
						1
						+ moveSpeedPoints
							* CompanionCatalog
								.Upgrades
								.MoveSpeed
								.BonusPerPoint
					),
				4,
				36
			),

		DetectionRange =
			math.min(
				CompanionCatalog
					.OwnerCombatRadius,

				math.max(
					config.DetectionRange,
					baseRange + 8
				)
					+ rangePoints
						* CompanionCatalog
							.Upgrades
							.Range
							.BonusPerPoint
			),

		PreferredDistance =
			definition
				and definition
					.PreferredDistance
				or math.max(
					config.StopDistance,
					baseRange
						* (
							attackType == "Ranged"
							and 0.7
							or 0.72
						)
				),

		RetreatDistance =
			definition
				and definition
					.RetreatDistance
				or 0,

		ProjectileSpeed =
			definition
				and definition
					.ProjectileSpeed
				or math.max(
					20,
					tonumber(
						model:GetAttribute(
							"ProjectileSpeed"
						)
					) or 60
				),

		ImpactRadius =
			definition
				and definition
					.ImpactRadius
				or math.max(
					2,
					tonumber(
						model:GetAttribute(
							"AttackImpactRadius"
						)
					) or 5
				),

		MortarWarningTime =
			definition
				and definition
					.MortarWarningTime
				or math.max(
					0.3,
					tonumber(
						model:GetAttribute(
							"AttackWindup"
						)
					) or 0.8
				),

		MortarArcHeight =
			definition
				and definition
					.MortarArcHeight
				or math.max(
					8,
					tonumber(
						model:GetAttribute(
							"ProjectileArcHeight"
						)
					) or 18
				),

		TeleportInterval =
			definition
				and definition
					.TeleportInterval
				or nil,

		HasGroundSlam =
			hasConfiguredAbility(
				model,
				"GroundSlam"
			),
	}
end

---------------------------------------------------------------------
-- Combat presentation and validation
---------------------------------------------------------------------

local function setCombatState(
	state,
	name
)
	state.Model:SetAttribute(
		"MonsterState",
		name
	)

	if state.IsSlime then
		local slimeState = "Melee"

		if name == "Ability"
			or state.CombatStats.AttackType
				== "Mortar"
		then
			slimeState = "Mortar"

		elseif state.CombatStats.AttackType
			== "Ranged"
		then
			slimeState = "RangedAttack"
		end

		state.Model:SetAttribute(
			"IsMoving",
			false
		)

		state.Model:SetAttribute(
			"AIState",
			slimeState
		)

	elseif state.Humanoid then
		MonsterAnimationLoader.Play(
			state.Model,
			state.Humanoid,
			name == "Ability"
				and "GroundSlam"
				or "Attack",
			0.06
		)
	end
end

local function isAlive(state)
	return state.Model.Parent ~= nil
		and state.Root.Parent ~= nil
		and state.Humanoid.Health > 0
end

local function targetIsValid(
	state,
	target
)
	return target
		and target.Model
		and target.Model.Parent
		and target.Humanoid
		and target.Humanoid.Health > 0
		and target.Root
		and target.Root.Parent
		and state.IsTargetValid(
			target.Model
		)
end

local function createBurst(
	position,
	color,
	size
)
	local burst =
		Instance.new("Part")

	burst.Name = "CompanionImpact"
	burst.Shape = Enum.PartType.Ball
	burst.Size =
		Vector3.new(
			size,
			size,
			size
		)
	burst.Position = position
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.Neon
	burst.Color = color
	burst.Transparency = 0.18
	burst.Parent = workspace

	Debris:AddItem(
		burst,
		0.28
	)
end

local function attackColor(state)
	local variant =
		state.Model:GetAttribute(
			"SlimeVariant"
		)

	local definition =
		type(variant) == "string"
		and SlimeVariants.GetDefinition(
			variant
		)
		or nil

	local configured =
		state.Model:GetAttribute(
			"CompanionAttackColor"
		)

	return typeof(configured) == "Color3"
		and configured
		or (
			definition
			and definition.Color
		)
		or Color3.fromRGB(
			111,
			230,
			159
		)
end

local function hasLineOfSight(
	state,
	target
)
	local direction =
		target.Root.Position
		- state.Root.Position

	if direction.Magnitude < 0.1 then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		state.Model,
		state.Owner.Character,
	}
	params.IgnoreWater = true

	local result =
		workspace:Raycast(
			state.Root.Position,
			direction,
			params
		)

	return not result
		or result.Instance
			:IsDescendantOf(
				target.Model
			)
end

local function applyHit(
	state,
	target,
	damage,
	source
)
	if not targetIsValid(
		state,
		target
	) then
		return false
	end

	-- Re-check physical-island ownership at the exact hit moment.
	if not targetMatchesOwnerIsland(
		state,
		target.Model,
		target.Root
	) then
		return false
	end

	local success =
		DamageService
			.ApplyCompanionHit(
				state.Owner,
				target,
				damage,
				source
			)

	if success then
		createBurst(
			target.Root.Position,
			attackColor(state),
			0.8
		)

		if state.CombatStats.Behavior
			== "IceRanged"
		then
			local model =
				target.Model

			local humanoid =
				target.Humanoid

			local now =
				workspace:GetServerTimeNow()

			local currentUntil =
				tonumber(
					model:GetAttribute(
						"CompanionIceSlowUntil"
					)
				) or 0

			if now >= currentUntil
				and humanoid
				and humanoid.Health > 0
			then
				local token =
					(
						tonumber(
							model:GetAttribute(
								"CompanionIceSlowToken"
							)
						) or 0
					) + 1

				local boss =
					model:GetAttribute(
						"SpawnMode"
					) == "Boss"
					or model:GetAttribute(
						"IsBoss"
					) == true

				local duration =
					boss
					and 0.45
					or 1.2

				local originalSpeed =
					humanoid.WalkSpeed

				model:SetAttribute(
					"CompanionIceSlowToken",
					token
				)

				model:SetAttribute(
					"CompanionIceSlowUntil",
					now + duration
				)

				humanoid.WalkSpeed =
					originalSpeed
						* (
							boss
							and 0.85
							or 0.6
						)

				task.delay(
					duration,
					function()
						if model.Parent
							and humanoid.Parent
							and humanoid.Health > 0
							and model:GetAttribute(
								"CompanionIceSlowToken"
							) == token
						then
							humanoid.WalkSpeed =
								originalSpeed

							model:SetAttribute(
								"CompanionIceSlowUntil",
								nil
							)
						end
					end
				)
			end
		end
	end

	return success
end

local function finishAttack(
	state,
	serial,
	delaySeconds
)
	task.delay(
		delaySeconds,
		function()
			if isAlive(state)
				and state.AttackSerial
					== serial
			then
				state.Busy = false

				local validTarget =
					state.Target
					and targetIsValid(
						state,
						state.Target
					)

				if not validTarget then
					state.Target = nil
				end

				state.Model:SetAttribute(
					"MonsterState",
					validTarget
						and "Chase"
						or "Idle"
				)

				if state.IsSlime then
					state.Model:SetAttribute(
						"AIState",
						validTarget
							and "Chase"
							or "Idle"
					)

					state.Model:SetAttribute(
						"IsMoving",
						validTarget == true
					)
				else
					MonsterAnimationLoader.Play(
						state.Model,
						state.Humanoid,
						validTarget
							and "Walk"
							or "Idle"
					)
				end
			end
		end
	)
end

---------------------------------------------------------------------
-- Attacks
---------------------------------------------------------------------

local function beginMelee(
	state,
	target,
	now
)
	local stats =
		state.CombatStats

	state.AttackSerial += 1

	local serial =
		state.AttackSerial

	state.Busy = true

	state.NextAttackAt =
		now
		+ math.max(
			stats.AttackCooldown,
			stats.AttackWindup
				+ stats.AttackRecovery
		)

	state.Humanoid:MoveTo(
		state.Root.Position
	)

	setCombatState(
		state,
		"Attack"
	)

	task.delay(
		stats.AttackWindup,
		function()
			if not isAlive(state)
				or state.AttackSerial
					~= serial
				or not targetIsValid(
					state,
					target
				)
			then
				return
			end

			local closeEnough =
				horizontalDistance(
					state.Root.Position,
					target.Root.Position
				)
					<= stats.AttackRange
						+ 1.5

			if closeEnough
				and math.abs(
					state.Root.Position.Y
						- target.Root.Position.Y
				) <= 8
				and hasLineOfSight(
					state,
					target
				)
			then
				applyHit(
					state,
					target,
					stats.Damage,
					"CompanionMelee"
				)
			end
		end
	)

	finishAttack(
		state,
		serial,
		stats.AttackWindup
			+ stats.AttackRecovery
	)

	return true
end

local function beginProjectile(
	state,
	target,
	now
)
	local stats =
		state.CombatStats

	state.AttackSerial += 1

	local serial =
		state.AttackSerial

	state.Busy = true

	state.NextAttackAt =
		now
		+ math.max(
			stats.AttackCooldown,
			stats.AttackWindup
				+ stats.AttackRecovery
		)

	state.Humanoid:MoveTo(
		state.Root.Position
	)

	setCombatState(
		state,
		"Attack"
	)

	task.delay(
		stats.AttackWindup,
		function()
			if not isAlive(state)
				or state.AttackSerial
					~= serial
				or not targetIsValid(
					state,
					target
				)
			then
				return
			end

			local origin =
				state.Root.Position
					+ Vector3.new(
						0,
						math.max(
							0.8,
							state.Root.Size.Y
								* 0.3
						),
						0
					)

			local offset =
				target.Root.Position
					+ Vector3.new(
						0,
						0.5,
						0
					)
					- origin

			if offset.Magnitude < 0.1
				or offset.Magnitude
					> stats.AttackRange + 4
				or not hasLineOfSight(
					state,
					target
				)
			then
				return
			end

			local direction =
				offset.Unit

			local projectile =
				Instance.new("Part")

			projectile.Name =
				"CompanionProjectile"

			projectile.Shape =
				Enum.PartType.Ball

			projectile.Size =
				Vector3.new(
					0.75,
					0.75,
					0.75
				)

			projectile.Position = origin
			projectile.Anchored = true
			projectile.CanCollide = false
			projectile.CanTouch = false
			projectile.CanQuery = false
			projectile.Material =
				Enum.Material.Neon
			projectile.Color =
				attackColor(state)
			projectile.Parent =
				workspace

			Debris:AddItem(
				projectile,
				4
			)

			local params =
				RaycastParams.new()

			params.FilterType =
				Enum.RaycastFilterType.Exclude

			params.FilterDescendantsInstances = {
				state.Model,
				state.Owner.Character,
			}

			params.IgnoreWater = true

			local travelled = 0

			task.spawn(function()
				while projectile.Parent
					and isAlive(state)
					and state.AttackSerial
						== serial
					and travelled
						< stats.AttackRange + 8
				do
					local dt =
						RunService.Heartbeat:Wait()

					local step =
						math.min(
							stats.ProjectileSpeed
								* dt,
							stats.AttackRange
								+ 8
								- travelled
						)

					local result =
						workspace:Raycast(
							projectile.Position,
							direction * step,
							params
						)

					if result then
						projectile.Position =
							result.Position

						if result.Instance
							:IsDescendantOf(
								target.Model
							)
						then
							applyHit(
								state,
								target,
								stats.Damage,
								"CompanionRanged"
							)
						end

						projectile:Destroy()
						return
					end

					projectile.Position +=
						direction * step

					travelled += step
				end

				if projectile.Parent then
					projectile:Destroy()
				end
			end)
		end
	)

	finishAttack(
		state,
		serial,
		stats.AttackWindup
			+ stats.AttackRecovery
	)

	return true
end

local function groundPosition(
	position,
	exclusions
)
	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		exclusions

	params.IgnoreWater = true

	local result =
		workspace:Raycast(
			position
				+ Vector3.new(
					0,
					25,
					0
				),
			Vector3.new(
				0,
				-70,
				0
			),
			params
		)

	return result
		and result.Position
		or position
end

local function damageEnemiesInRadius(
	state,
	position,
	radius,
	damage,
	source
)
	local _, ownerIndex =
		ownerPhysicalIsland(state)

	if not ownerIndex then
		return
	end

	for _, model in ipairs(
		CollectionService:GetTagged(
			"CombatTarget"
		)
	) do
		if state.IsTargetValid(model) then
			local humanoid =
				MonsterConfig
					.GetHumanoid(model)

			local root =
				MonsterConfig.GetRoot(model)

			if humanoid
				and humanoid.Health > 0
				and root
				and targetIslandIndex(
					model,
					root
				) == ownerIndex
				and horizontalDistance(
					root.Position,
					position
				) <= radius
				and math.abs(
					root.Position.Y
						- position.Y
				) <= 10
			then
				DamageService
					.ApplyCompanionHit(
						state.Owner,
						{
							Model = model,
							Humanoid = humanoid,
							Root = root,
						},
						damage,
						source
					)
			end
		end
	end
end

local function createCompanionFireGround(
	state,
	position,
	stats
)
	local radius =
		math.max(
			2.5,
			stats.ImpactRadius
				* 0.65
		)

	local duration = 3
	local interval = 0.75

	local fire =
		Instance.new("Part")

	fire.Name =
		"CompanionFireGround"

	fire.Shape =
		Enum.PartType.Cylinder

	fire.Size =
		Vector3.new(
			0.1,
			radius * 2,
			radius * 2
		)

	fire.CFrame =
		CFrame.new(
			position
				+ Vector3.new(
					0,
					0.08,
					0
				)
		)
		* CFrame.Angles(
			0,
			0,
			math.pi / 2
		)

	fire.Anchored = true
	fire.CanCollide = false
	fire.CanTouch = false
	fire.CanQuery = false
	fire.Material =
		Enum.Material.Neon
	fire.Color =
		attackColor(state)
	fire.Transparency = 0.48
	fire.Parent = workspace

	Debris:AddItem(
		fire,
		duration + 0.2
	)

	task.spawn(function()
		local expiresAt =
			workspace:GetServerTimeNow()
				+ duration

		while fire.Parent
			and isAlive(state)
			and workspace:GetServerTimeNow()
				< expiresAt
		do
			local _, ownerIndex =
				ownerPhysicalIsland(state)

			if not ownerIndex then
				break
			end

			damageEnemiesInRadius(
				state,
				position,
				radius,
				math.max(
					1,
					stats.Damage * 0.25
				),
				"CompanionFireGround"
			)

			task.wait(interval)
		end

		if fire.Parent then
			fire:Destroy()
		end
	end)
end

local function beginMortar(
	state,
	target,
	now
)
	local stats =
		state.CombatStats

	local impactPosition =
		groundPosition(
			target.Root.Position,
			{
				state.Model,
				state.Owner.Character,
				target.Model,
			}
		)

	state.AttackSerial += 1

	local serial =
		state.AttackSerial

	state.Busy = true

	state.NextAttackAt =
		now + stats.AttackCooldown

	state.Humanoid:MoveTo(
		state.Root.Position
	)

	setCombatState(
		state,
		"Attack"
	)

	local marker =
		Instance.new("Part")

	marker.Name =
		"CompanionMortarWarning"

	marker.Shape =
		Enum.PartType.Cylinder

	marker.Size =
		Vector3.new(
			0.12,
			stats.ImpactRadius * 2,
			stats.ImpactRadius * 2
		)

	marker.CFrame =
		CFrame.new(
			impactPosition
				+ Vector3.new(
					0,
					0.08,
					0
				)
		)
		* CFrame.Angles(
			0,
			0,
			math.pi / 2
		)

	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Material =
		Enum.Material.Neon
	marker.Color =
		attackColor(state)
	marker.Transparency = 0.62
	marker.Parent = workspace

	Debris:AddItem(
		marker,
		stats.MortarWarningTime + 0.4
	)

	local projectile =
		Instance.new("Part")

	projectile.Name =
		"CompanionMortar"

	projectile.Shape =
		Enum.PartType.Ball

	projectile.Size =
		Vector3.new(
			1.3,
			1.3,
			1.3
		)

	projectile.Position =
		state.Root.Position
			+ Vector3.new(
				0,
				2,
				0
			)

	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Material =
		Enum.Material.Neon
	projectile.Color =
		attackColor(state)
	projectile.Parent =
		workspace

	Debris:AddItem(
		projectile,
		stats.MortarWarningTime
			+ 0.5
	)

	local startPosition =
		projectile.Position

	local control =
		(
			startPosition
				+ impactPosition
		) / 2
		+ Vector3.new(
			0,
			stats.MortarArcHeight,
			0
		)

	task.spawn(function()
		local startedAt =
			workspace:GetServerTimeNow()

		while projectile.Parent
			and isAlive(state)
			and state.AttackSerial
				== serial
		do
			if not targetIsValid(
				state,
				target
			) then
				break
			end

			local alpha =
				math.clamp(
					(
						workspace
							:GetServerTimeNow()
						- startedAt
					)
						/ stats.MortarWarningTime,
					0,
					1
				)

			local inverse =
				1 - alpha

			projectile.Position =
				inverse
					* inverse
					* startPosition
				+ 2
					* inverse
					* alpha
					* control
				+ alpha
					* alpha
					* impactPosition

			marker.Transparency =
				0.62
				- alpha * 0.38

			if alpha >= 1 then
				break
			end

			RunService.Heartbeat:Wait()
		end

		if projectile.Parent
			and isAlive(state)
			and state.AttackSerial
				== serial
			and targetIsValid(
				state,
				target
			)
		then
			damageEnemiesInRadius(
				state,
				impactPosition,
				stats.ImpactRadius,
				stats.Damage,
				"CompanionMortar"
			)

			createBurst(
				impactPosition
					+ Vector3.new(
						0,
						0.5,
						0
					),
				attackColor(state),
				2.2
			)

			if stats.Behavior
				== "FireMortar"
			then
				createCompanionFireGround(
					state,
					impactPosition,
					stats
				)
			end
		end

		if projectile.Parent then
			projectile:Destroy()
		end

		if marker.Parent then
			marker:Destroy()
		end
	end)

	finishAttack(
		state,
		serial,
		stats.MortarWarningTime
			+ stats.AttackRecovery
	)

	return true
end

local function beginGroundSlam(
	state,
	now
)
	local stats =
		state.CombatStats

	local radius =
		math.max(
			2,
			(
				tonumber(
					state.Model:GetAttribute(
						"GroundSlamRadius"
					)
				) or 12
			)
				+ (
					stats.AttackRange
					- math.max(
						1,
						MonsterConfig
							.Read(
								state.Model
							)
							.AttackRange
					)
				) * 0.5
		)

	local windup =
		math.max(
			0.2,
			tonumber(
				state.Model:GetAttribute(
					"GroundSlamWindup"
				)
			) or 1
		)

	local recovery =
		math.max(
			0.1,
			tonumber(
				state.Model:GetAttribute(
					"GroundSlamRecovery"
				)
			) or 0.8
		)

	local cooldown =
		math.max(
			1,
			tonumber(
				state.Model:GetAttribute(
					"GroundSlamCooldown"
				)
			) or 8
		)

	local baseDamage =
		math.max(
			1,
			tonumber(
				state.Model:GetAttribute(
					"GroundSlamDamage"
				)
			)
				or (
					stats.Damage
						/ stats.DamageMultiplier
				) * 1.5
		)

	local damage =
		baseDamage
			* stats.DamageMultiplier

	state.AbilityCooldowns.GroundSlam =
		now + cooldown

	state.AttackSerial += 1

	local serial =
		state.AttackSerial

	state.Busy = true

	state.NextAttackAt =
		math.max(
			state.NextAttackAt,
			now
				+ windup
				+ recovery
		)

	state.Humanoid:MoveTo(
		state.Root.Position
	)

	setCombatState(
		state,
		"Ability"
	)

	local warning =
		Instance.new("Part")

	warning.Name =
		"CompanionGroundSlamWarning"

	warning.Shape =
		Enum.PartType.Cylinder

	warning.Size =
		Vector3.new(
			0.12,
			1,
			1
		)

	warning.CFrame =
		CFrame.new(
			state.Root.Position
				- Vector3.new(
					0,
					math.max(
						1,
						state.Root.Size.Y / 2
					),
					0
				)
		)
		* CFrame.Angles(
			0,
			0,
			math.rad(90)
		)

	warning.Anchored = true
	warning.CanCollide = false
	warning.CanTouch = false
	warning.CanQuery = false
	warning.Material =
		Enum.Material.Neon
	warning.Color =
		attackColor(state)
	warning.Transparency = 0.55
	warning.Parent = workspace

	TweenService:Create(
		warning,
		TweenInfo.new(
			windup,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			Size =
				Vector3.new(
					0.12,
					radius * 2,
					radius * 2
				),

			Transparency = 0.18,
		}
	):Play()

	Debris:AddItem(
		warning,
		windup + 0.3
	)

	task.delay(
		windup,
		function()
			if not isAlive(state)
				or state.AttackSerial
					~= serial
			then
				return
			end

			local _, ownerIndex =
				ownerPhysicalIsland(state)

			if not ownerIndex then
				return
			end

			damageEnemiesInRadius(
				state,
				state.Root.Position,
				radius,
				damage,
				"CompanionGroundSlam"
			)

			createBurst(
				state.Root.Position,
				attackColor(state),
				2.5
			)
		end
	)

	finishAttack(
		state,
		serial,
		windup + recovery
	)

	return true
end

---------------------------------------------------------------------
-- Public attack entry point
---------------------------------------------------------------------

function CompanionCombat.TryAttack(
	state,
	target,
	now
)
	ensureIslandGuard(state)

	local _, ownerIndex =
		ownerPhysicalIsland(state)

	if not ownerIndex then
		suppressDetectionRange(state)

		cancelCombat(
			state,
			"OwnerBetweenIslands",
			nil
		)

		return false
	end

	restoreDetectionRange(state)

	if not target
		or not target.Model
		or not targetMatchesOwnerIsland(
			state,
			target.Model,
			target.Root
		)
	then
		cancelCombat(
			state,
			"TargetOnDifferentIsland",
			ownerIndex
		)

		return false
	end

	setPassivePresentation(
		state,
		false,
		ownerIndex,
		"ValidSameIslandTarget"
	)

	if state.Busy
		or now < state.NextAttackAt
		or not targetIsValid(
			state,
			target
		)
	then
		return false
	end

	local stats =
		state.CombatStats

	local distance =
		horizontalDistance(
			state.Root.Position,
			target.Root.Position
		)

	if stats.HasGroundSlam
		and distance
			<= math.max(
				stats.AttackRange,
				tonumber(
					state.Model:GetAttribute(
						"GroundSlamRadius"
					)
				) or 12
			)
		and now
			>= (
				state.AbilityCooldowns
					.GroundSlam
				or 0
			)
	then
		return beginGroundSlam(
			state,
			now
		)
	end

	if distance > stats.AttackRange then
		return false
	end

	if stats.AttackType == "Mortar" then
		return beginMortar(
			state,
			target,
			now
		)

	elseif stats.AttackType == "Ranged" then
		return beginProjectile(
			state,
			target,
			now
		)

	elseif stats.AttackType == "Melee"
		or stats.AttackType == "Contact"
	then
		return beginMelee(
			state,
			target,
			now
		)
	end

	return false
end

return table.freeze(
	CompanionCombat
)
