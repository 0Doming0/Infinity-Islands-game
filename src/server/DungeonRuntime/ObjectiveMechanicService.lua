local CollectionService = game:GetService("CollectionService")

local ObjectiveMechanicService = {}

local POLICY = "DistinctObjectiveMechanicsV2"
local statesByEncounterId = {}
local started = false

local function now()
	return workspace:GetServerTimeNow()
end

local function addHighlight(model, name, outlineColor, fillTransparency)
	local old = model:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.Adornee = model
	highlight.FillColor = outlineColor
	highlight.FillTransparency = fillTransparency or 0.82
	highlight.OutlineColor = outlineColor
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	return highlight
end

local function setMechanicAttributes(encounter, state)
	local mechanic = state.Mechanic
	workspace:SetAttribute("DungeonObjectiveMechanicsReady", started)
	workspace:SetAttribute("DungeonObjectiveMechanicsPolicy", POLICY)
	workspace:SetAttribute("DungeonObjectiveMechanic", mechanic)
	workspace:SetAttribute("DungeonObjectiveMechanicEncounterId", encounter.Id)
	workspace:SetAttribute("DungeonObjectiveMechanicState", state.State)
	workspace:SetAttribute("DungeonObjectiveMechanicUpdatedAt", now())
	local island = encounter.Context and encounter.Context.IslandModel
	if island and island.Parent then
		island:SetAttribute("ObjectiveGameplayIdentity", mechanic)
		island:SetAttribute("ObjectiveMechanicState", state.State)
		island:SetAttribute("ObjectiveMechanicVersion", 1)
	end
end

local function stateFor(encounter)
	return encounter and statesByEncounterId[encounter.Id] or nil
end

local function markObjectiveTarget(encounter, model, priority)
	if not model or not model.Parent then
		return
	end
	model:SetAttribute("ObjectiveId", encounter.Definition.Id)
	model:SetAttribute("GlobalIslandIndex", encounter.Definition.GlobalIslandIndex)
	model:SetAttribute("ObjectivePriorityTarget", priority == true)
	CollectionService:AddTag(model, "DungeonObjectiveTarget")
	if priority == true then
		CollectionService:AddTag(model, "DungeonObjectivePriorityTarget")
	end
end

local function clearPriorityTarget(model)
	if not model then
		return
	end
	model:SetAttribute("ObjectivePriorityTarget", false)
	if CollectionService:HasTag(model, "DungeonObjectivePriorityTarget") then
		CollectionService:RemoveTag(model, "DungeonObjectivePriorityTarget")
	end
end

local function setModelPartsVisible(model, visible, state)
	state.HiddenPartState = state.HiddenPartState or setmetatable({}, { __mode = "k" })
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if not state.HiddenPartState[descendant] then
				state.HiddenPartState[descendant] = {
					Transparency = descendant.Transparency,
					CastShadow = descendant.CastShadow,
				}
			end
			local saved = state.HiddenPartState[descendant]
			descendant.Transparency = visible and saved.Transparency or 1
			descendant.CastShadow = visible and saved.CastShadow or false
		end
	end
end

local function revealAmbushModel(encounter, state, model)
	if not statesByEncounterId[encounter.Id]
		or statesByEncounterId[encounter.Id] ~= state
		or not model.Parent
	then
		return
	end
	setModelPartsVisible(model, true, state)
	model:SetAttribute("ObjectiveAmbushHidden", false)
	model:SetAttribute("Invulnerable", false)
	model:SetAttribute("SimulationActive", state.CombatEnabled == true)
	addHighlight(model, "AmbushRevealOutline", Color3.fromRGB(255, 96, 96), 0.93)
	task.delay(0.8, function()
		local outline = model:FindFirstChild("AmbushRevealOutline")
		if outline then
			outline:Destroy()
		end
	end)
	state.PendingRevealCount = math.max(0, state.PendingRevealCount - 1)
	state.State = state.PendingRevealCount > 0 and "RevealingAmbush" or "AmbushRevealed"
	setMechanicAttributes(encounter, state)
end

local function registerAmbushEnemy(encounter, state, model)
	if not state.AmbushRevealAt then
		state.AmbushRevealAt = now() + math.max(0.25, tonumber(encounter.Plan.AmbushRevealDelaySeconds) or 0.85)
		workspace:SetAttribute("DungeonAmbushRevealAt", state.AmbushRevealAt)
		local island = encounter.Context and encounter.Context.IslandModel
		if island then
			island:SetAttribute("ObjectiveAmbushRevealAt", state.AmbushRevealAt)
		end
	end
	state.PendingRevealCount += 1
	state.State = "AmbushHidden"
	model:SetAttribute("ObjectiveAmbushHidden", true)
	model:SetAttribute("Invulnerable", true)
	model:SetAttribute("SimulationActive", false)
	setModelPartsVisible(model, false, state)
	setMechanicAttributes(encounter, state)
	task.delay(math.max(0, state.AmbushRevealAt - now()), function()
		revealAmbushModel(encounter, state, model)
	end)
end

local function createWardModel(encounter, state, marker, index)
	local model = Instance.new("Model")
	model.Name = string.format("ObjectiveGuardWard_%02d", index)
	model:SetAttribute("ObjectiveMechanicActor", true)
	model:SetAttribute("ObjectiveMechanicActorType", "GuardWard")
	model:SetAttribute("ObjectiveEncounterId", encounter.Id)
	model:SetAttribute("ObjectiveId", encounter.Definition.Id)
	model:SetAttribute("GlobalIslandIndex", encounter.Definition.GlobalIslandIndex)
	model:SetAttribute("RuntimeMonster", false)
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("CanBeStunned", false)
	model:SetAttribute("NoKnockback", true)
	model:SetAttribute("SimulationActive", true)
	model:SetAttribute("Invulnerable", true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(4.5, 6.5, 4.5)
	local objectiveAnchor = encounter.Context and encounter.Context.ObjectiveAnchor
	local centerPosition = objectiveAnchor and objectiveAnchor.Position or marker.Position
	local inward = Vector3.new(
		centerPosition.X - marker.Position.X,
		0,
		centerPosition.Z - marker.Position.Z
	)
	if inward.Magnitude < 0.1 then
		inward = Vector3.new(index % 2 == 0 and 1 or -1, 0, 0)
	else
		inward = inward.Unit
	end
	local wardPosition = marker.Position + inward * 8 + Vector3.new(0, 3.15, 0)
	root.CFrame = CFrame.lookAt(wardPosition, Vector3.new(centerPosition.X, wardPosition.Y, centerPosition.Z))
	root.Anchored = true
	root.CanCollide = true
	root.CanTouch = false
	root.CanQuery = true
	root.Material = Enum.Material.Neon
	root.Color = Color3.fromRGB(105, 146, 255)
	root.Parent = model

	local ring = Instance.new("Part")
	ring.Name = "WardRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.45, 7, 7)
	ring.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.ForceField
	ring.Color = Color3.fromRGB(124, 96, 255)
	ring.Transparency = 0.35
	ring.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = math.max(30, math.floor(tonumber(encounter.Plan.GuardWardHealth) or 70))
	humanoid.Health = humanoid.MaxHealth
	humanoid.DisplayName = "Cristal de Protecao"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = encounter.Context.IslandModel
	CollectionService:AddTag(model, "CombatTarget")
	CollectionService:AddTag(model, "DungeonGuardWard")
	markObjectiveTarget(encounter, model, true)
	addHighlight(model, "GuardWardOutline", Color3.fromRGB(119, 164, 255), 0.76)

	state.Wards[model] = true
	state.WardsAlive += 1
	humanoid.Died:Connect(function()
		if state.Wards[model] ~= true then
			return
		end
		state.Wards[model] = nil
		state.WardsAlive = math.max(0, state.WardsAlive - 1)
		model:SetAttribute("ObjectiveTargetCompleted", true)
		root.CanCollide = false
		workspace:SetAttribute("DungeonGuardWardsRemaining", state.WardsAlive)
		if state.WardsAlive <= 0 then
			state.State = "GuardWardsBroken"
			for guard in pairs(state.Guards) do
				if guard.Parent then
					guard:SetAttribute("GuardWardProtected", false)
					guard:SetAttribute("Invulnerable", false)
					markObjectiveTarget(encounter, guard, true)
					local shield = guard:FindFirstChild("GuardWardShield")
					if shield then
						shield:Destroy()
					end
				end
			end
			setMechanicAttributes(encounter, state)
		end
		task.delay(0.45, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)
	return model
end

local function createGuardWards(encounter, state)
	local count = math.clamp(math.floor(tonumber(encounter.Plan.GuardWardCount) or 2), 1, 3)
	local markers = encounter.EnemyMarkers
	for index = 1, count do
		local marker
		if #markers > 0 then
			local markerIndex = math.floor(((index - 1) * #markers) / count) + 1
			marker = markers[math.clamp(markerIndex, 1, #markers)]
		end
		marker = marker or encounter.Context.ObjectiveAnchor
		if marker then
			createWardModel(encounter, state, marker, index)
		end
	end
	workspace:SetAttribute("DungeonGuardWardsRemaining", state.WardsAlive)
	workspace:SetAttribute("DungeonGuardWardCount", state.WardsAlive)
	state.State = "BreakGuardWards"
end

local function protectGuard(state, model)
	state.Guards[model] = true
	model:SetAttribute("GuardWardProtected", state.WardsAlive > 0)
	model:SetAttribute("ObjectivePriorityTarget", false)
	if state.WardsAlive > 0 then
		model:SetAttribute("Invulnerable", true)
		addHighlight(model, "GuardWardShield", Color3.fromRGB(92, 159, 255), 0.86)
	end
end

local function tryUnlockElite(encounter, state)
	if state.EliteUnlocked then
		return
	end
	if state.EliteSupportRegistered < state.EliteSupportExpected or state.EliteSupportAlive > 0 then
		return
	end
	state.EliteUnlocked = true
	state.State = "EliteVulnerable"
	if state.Elite and state.Elite.Parent then
		state.Elite:SetAttribute("EliteShielded", false)
		state.Elite:SetAttribute("Invulnerable", false)
		state.Elite:SetAttribute("SimulationActive", state.CombatEnabled == true)
		state.Elite:SetAttribute("ObjectiveMechanicSuppressed", false)
		markObjectiveTarget(encounter, state.Elite, true)
		local shield = state.Elite:FindFirstChild("EliteSupportShield")
		if shield then
			shield:Destroy()
		end
	end
	workspace:SetAttribute("DungeonEliteShieldSupportsRemaining", 0)
	setMechanicAttributes(encounter, state)
end

local function registerEliteOrSupport(encounter, state, model, enemy)
	if enemy.IsElite == true or model:GetAttribute("IsElite") == true then
		state.Elite = model
		model:SetAttribute("EliteShielded", state.EliteSupportExpected > 0)
		if state.EliteSupportExpected > 0 then
			model:SetAttribute("Invulnerable", true)
			model:SetAttribute("SimulationActive", false)
			model:SetAttribute("ObjectiveMechanicSuppressed", true)
			clearPriorityTarget(model)
			addHighlight(model, "EliteSupportShield", Color3.fromRGB(255, 209, 84), 0.82)
		else
			state.EliteUnlocked = true
			markObjectiveTarget(encounter, model, true)
		end
		tryUnlockElite(encounter, state)
		return
	end
	if state.EliteSupportRegistered >= state.EliteSupportExpected then
		return
	end
	state.EliteSupportRegistered += 1
	state.EliteSupportAlive += 1
	model:SetAttribute("EliteShieldSupport", true)
	markObjectiveTarget(encounter, model, true)
	addHighlight(model, "EliteSupportOutline", Color3.fromRGB(255, 142, 72), 0.93)
	workspace:SetAttribute("DungeonEliteShieldSupportsRemaining", state.EliteSupportAlive)
	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		humanoid.Died:Connect(function()
			if model:GetAttribute("EliteShieldSupportDefeated") == true then
				return
			end
			model:SetAttribute("EliteShieldSupportDefeated", true)
			model:SetAttribute("ObjectiveTargetCompleted", true)
			clearPriorityTarget(model)
			state.EliteSupportAlive = math.max(0, state.EliteSupportAlive - 1)
			workspace:SetAttribute("DungeonEliteShieldSupportsRemaining", state.EliteSupportAlive)
			tryUnlockElite(encounter, state)
		end)
	end
end

local function destroyState(state)
	for ward in pairs(state.Wards or {}) do
		if ward.Parent then
			ward:Destroy()
		end
	end
	for model in pairs(state.Guards or {}) do
		if model.Parent then
			model:SetAttribute("GuardWardProtected", false)
			model:SetAttribute("Invulnerable", false)
			local shield = model:FindFirstChild("GuardWardShield")
			if shield then
				shield:Destroy()
			end
		end
	end
	if state.Elite and state.Elite.Parent then
		state.Elite:SetAttribute("EliteShielded", false)
		state.Elite:SetAttribute("Invulnerable", false)
	end
end

function ObjectiveMechanicService.Start()
	if started then
		return
	end
	started = true
	statesByEncounterId = {}
	workspace:SetAttribute("DungeonObjectiveMechanicsReady", true)
	workspace:SetAttribute("DungeonObjectiveMechanicsPolicy", POLICY)
	workspace:SetAttribute("DungeonObjectiveMechanic", "Idle")
end

function ObjectiveMechanicService.Stop()
	for _, state in pairs(statesByEncounterId) do
		destroyState(state)
	end
	statesByEncounterId = {}
	started = false
	workspace:SetAttribute("DungeonObjectiveMechanicsReady", false)
	workspace:SetAttribute("DungeonObjectiveMechanic", "Stopped")
	workspace:SetAttribute("DungeonGuardWardsRemaining", nil)
	workspace:SetAttribute("DungeonEliteShieldSupportsRemaining", nil)
end

function ObjectiveMechanicService.BeginEncounter(encounter)
	if not started or type(encounter) ~= "table" or type(encounter.Id) ~= "string" then
		return false, "MechanicServiceUnavailable"
	end
	local mechanic = tostring(encounter.Plan.Mechanic or encounter.Definition.GameplayIdentity or "StandardCombat")
	local state = {
		EncounterId = encounter.Id,
		Mechanic = mechanic,
		State = "Prepared",
		CombatEnabled = false,
		Wards = setmetatable({}, { __mode = "k" }),
		Guards = setmetatable({}, { __mode = "k" }),
		WardsAlive = 0,
		Elite = nil,
		EliteSupportExpected = math.max(0, math.floor(tonumber(encounter.Plan.EliteSupportCount) or 0)),
		EliteSupportRegistered = 0,
		EliteSupportAlive = 0,
		EliteUnlocked = false,
		PendingRevealCount = 0,
	}
	statesByEncounterId[encounter.Id] = state
	encounter.Mechanic = mechanic
	if mechanic == "BreakWardsThenGuards" then
		createGuardWards(encounter, state)
	elseif mechanic == "DefeatSupportsThenElite" then
		state.State = state.EliteSupportExpected > 0 and "DefeatEliteSupports" or "EliteVulnerable"
		task.delay(12, function()
			if statesByEncounterId[encounter.Id] == state
				and state.EliteSupportRegistered < state.EliteSupportExpected
			then
				state.EliteSupportExpected = state.EliteSupportRegistered
				tryUnlockElite(encounter, state)
			end
		end)
	elseif mechanic == "MarkedOpeningTarget" then
		state.State = "FindMarkedTarget"
	elseif mechanic == "HiddenPerimeterAmbush" then
		state.State = "AmbushPrepared"
	elseif mechanic == "PriorityRangedTargets" then
		state.State = "EliminatePriorityTargets"
	else
		state.State = "ActiveRule"
	end
	setMechanicAttributes(encounter, state)
	return true, mechanic
end

function ObjectiveMechanicService.RegisterSpawnedEnemy(encounter, model, enemy, waveIndex, sequenceIndex)
	local state = stateFor(encounter)
	if not state or not model or not model.Parent then
		return false
	end
	model:SetAttribute("ObjectiveGameplayIdentity", state.Mechanic)
	model:SetAttribute("ObjectiveMechanicWaveIndex", waveIndex)
	model:SetAttribute("ObjectiveMechanicSpawnSequence", sequenceIndex)
	if state.Mechanic == "MarkedOpeningTarget" then
		if not state.FocusTarget or not state.FocusTarget.Parent then
			state.FocusTarget = model
			model:SetAttribute("ObjectiveFocusTarget", true)
			addHighlight(model, "ObjectiveFocusTargetOutline", Color3.fromRGB(255, 220, 70), 0.91)
			workspace:SetAttribute("DungeonObjectiveFocusTarget", model:GetFullName())
			state.State = "StrikeMarkedTarget"
		else
			model:SetAttribute("ObjectiveSupport", true)
		end
	elseif state.Mechanic == "HiddenPerimeterAmbush" then
		registerAmbushEnemy(encounter, state, model)
	elseif state.Mechanic == "PriorityRangedTargets" then
		markObjectiveTarget(encounter, model, true)
		addHighlight(model, "ObjectivePriorityOutline", Color3.fromRGB(90, 190, 255), 0.93)
	elseif state.Mechanic == "BreakWardsThenGuards" and tostring(enemy.Role) == "Guard" then
		protectGuard(state, model)
	elseif state.Mechanic == "DefeatSupportsThenElite" then
		registerEliteOrSupport(encounter, state, model, enemy)
	elseif state.Mechanic == "EscalatingRewardWaves" then
		model:SetAttribute("RewardBattleWaveTier", waveIndex)
		if waveIndex >= 3 then
			addHighlight(model, "FinalWaveOutline", Color3.fromRGB(255, 103, 91), 0.96)
		end
	end
	setMechanicAttributes(encounter, state)
	return true
end

function ObjectiveMechanicService.SetEncounterActive(encounter, enabled)
	local state = stateFor(encounter)
	if not state then
		return false
	end
	state.CombatEnabled = enabled == true
	for ward in pairs(state.Wards) do
		if ward.Parent then
			ward:SetAttribute("SimulationActive", state.CombatEnabled)
			ward:SetAttribute("Invulnerable", not state.CombatEnabled)
		end
	end
	if not state.CombatEnabled then
		state.State = "Paused"
	elseif state.Mechanic == "BreakWardsThenGuards" and state.WardsAlive > 0 then
		state.State = "BreakGuardWards"
	elseif state.Mechanic == "DefeatSupportsThenElite" and not state.EliteUnlocked then
		state.State = "DefeatEliteSupports"
	else
		state.State = "CombatActive"
	end
	setMechanicAttributes(encounter, state)
	return true
end

function ObjectiveMechanicService.EndEncounter(encounter, reason)
	local state = stateFor(encounter)
	if not state then
		return false
	end
	state.State = tostring(reason or "Ended")
	setMechanicAttributes(encounter, state)
	destroyState(state)
	statesByEncounterId[encounter.Id] = nil
	return true
end

function ObjectiveMechanicService.GetSnapshot(encounter)
	local state = stateFor(encounter)
	if not state then
		return {
			Ready = started,
			Mechanic = "None",
			State = "Idle",
		}
	end
	return {
		Ready = started,
		Mechanic = state.Mechanic,
		State = state.State,
		GuardWardsRemaining = state.WardsAlive,
		EliteSupportsRemaining = state.EliteSupportAlive,
		FocusTarget = state.FocusTarget,
		CombatEnabled = state.CombatEnabled,
	}
end

return ObjectiveMechanicService
