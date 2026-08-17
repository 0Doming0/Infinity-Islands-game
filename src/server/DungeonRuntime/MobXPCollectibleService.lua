--[[
	Infinity Islands - MobXPCollectibleService V5 - Cycle-scaled physical XP

	Compatibility strategy:
	1. MonsterSpawner still calculates the authoritative mob XP value.
	2. Its existing PlayerLevelService.AwardXP(..., "MobDefeated:*") call is
	   intercepted and acknowledged WITHOUT increasing XP.
	3. This service listens to managed CombatTarget deaths.
	4. It calculates the final reward for the LAST HITTER.
	   XPReward already contains the server-authored cycle multiplier.
	5. It spawns physical fragments whose XP values sum exactly to that reward.
	6. XP is granted only when each fragment reaches the target player.

	MonsterSpawner, waves, AI, scaling and island combat do not need replacement.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local MobXPConfig = require(
	ReplicatedStorage.Shared.Configs.MobXPConfig
)

local CollectibleConfig = require(
	ReplicatedStorage.Shared.Configs.MobXPCollectibleConfig
)

local PlayerLevelService = require(
	script.Parent.PlayerLevelService
)

local AnimeOutline = require(
	ServerScriptService.MVPSystems.AnimeOutline
)

local Service = {}

local started = false
local originalAwardXP
local active = {}
local boundMobs =
	setmetatable({}, { __mode = "k" })
local spawnQueue = {}
local spawnQueueHead = 1
local queuedPieceCount = 0

local deathSerial = 0
local collectSerial = 0

local function runtimeFolder()
	local folder =
		workspace:FindFirstChild(
			CollectibleConfig.RuntimeFolderName
		)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name =
			CollectibleConfig.RuntimeFolderName
		folder.Parent = workspace
	end

	return folder
end

local function getRoot(model)
	if not model
		or not model:IsA("Model")
	then
		return nil
	end

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

	return root
		and root:IsA("BasePart")
		and root
		or nil
end

local function getHumanoid(model)
	return model
		and model:FindFirstChildWhichIsA(
			"Humanoid",
			true
		)
		or nil
end

local function validTargetPlayer(player)
	return player
		and player:IsA("Player")
		and player.Parent == Players
end

local function lastHitter(model, humanoid)
	local userId =
		model:GetAttribute(
			"LastDamagedByUserId"
		)
		or model:GetAttribute(
			"LastHitUserId"
		)

	if typeof(userId) == "number" then
		local player =
			Players:GetPlayerByUserId(userId)

		if validTargetPlayer(player) then
			return player
		end
	end

	local creator =
		humanoid
		and humanoid:FindFirstChild(
			"creator"
		)

	if creator
		and creator:IsA("ObjectValue")
		and validTargetPlayer(creator.Value)
	then
		return creator.Value
	end

	return nil
end

local function playerRoot(player)
	if not validTargetPlayer(player) then
		return nil
	end

	local character = player.Character

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
		return nil
	end

	return root
end

---------------------------------------------------------------------
-- Intercept only the old immediate mob-death delivery.
---------------------------------------------------------------------

local function installAwardInterceptor()
	if originalAwardXP then
		return
	end

	originalAwardXP =
		PlayerLevelService.AwardXP

	PlayerLevelService.AwardXP =
		function(player, amount, reason)
			local reasonText =
				tostring(reason or "")

			local prefix =
				"MobDefeated:"

			if string.sub(
				reasonText,
				1,
				#prefix
			) == prefix
			then
				if validTargetPlayer(player) then
					player:SetAttribute(
						"LastMobXPDeferredAmount",
						math.max(
							0,
							math.floor(
								tonumber(amount) or 0
							)
						)
					)

					player:SetAttribute(
						"LastMobXPDeferredAt",
						workspace:GetServerTimeNow()
					)

					player:SetAttribute(
						"MobXPDeliveryPolicy",
						CollectibleConfig.AwardPolicy
					)
				end

				-- MonsterSpawner considers the reward pipeline successfully
				-- handled, but the XP is intentionally not added yet.
				return true,
					"DeferredToPhysicalXPCollectibles"
			end

			return originalAwardXP(
				player,
				amount,
				reason
			)
		end
end

---------------------------------------------------------------------
-- Reuse old collectible assets when available.
---------------------------------------------------------------------

local function templateFolder()
	local assets =
		ServerStorage:FindFirstChild(
			"MVPAssets"
		)

	return assets
		and assets:FindFirstChild(
			"Collectibles"
		)
		or nil
end

local function chooseTemplateId(index)
	local ids =
		CollectibleConfig.TemplateIds

	return ids[
		((index - 1) % #ids) + 1
	]
end

local function templateColor(
	templateId,
	template
)
	if template then
		local configured =
			template:GetAttribute(
				"ParticleColor"
			)

		if typeof(configured) == "Color3" then
			return configured
		end

		local base =
			template:IsA("BasePart")
				and template
				or template:FindFirstChildWhichIsA(
					"BasePart",
					true
				)

		if base then
			return base.Color
		end
	end

	return CollectibleConfig
		.FallbackColors[templateId]
		or Color3.fromRGB(
			80,
			190,
			255
		)
end

local function prepareVisual(instance)
	for _, descendant in ipairs(
		instance:GetDescendants()
	) do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = true
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end

	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
	end
end

local function fallbackVisual(
	templateId,
	color
)
	local part = Instance.new("Part")
	part.Name = templateId

	part.Shape =
		templateId == "GoldenOrb"
			and Enum.PartType.Ball
			or Enum.PartType.Block

	local baseSize =
		templateId == "RubyShard"
			and Vector3.new(
				0.55,
				1.15,
				0.55
			)
			or Vector3.new(
				0.8,
				0.8,
				0.8
			)

	part.Size =
		baseSize
			* CollectibleConfig.VisualScale

	part.Material =
		Enum.Material.Neon
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false

	return part
end

local function cloneVisual(templateId)
	local folder =
		templateFolder()

	local template =
		folder
		and folder:FindFirstChild(
			templateId
		)

	if not template
		and folder
	then
		for _, candidate in ipairs(
			folder:GetChildren()
		) do
			if candidate:GetAttribute(
				"CollectibleId"
			) == templateId
			then
				template = candidate
				break
			end
		end
	end

	local color =
		templateColor(
			templateId,
			template
		)

	local visual

	if template
		and (
			template:IsA("Model")
			or template:IsA("BasePart")
		)
	then
		local ok, clone =
			pcall(
				template.Clone,
				template
			)

		if ok and clone then
			visual = clone
			visual.Name = "Visual"

			prepareVisual(visual)

			-- Preserve the rotation authored in Studio while removing only
			-- the stored world translation. The runtime will translate the
			-- collectible without rotating it during scatter/homing.
			if visual:IsA("Model") then
				local authoredPivot =
					visual:GetPivot()

				local authoredRotation =
					authoredPivot
						- authoredPivot.Position

				visual:PivotTo(
					authoredRotation
				)

				local okScale,
					currentScale =
						pcall(
							visual.GetScale,
							visual
						)

				if okScale
					and typeof(currentScale)
						== "number"
				then
					pcall(
						visual.ScaleTo,
						visual,
						currentScale
							* CollectibleConfig
								.VisualScale
					)
				end
			else
				local authoredRotation =
					visual.CFrame
						- visual.Position

				visual.CFrame =
					authoredRotation

				visual.Size *=
					CollectibleConfig
						.VisualScale
			end
		end
	end

	if not visual then
		visual =
			fallbackVisual(
				templateId,
				color
			)
	end

	return visual, color
end

-- ServerStorage templates only reach a client when the first XP drop is
-- created. Publish one inert copy of every collectible before combat so the
-- client can load its meshes, bones and effects without a death-frame hitch.
local function prewarmVisualTemplates()
	local folderName = CollectibleConfig.PrewarmFolderName
	local prewarmFolder = ReplicatedStorage:FindFirstChild(folderName)

	if prewarmFolder and not prewarmFolder:IsA("Folder") then
		warn("[MobXPCollectibleService] Prewarm ignorado: ReplicatedStorage/" .. folderName .. " nao e uma Folder.")
		return
	end

	if not prewarmFolder then
		prewarmFolder = Instance.new("Folder")
		prewarmFolder.Name = folderName
		prewarmFolder.Parent = ReplicatedStorage
	end

	for _, child in ipairs(prewarmFolder:GetChildren()) do
		child:Destroy()
	end

	prewarmFolder:SetAttribute("Ready", false)
	prewarmFolder:SetAttribute("TemplateCount", #CollectibleConfig.TemplateIds)

	task.spawn(function()
		local prepared = 0
		for _, templateId in ipairs(CollectibleConfig.TemplateIds) do
			local created, visualOrError = pcall(cloneVisual, templateId)
			if created and visualOrError then
				local visual = visualOrError
				visual.Name = templateId
				visual:SetAttribute("IsXPCollectiblePrewarm", true)
				visual.Parent = prewarmFolder
				prepared += 1
			else
				warn("[MobXPCollectibleService] Falha no prewarm de " .. templateId .. ": " .. tostring(visualOrError))
			end

			task.wait(math.max(0, tonumber(CollectibleConfig.PrewarmTemplateDelaySeconds) or 0))
		end

		prewarmFolder:SetAttribute("PreparedCount", prepared)
		prewarmFolder:SetAttribute("Ready", true)
		workspace:SetAttribute("DungeonXPCollectiblePrewarmReady", true)
		workspace:SetAttribute("DungeonXPCollectiblePrewarmPrepared", prepared)
	end)
end

local function addTrail(root, color)
	local attachment0 =
		Instance.new("Attachment")
	attachment0.Name = "TrailA"
	attachment0.Position =
		Vector3.new(
			-CollectibleConfig.TrailWidth
				* 0.5,
			0,
			0
		)
	attachment0.Parent = root

	local attachment1 =
		Instance.new("Attachment")
	attachment1.Name = "TrailB"
	attachment1.Position =
		Vector3.new(
			CollectibleConfig.TrailWidth
				* 0.5,
			0,
			0
		)
	attachment1.Parent = root

	local trail =
		Instance.new("Trail")
	trail.Name =
		"XPCollectibleTrail"
	trail.Attachment0 =
		attachment0
	trail.Attachment1 =
		attachment1
	trail.Color =
		ColorSequence.new(color)
	trail.LightEmission = 0.85
	trail.Lifetime =
		CollectibleConfig.TrailLifetime
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = root

	return trail
end

---------------------------------------------------------------------
-- XP fragments.
---------------------------------------------------------------------

local function splitXP(totalXP)
	totalXP =
		math.max(
			1,
			math.floor(
				tonumber(totalXP) or 1
			)
		)

	local count =
		math.min(
			totalXP,
			CollectibleConfig
				.GetPieceCount(totalXP)
		)

	local base =
		math.floor(
			totalXP / count
		)

	local remainder =
		totalXP - base * count

	local values =
		table.create(count)

	for index = 1, count do
		values[index] =
			base
			+ (
				index <= remainder
					and 1
					or 0
			)
	end

	return values
end

local function randomScatterVelocity(
	random
)
	local angle =
		random:NextNumber(
			0,
			math.pi * 2
		)

	local speed =
		random:NextNumber(
			CollectibleConfig
				.MinimumScatterSpeed,
			CollectibleConfig
				.MaximumScatterSpeed
		)

	local up =
		random:NextNumber(
			CollectibleConfig
				.MinimumScatterUpwardSpeed,
			CollectibleConfig
				.MaximumScatterUpwardSpeed
		)

	return Vector3.new(
		math.cos(angle) * speed,
		up,
		math.sin(angle) * speed
	)
end

local function raycastGround(
	entry,
	fromPosition,
	toPosition
)
	local delta =
		toPosition - fromPosition

	if delta.Magnitude < 0.001 then
		return nil
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	local excludes = {
		entry.Runtime,
	}

	if entry.TargetPlayer.Character then
		table.insert(
			excludes,
			entry.TargetPlayer.Character
		)
	end

	params.FilterDescendantsInstances =
		excludes

	return workspace:Raycast(
		fromPosition,
		delta,
		params
	)
end

local function moveRuntime(
	entry,
	position,
	_direction
)
	if not entry.Runtime.Parent then
		return
	end

	-- Position changes, rotation does not. This keeps the authored collectible
	-- orientation visually stable while it scatters and homes toward the player.
	entry.Runtime:PivotTo(
		CFrame.new(position)
	)

	entry.Position = position
end

local function changePending(
	player,
	delta
)
	if not validTargetPlayer(player) then
		return
	end

	player:SetAttribute(
		"PendingXPCollectibles",
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute(
						"PendingXPCollectibles"
					)
				) or 0
			) + delta
		)
	)
end

local function destroyEntry(
	entry,
	decrementPending
)
	if not entry
		or entry.Destroyed
	then
		return
	end

	entry.Destroyed = true
	active[entry.Runtime] = nil

	if decrementPending then
		changePending(
			entry.TargetPlayer,
			-1
		)
	end

	if entry.Runtime
		and entry.Runtime.Parent
	then
		entry.Runtime:Destroy()
	end
end

local function collectibleTouchesTarget(entry)
	if not entry
		or not entry.Runtime
		or not entry.Runtime.Parent
		or not validTargetPlayer(
			entry.TargetPlayer
		)
	then
		return false
	end

	local character =
		entry.TargetPlayer.Character

	local humanoid =
		character
		and character:FindFirstChildOfClass(
			"Humanoid"
		)

	if not character
		or not humanoid
		or humanoid.Health <= 0
	then
		return false
	end

	-- Use the actual rendered collectible bounds, not the invisible root and
	-- not a cached player position. The overlap query is evaluated against the
	-- CURRENT Character hierarchy on every near-contact heartbeat.
	local okBounds, boxCFrame, boxSize =
		pcall(function()
			return entry.Runtime:GetBoundingBox()
		end)

	if not okBounds
		or typeof(boxCFrame) ~= "CFrame"
		or typeof(boxSize) ~= "Vector3"
	then
		return false
	end

	local params = OverlapParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {
		character,
	}
	params.MaxParts = 16

	local touchingParts =
		workspace:GetPartBoundsInBox(
			boxCFrame,
			boxSize,
			params
		)

	for _, part in ipairs(touchingParts) do
		if part:IsA("BasePart")
			and part:IsDescendantOf(character)
			and part.Transparency < 1
		then
			return true
		end
	end

	return false
end

local function awardPiece(entry)
	if entry.Claimed
		or entry.Destroyed
	then
		return
	end

	entry.Claimed = true
	active[entry.Runtime] = nil

	local player =
		entry.TargetPlayer

	local granted = false

	if validTargetPlayer(player)
		and originalAwardXP
	then
		local success =
			originalAwardXP(
				player,
				entry.XPValue,
				"XPCollectible:"
					.. tostring(
						entry.SourceMonsterId
					)
			)

		if success then
			granted = true
			collectSerial += 1

			player:SetAttribute(
				"LastXPCollectibleValue",
				entry.XPValue
			)
			player:SetAttribute(
				"LastXPCollectibleAt",
				workspace:GetServerTimeNow()
			)
			player:SetAttribute(
				"XPCollectibleCollectedSerial",
				collectSerial
			)
		end
	end

	if granted then
		changePending(
			player,
			-1
		)
	end

	if entry.Root
		and entry.Root.Parent
	then
		local particles =
			Instance.new(
				"ParticleEmitter"
			)

		particles.Color =
			ColorSequence.new(
				entry.Color
			)
		particles.LightEmission = 1
		particles.Lifetime =
			NumberRange.new(
				0.12,
				0.28
			)
		particles.Speed =
			NumberRange.new(
				3,
				7
			)
		particles.SpreadAngle =
			Vector2.new(
				180,
				180
			)
		particles.Rate = 0
		particles.Parent =
			entry.Root

		particles:Emit(10)
	end

	Debris:AddItem(
		entry.Runtime,
		0.18
	)
end

local function createPiece(
	targetPlayer,
	position,
	xpValue,
	index,
	random,
	metadata
)
	local templateId =
		chooseTemplateId(index)

	local visual, color =
		cloneVisual(templateId)

	local runtime =
		Instance.new("Model")

	runtime.Name =
		"XP_"
		.. templateId
		.. "_"
		.. tostring(index)

	local root =
		Instance.new("Part")

	root.Name =
		"XPCollectibleRoot"
	root.Size =
		Vector3.new(
			0.45,
			0.45,
			0.45
		)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Parent = runtime

	visual.Parent = runtime
	runtime.PrimaryPart = root

	-- Restore the thin near-black outline from the old collectible system.
	AnimeOutline.Apply(
		runtime,
		{
			OutlineColor =
				CollectibleConfig.OutlineColor,
			OutlineTransparency =
				CollectibleConfig
					.OutlineTransparency,
			FillTransparency =
				CollectibleConfig
					.FillTransparency,
			DepthMode =
				Enum.HighlightDepthMode
					.Occluded,
		}
	)

	local trail =
		addTrail(
			root,
			color
		)

	local spawnPosition =
		position
			+ Vector3.new(
				random:NextNumber(
					-0.35,
					0.35
				),
				random:NextNumber(
					0.8,
					1.5
				),
				random:NextNumber(
					-0.35,
					0.35
				)
			)

	runtime:PivotTo(
		CFrame.new(spawnPosition)
	)

	local entry = {
		Runtime = runtime,
		Root = root,
		Trail = trail,
		Color = color,
		TargetPlayer = targetPlayer,
		XPValue = xpValue,
		Position = spawnPosition,
		Velocity =
			randomScatterVelocity(
				random
			),
		SpawnAt =
			workspace:GetServerTimeNow(),
		HomingSpeed =
			CollectibleConfig
				.MagnetStartSpeed,
		Grounded = false,
		Claimed = false,
		Destroyed = false,
		SourceMonsterId =
			metadata.MonsterId,
		MobLevel =
			metadata.MobLevel,
		RecommendedLevel =
			metadata.RecommendedLevel,
		GlobalIslandIndex =
			metadata.GlobalIslandIndex,
		CycleIndex =
			metadata.CycleIndex,
		XPRewardMultiplier =
			metadata.XPRewardMultiplier,
	}

	for _, instance in ipairs({
		runtime,
		root,
	}) do
		instance:SetAttribute(
			"IsXPCollectible",
			true
		)
		instance:SetAttribute(
			"XPValue",
			xpValue
		)
		instance:SetAttribute(
			"TargetUserId",
			targetPlayer.UserId
		)
		instance:SetAttribute(
			"CollectibleId",
			templateId
		)
		instance:SetAttribute(
			"CollectPolicy",
			"ActualCharacterOverlapV1"
		)
		instance:SetAttribute(
			"VisualScale",
			CollectibleConfig.VisualScale
		)
		instance:SetAttribute(
			"MobLevel",
			metadata.MobLevel
		)
		instance:SetAttribute(
			"RecommendedLevel",
			metadata.RecommendedLevel
		)
		instance:SetAttribute(
			"GlobalIslandIndex",
			metadata.GlobalIslandIndex
		)
		instance:SetAttribute(
			"CycleIndex",
			metadata.CycleIndex
		)
		instance:SetAttribute(
			"XPRewardMultiplier",
			metadata.XPRewardMultiplier
		)
	end

	-- Publish only the fully assembled model. Parenting earlier makes the
	-- server replicate the visual, outline, trail and attributes as separate
	-- updates, which amplifies the first collectible burst frame spike.
	runtime.Parent = runtimeFolder()
	active[runtime] = entry

	return entry
end

local function updateQueueDiagnostics()
	if workspace:GetAttribute(
		"DungeonXPCollectibleQueuedPieces"
	) ~= queuedPieceCount
	then
		workspace:SetAttribute(
			"DungeonXPCollectibleQueuedPieces",
			queuedPieceCount
		)
	end
end

local function queueRewardPieces(
	player,
	position,
	values,
	random,
	metadata
)
	table.insert(
		spawnQueue,
		{
			TargetPlayer = player,
			Position = position,
			Values = values,
			Random = random,
			Metadata = metadata,
			NextIndex = 1,
		}
	)

	queuedPieceCount += #values
	updateQueueDiagnostics()
end

local function grantFailedQueuedPiece(
	job,
	xpValue,
	errorMessage
)
	local player = job.TargetPlayer

	-- A visual creation failure must never make the player lose earned XP.
	-- This path is exceptional; normal rewards remain physical collectibles.
	if validTargetPlayer(player)
		and originalAwardXP
	then
		originalAwardXP(
			player,
			xpValue,
			"XPCollectibleSpawnFallback:"
				.. tostring(
					job.Metadata.MonsterId
				)
		)
	end

	changePending(player, -1)

	warn(
		"[MobXPCollectibleService] falha ao criar fragmento; "
			.. "XP entregue diretamente: "
			.. tostring(errorMessage)
	)
end

local function compactSpawnQueue()
	if spawnQueueHead > #spawnQueue then
		table.clear(spawnQueue)
		spawnQueueHead = 1
		return
	end

	if spawnQueueHead <= 64 then
		return
	end

	local compacted =
		table.create(
			#spawnQueue
				- spawnQueueHead
				+ 1
		)

	for index = spawnQueueHead, #spawnQueue do
		table.insert(
			compacted,
			spawnQueue[index]
		)
	end

	spawnQueue = compacted
	spawnQueueHead = 1
end

local function processSpawnQueue()
	if spawnQueueHead > #spawnQueue then
		return
	end

	local budget =
		math.max(
			1,
			math.floor(
				tonumber(
					CollectibleConfig
						.MaxPieceCreationsPerHeartbeat
				) or 1
			)
		)

	while budget > 0
		and spawnQueueHead <= #spawnQueue
	do
		local job =
			spawnQueue[spawnQueueHead]

		if not validTargetPlayer(
			job.TargetPlayer
		) then
			local remaining =
				#job.Values
					- job.NextIndex
					+ 1

			queuedPieceCount =
				math.max(
					0,
					queuedPieceCount
						- remaining
				)

			spawnQueueHead += 1
			continue
		end

		local index = job.NextIndex
		local xpValue = job.Values[index]

		local created, errorMessage =
			pcall(
				createPiece,
				job.TargetPlayer,
				job.Position,
				xpValue,
				index,
				job.Random,
				job.Metadata
			)

		if not created then
			grantFailedQueuedPiece(
				job,
				xpValue,
				errorMessage
			)
		end

		job.NextIndex += 1
		queuedPieceCount =
			math.max(
				0,
				queuedPieceCount - 1
			)

		if job.NextIndex > #job.Values then
			spawnQueueHead += 1
		end

		budget -= 1
	end

	compactSpawnQueue()
	updateQueueDiagnostics()
end

local function spawnRewardBurst(
	player,
	position,
	totalXP,
	metadata
)
	if not validTargetPlayer(player)
		or typeof(position) ~= "Vector3"
	then
		return false
	end

	local values =
		splitXP(totalXP)

	deathSerial += 1

	local rawSeed =
		math.floor(
			math.abs(
				player.UserId
					* 104729
				+ deathSerial
					* 130363
				+ position.X * 11
				+ position.Z * 17
			)
		) % 2147483647

	local random =
		Random.new(
			rawSeed == 0
				and 1
				or rawSeed
		)

	changePending(
		player,
		#values
	)

	queueRewardPieces(
		player,
		position,
		values,
		random,
		metadata
	)

	player:SetAttribute(
		"LastMobXPCollectibleTotal",
		totalXP
	)
	player:SetAttribute(
		"LastMobXPCollectibleCount",
		#values
	)
	player:SetAttribute(
		"LastMobXPCollectibleSpawnAt",
		workspace:GetServerTimeNow()
	)
	player:SetAttribute(
		"LastMobXPCycleIndex",
		metadata.CycleIndex
	)
	player:SetAttribute(
		"LastMobXPRewardMultiplier",
		metadata.XPRewardMultiplier
	)
	player:SetAttribute(
		"LastMobXPRiskLevel",
		metadata.RecommendedLevel
	)

	workspace:SetAttribute(
		"DungeonLastXPCollectibleBurstCount",
		#values
	)
	workspace:SetAttribute(
		"DungeonLastXPCollectibleBurstXP",
		totalXP
	)
	workspace:SetAttribute(
		"DungeonXPCollectiblePolicy",
		CollectibleConfig.AwardPolicy
	)

	return true
end

local function heartbeat(dt)
	-- Keep expensive template cloning and replication off the death frame.
	-- The queue preserves every piece and all XP, but publishes only a small
	-- number of fully assembled collectible models per Heartbeat.
	processSpawnQueue()

	local now =
		workspace:GetServerTimeNow()

	for runtime, entry in pairs(active) do
		if not runtime.Parent then
			active[runtime] = nil
			continue
		end

		if not validTargetPlayer(
			entry.TargetPlayer
		)
		then
			destroyEntry(
				entry,
				false
			)
			continue
		end

		local age =
			now - entry.SpawnAt

		if age >=
			CollectibleConfig
				.MaximumLifetime
		then
			destroyEntry(
				entry,
				true
			)
			continue
		end

		if age <
			CollectibleConfig
				.ScatterDuration
		then
			local oldPosition =
				entry.Position

			entry.Velocity +=
				Vector3.new(
					0,
					-CollectibleConfig
						.ScatterGravity
						* dt,
					0
				)

			local nextPosition =
				oldPosition
					+ entry.Velocity * dt

			local hit =
				raycastGround(
					entry,
					oldPosition,
					nextPosition
				)

			if hit
				and entry.Velocity.Y <= 0
			then
				nextPosition =
					hit.Position
						+ hit.Normal
							* CollectibleConfig
								.GroundHoverHeight

				entry.Velocity =
					Vector3.zero

				entry.Grounded = true
			end

			moveRuntime(
				entry,
				nextPosition,
				entry.Velocity
			)
		else
			local targetRoot =
				playerRoot(
					entry.TargetPlayer
				)

			if not targetRoot then
				entry.Trail.Enabled =
					false
				continue
			end

			entry.Trail.Enabled =
				true

			local targetPosition =
				targetRoot.Position
					+ Vector3.new(
						0,
						CollectibleConfig
							.MagnetTargetHeight,
						0
					)

			local difference =
				targetPosition
					- entry.Position

			local distance =
				difference.Magnitude

			-- Distance is now ONLY an optimization gate. XP is never awarded
			-- just because the collectible is near the player's root position.
			-- The actual visual bounds must overlap the player's CURRENT body.
			if distance <=
				CollectibleConfig
					.ContactCheckDistance
				and collectibleTouchesTarget(
					entry
				)
			then
				awardPiece(entry)
				continue
			end

			entry.HomingSpeed =
				math.min(
					CollectibleConfig
						.MagnetMaximumSpeed,
					entry.HomingSpeed
						+ CollectibleConfig
							.MagnetAcceleration
							* dt
				)

			local direction =
				distance > 0.001
					and difference.Unit
					or Vector3.zero

			local travel =
				math.min(
					distance,
					entry.HomingSpeed * dt
				)

			moveRuntime(
				entry,
				entry.Position
					+ direction * travel,
				direction
			)
		end
	end
end

---------------------------------------------------------------------
-- Strong final-hit death presentation.
---------------------------------------------------------------------

local function deathKnockback(
	model,
	killer
)
	task.delay(
		CollectibleConfig
			.DeathKnockbackDelay,
		function()
			if not model.Parent then
				return
			end

			local root =
				getRoot(model)

			if not root then
				return
			end

			local killerRoot =
				playerRoot(killer)

			local direction

			if killerRoot then
				direction =
					Vector3.new(
						root.Position.X
							- killerRoot.Position.X,
						0,
						root.Position.Z
							- killerRoot.Position.Z
					)
			end

			if not direction
				or direction.Magnitude < 0.05
			then
				local look =
					root.CFrame.LookVector

				direction =
					Vector3.new(
						look.X,
						0,
						look.Z
					)
			end

			if direction.Magnitude < 0.05 then
				direction =
					Vector3.new(
						0,
						0,
						-1
					)
			end

			direction = direction.Unit

			for _, descendant in ipairs(
				model:GetDescendants()
			) do
				if descendant:IsA(
					"BasePart"
				)
				then
					descendant.Anchored =
						false
					descendant.CanCollide =
						false
					descendant.CanTouch =
						false
				end
			end

			pcall(function()
				root:SetNetworkOwner(nil)
			end)

			root.AssemblyLinearVelocity =
				direction
					* CollectibleConfig
						.DeathHorizontalSpeed
				+ Vector3.new(
					0,
					CollectibleConfig
						.DeathUpwardSpeed,
					0
				)

			root.AssemblyAngularVelocity =
				Vector3.new(
					CollectibleConfig
						.DeathAngularSpeed
						* 0.6,
					CollectibleConfig
						.DeathAngularSpeed,
					CollectibleConfig
						.DeathAngularSpeed
						* 0.35
				)

			model:SetAttribute(
				"DeathKnockbackApplied",
				true
			)
			model:SetAttribute(
				"DeathKnockbackPolicy",
				"StrongFinalHitV1"
			)
		end
	)
end

local function onManagedMobDied(
	model,
	humanoid
)
	if model:GetAttribute(
		"XPCollectibleDeathHandled"
	) == true
	then
		return
	end

	model:SetAttribute(
		"XPCollectibleDeathHandled",
		true
	)

	local killer =
		lastHitter(
			model,
			humanoid
		)

	if not killer then
		model:SetAttribute(
			"XPCollectibleDeathStatus",
			"NoLastHitter"
		)
		return
	end

	local root =
		getRoot(model)

	local deathPosition =
		root
		and root.Position
		or model:GetPivot().Position

	local mobLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					model:GetAttribute(
						"MobLevel"
					)
				) or 1
			)
		)

	local riskRewardLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					model:GetAttribute(
						"RecommendedLevel"
					)
				) or mobLevel
			)
		)

	local baseReward =
		math.max(
			1,
			math.floor(
				tonumber(
					model:GetAttribute(
						"XPReward"
					)
				)
					or MobXPConfig
						.GetMobXPReward(
							model:GetAttribute(
								"SlimeVariant"
							),
							mobLevel,
							model:GetAttribute(
								"XPRewardMultiplier"
							)
						)
			)
		)

	local playerLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					killer:GetAttribute(
						"PlayerLevel"
					)
				) or 1
			)
		)

	local totalXP, riskBonus =
		MobXPConfig
			.GetAwardForPlayer(
				baseReward,
				riskRewardLevel,
				playerLevel
			)

	local metadata = {
		MonsterId =
			model:GetAttribute(
				"MonsterId"
			)
				or model.Name,

		MobLevel = mobLevel,

		RecommendedLevel = riskRewardLevel,

		GlobalIslandIndex =
			model:GetAttribute(
				"GlobalIslandIndex"
			),

		CycleIndex =
			model:GetAttribute(
				"CycleIndex"
			),

		XPRewardMultiplier =
			model:GetAttribute(
				"XPRewardMultiplier"
			),

		RiskBonus = riskBonus,
	}

	model:SetAttribute(
		"XPCollectibleTargetUserId",
		killer.UserId
	)
	model:SetAttribute(
		"XPCollectibleTotalXP",
		totalXP
	)
	model:SetAttribute(
		"XPCollectibleRiskBonus",
		riskBonus
	)
	model:SetAttribute(
		"XPCollectibleDeathStatus",
		"FragmentsSpawned"
	)

	deathKnockback(
		model,
		killer
	)

	spawnRewardBurst(
		killer,
		deathPosition,
		totalXP,
		metadata
	)
end

local function bindMob(model)
	if boundMobs[model]
		or not model:IsA("Model")
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
		getHumanoid(model)

	if not humanoid then
		return
	end

	boundMobs[model] = true

	humanoid.Died:Connect(function()
		onManagedMobDied(
			model,
			humanoid
		)
	end)
end

---------------------------------------------------------------------
-- Public physical-XP reward API
---------------------------------------------------------------------

function Service.SpawnXPBurst(
	player,
	position,
	totalXP,
	metadata
)
	if not started
		or not originalAwardXP
	then
		return false,
			"XPCollectibleServiceNotReady"
	end

	if not validTargetPlayer(player) then
		return false,
			"InvalidTargetPlayer"
	end

	if typeof(position) ~= "Vector3" then
		return false,
			"InvalidBurstPosition"
	end

	totalXP =
		math.max(
			1,
			math.floor(
				tonumber(totalXP) or 0
			)
		)

	metadata =
		type(metadata) == "table"
			and table.clone(metadata)
			or {}

	metadata.MonsterId =
		metadata.MonsterId
			or metadata.SourceId
			or "ExternalXPReward"

	metadata.MobLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					metadata.MobLevel
						or metadata.IslandLevel
				) or 1
			)
		)

	return spawnRewardBurst(
		player,
		position,
		totalXP,
		metadata
	)
end

function Service.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	installAwardInterceptor()
	runtimeFolder()
	prewarmVisualTemplates()

	CollectionService
		:GetInstanceAddedSignal(
			"CombatTarget"
		)
		:Connect(function(instance)
			task.defer(
				bindMob,
				instance
			)
		end)

	for _, instance in ipairs(
		CollectionService:GetTagged(
			"CombatTarget"
		)
	) do
		task.defer(
			bindMob,
			instance
		)
	end

	RunService.Heartbeat:Connect(
		heartbeat
	)

	workspace:SetAttribute(
		"DungeonXPCollectibleServiceReady",
		true
	)
	workspace:SetAttribute(
		"DungeonXPCollectibleVersion",
		CollectibleConfig.Version
	)
	workspace:SetAttribute(
		"DungeonXPCollectiblePolicy",
		CollectibleConfig.AwardPolicy
	)
	workspace:SetAttribute(
		"DungeonDeathKnockbackPolicy",
		"StrongFinalHitV1"
	)
	workspace:SetAttribute(
		"DungeonXPCollectibleContactPolicy",
		"ActualCharacterOverlapV1"
	)
	workspace:SetAttribute(
		"DungeonXPCollectibleVisualScale",
		CollectibleConfig.VisualScale
	)
	workspace:SetAttribute(
		"DungeonXPCollectibleSpawnBudgetPerHeartbeat",
		CollectibleConfig.MaxPieceCreationsPerHeartbeat
	)
	updateQueueDiagnostics()

	print(
		"[MobXPCollectibleService] ativo: "
			.. "death knockback + physical XP fragments."
	)

	return true
end

return Service
