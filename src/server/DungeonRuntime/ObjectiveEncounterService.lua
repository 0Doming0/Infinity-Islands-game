--[[
    Rebuild Part 03 — deterministic encounters.

    FirstStrike:
      1 slime.

    ClearThePath:
      3 slimes simultaneously.

    FirstRewardBattle:
      Wave 1 = 3 slimes.
      Wait until all 3 die.
      Wave 2 = 2 slimes.
      Total = exactly 5 kills.

    SkyAmbush:
      1.05s warning delay.
      Then exactly 4 Common slimes spawn around the island.

    RangedThreat:
      exactly 3 Role="Ranged" / Blue slimes.
      Existing SlimeController handles strafe + projectile behavior.

    BreakTheNests:
      exactly 2 static CombatTarget nests with Humanoids.
      Each death emits NestDestroyed directly.

    SecondRewardBattle:
      Wave 1 = 4 Common/Green.
      Wave 2 = 3 Ranged/Blue.
      Total = exactly 7 objective kills.

    BreakTheGuard:
      2 Guard monsters spawn dormant/invulnerable.
      2 destructible wards must be broken first.
      Last ward releases both Guards.
      Progress counts only Guard deaths.

    HoldTheBeacon:
      one static hold zone.
      staying inside accumulates seconds.
      leaving pauses without resetting progress.
      target = exactly 25 seconds.

    NestCluster:
      reuses the same deterministic Nest contract as BreakTheNests.
      exactly 3 nests.
      each nest has 90 HP.
      progress counts only NestDestroyed.

    EliteHunt:
      exactly 1 Role="Elite" target.
      IsElite=true is explicit in spawn options.
      no support mobs or shield phase.
      progress counts only the Elite death.

    FinalRewardBattle:
      Wave 1 = 3 Common/Green.
      Wave 2 = 3 Ranged/Blue.
      Wave 3 = 2 Guard/Red.
      Total = exactly 8 objective kills.
      no Elite is mixed into the final waves.

    No EncounterCatalog / mechanic service / legacy actor service.
]]

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MonsterSpawner = require(script.Parent.Parent.BlockParkour.MonsterSpawner)
local ObjectiveSignalBridge = require(script.Parent.ObjectiveSignalBridge)

local ObjectiveEncounterService = {}

local started = false
local current
local token = 0

local ENCOUNTERS = {
    FirstStrike = {
        Waves = { 1 },
        HealthMultiplier = 0.75,
        DamageMultiplier = 0.60,
        SpeedMultiplier = 0.90,
    },
    ClearThePath = {
        Waves = { 3 },
        HealthMultiplier = 0.85,
        DamageMultiplier = 0.68,
        SpeedMultiplier = 0.92,
    },
    FirstRewardBattle = {
        Waves = { 3, 2 },
        HealthMultiplier = 0.92,
        DamageMultiplier = 0.76,
        SpeedMultiplier = 0.95,
    },
    SkyAmbush = {
        Waves = { 4 },
        StartDelay = 1.05,
        Role = "Common",
        HealthMultiplier = 0.95,
        DamageMultiplier = 0.80,
        SpeedMultiplier = 0.98,
        SlimeVariant = "Red",
    },
    RangedThreat = {
        Waves = { 3 },
        StartDelay = 0.82,
        IntroState = "RangedWarning",
        Role = "Ranged",
        HealthMultiplier = 0.88,
        DamageMultiplier = 0.72,
        SpeedMultiplier = 0.88,
        SlimeVariant = "Blue",
    },
    BreakTheNests = {
        Mode = "Nests",
        NestCount = 2,
        NestHealth = 70,
    },
    SecondRewardBattle = {
        Waves = { 4, 3 },
        WaveRoles = { "Common", "Ranged" },
        WaveVariants = { "Green", "Blue" },
        HealthMultiplier = 0.96,
        DamageMultiplier = 0.78,
        SpeedMultiplier = 0.95,
    },
    BreakTheGuard = {
        Mode = "GuardWards",
        GuardCount = 2,
        WardCount = 2,
        WardHealth = 55,
        Role = "Guard",
        SlimeVariant = "Green",
        HealthMultiplier = 1.00,
        DamageMultiplier = 0.72,
        SpeedMultiplier = 0.95,
    },
    HoldTheBeacon = {
        Mode = "Beacon",
        BeaconRadius = 14,
        BeaconTargetSeconds = 25,
    },
    NestCluster = {
        Mode = "Nests",
        NestCount = 3,
        NestHealth = 90,
    },
    EliteHunt = {
        Waves = { 1 },
        Role = "Elite",
        IsElite = true,
        SlimeVariant = "Red",
        HealthMultiplier = 1.08,
        DamageMultiplier = 0.82,
        SpeedMultiplier = 0.98,
    },
    FinalRewardBattle = {
        Waves = { 3, 3, 2 },
        WaveRoles = { "Common", "Ranged", "Guard" },
        WaveVariants = { "Green", "Blue", "Red" },
        HealthMultiplier = 1.00,
        DamageMultiplier = 0.82,
        SpeedMultiplier = 0.96,
    },
}

local function now()
    return workspace:GetServerTimeNow()
end

local function sortedMarkers(folder)
    local result = {}
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("BasePart") then
                table.insert(result, child)
            end
        end
    end

    table.sort(result, function(a, b)
        local ai = tonumber(a:GetAttribute("MarkerIndex")) or 0
        local bi = tonumber(b:GetAttribute("MarkerIndex")) or 0
        if ai == bi then
            return a.Name < b.Name
        end
        return ai < bi
    end)
    return result
end

local function activeCount()
    if not current then
        return 0
    end
    return MonsterSpawner.GetObjectiveActiveCount(current.Id)
end

local function update(state)
    workspace:SetAttribute("DungeonEncounterState", state)
    workspace:SetAttribute("DungeonEncounterId", current and current.Id or nil)
    workspace:SetAttribute("DungeonEncounterObjectiveId", current and current.ObjectiveId or nil)
    workspace:SetAttribute("DungeonEncounterIsland", current and current.GlobalIslandIndex or nil)
    workspace:SetAttribute("DungeonEncounterActiveEnemies", activeCount())
    workspace:SetAttribute("DungeonEncounterUpdatedAt", now())
end

local function destroyCurrent(reason)
    if not current then
        return
    end

    MonsterSpawner.DespawnObjectiveMonsters(current.Id)

    if current.BeaconHeartbeat then
        current.BeaconHeartbeat:Disconnect()
        current.BeaconHeartbeat = nil
    end
    if current.Beacon and current.Beacon.Parent then
        current.Beacon:Destroy()
    end

    for _, nest in ipairs(current.Nests or {}) do
        if nest and nest.Parent then
            nest:Destroy()
        end
    end
    for _, ward in ipairs(current.Wards or {}) do
        if ward and ward.Parent then
            ward:Destroy()
        end
    end

    current = nil
    update(reason or "Idle")
end

local function markerFor(markers, fallback, index)
    if #markers > 0 then
        return markers[((index - 1) % #markers) + 1]
    end
    return fallback
end

local function spawnSingle(encounter, config, markers, fallback, waveIndex, indexInWave, globalSequence)
    local marker = markerFor(markers, fallback, globalSequence)
    if not marker or not marker:IsA("BasePart") then
        return nil, "EnemySpawnMarkerMissing"
    end

    local model
    local lastReason

    for attempt = 1, 8 do
        if not started or not current or current ~= encounter or token ~= encounter.Token then
            return nil, "EncounterCancelled"
        end

        model, lastReason = MonsterSpawner.SpawnObjectiveMonster(
            encounter.Context.IslandModel,
            marker,
            {
                EncounterId = encounter.Id,
                ObjectiveId = encounter.ObjectiveId,
                GlobalIslandIndex = encounter.GlobalIslandIndex,
                Role = (config.WaveRoles and config.WaveRoles[waveIndex])
                    or config.Role
                    or "Common",
                SlimeVariant = (config.WaveVariants and config.WaveVariants[waveIndex])
                    or config.SlimeVariant
                    or "Green",
                IsElite = config.IsElite == true,
                HealthMultiplier = config.HealthMultiplier,
                DamageMultiplier = config.DamageMultiplier,
                SpeedMultiplier = config.SpeedMultiplier,
                WaveIndex = waveIndex,
                SpawnSequence = globalSequence,
                Seed = encounter.GlobalIslandIndex * 10000
                    + waveIndex * 1000
                    + indexInWave * 100
                    + attempt,
                ForceHostile = true,
            }
        )

        if model then
            model:SetAttribute("RebuildProgressionTarget", true)
            if globalSequence == 1 then
                model:SetAttribute("ObjectiveFocusTarget", true)
            end
            return model
        end

        workspace:SetAttribute("DungeonEncounterLastSpawnError", tostring(lastReason))
        task.wait(0.20)
    end

    return nil, tostring(lastReason or "ObjectiveMonsterSpawnFailed")
end

local function waitForWaveClear(encounter)
    while started and current == encounter and token == encounter.Token do
        local alive = activeCount()
        workspace:SetAttribute("DungeonEncounterActiveEnemies", alive)
        if alive <= 0 then
            return true
        end
        task.wait(0.15)
    end
    return false
end

local function createNestHealthBar(model, root, humanoid)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "RebuildNestHealthBar"
    billboard.Adornee = root
    billboard.Size = UDim2.fromOffset(116, 30)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.7, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 90
    billboard.Parent = model

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 14)
    title.BackgroundTransparency = 1
    title.Text = "NINHO"
    title.TextColor3 = Color3.fromRGB(238, 230, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11
    title.Parent = billboard

    local background = Instance.new("Frame")
    background.Position = UDim2.fromOffset(5, 18)
    background.Size = UDim2.new(1, -10, 0, 8)
    background.BackgroundColor3 = Color3.fromRGB(27, 20, 35)
    background.BorderSizePixel = 0
    background.ClipsDescendants = true
    background.Parent = billboard
    Instance.new("UICorner", background).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundColor3 = Color3.fromRGB(183, 91, 255)
    fill.BorderSizePixel = 0
    fill.Parent = background
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local function refresh()
        fill.Size = UDim2.fromScale(
            math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1),
            1
        )
    end

    humanoid.HealthChanged:Connect(refresh)
    refresh()
end

local function createNest(encounter, definition, marker, index, maxHealth)
    local model = Instance.new("Model")
    model.Name = string.format("RebuildObjectiveNest_%02d", index)
    model:SetAttribute("ObjectiveActorType", "Nest")
    model:SetAttribute("MonsterRole", "Nest")
    model:SetAttribute("RuntimeMonster", false)
    model:SetAttribute("ObjectiveSpawned", false)
    model:SetAttribute("ObjectiveId", definition.Id)
    model:SetAttribute("GlobalIslandIndex", definition.GlobalIslandIndex)
    model:SetAttribute("RouteRoundIndex", definition.RoundIndex)
    model:SetAttribute("RouteIslandIndex", definition.IslandIndex)
    model:SetAttribute("ObjectiveTargetCompleted", false)
    model:SetAttribute("NoKnockback", true)
    model:SetAttribute("CanBeKnockedBack", false)
    model:SetAttribute("CanBeStunned", false)
    model:SetAttribute("UseCentralAI", false)
    model:SetAttribute("SimulationActive", true)
    model:SetAttribute("ObjectiveEncounterId", encounter.Id)
    model:SetAttribute("RebuildProgressionTarget", true)

    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Shape = Enum.PartType.Ball
    root.Size = Vector3.new(6.0, 3.4, 6.0)
    root.CFrame = marker.CFrame * CFrame.new(0, 1.55, 0)
    root.Anchored = true
    root.CanCollide = true
    root.CanTouch = false
    root.CanQuery = true
    root.Material = Enum.Material.Slate
    root.Color = Color3.fromRGB(80, 49, 91)
    root:SetAttribute("ObjectiveId", definition.Id)
    root:SetAttribute("GlobalIslandIndex", definition.GlobalIslandIndex)
    root.Parent = model

    for podIndex, offset in ipairs({
        Vector3.new(1.8, 1.0, 0.7),
        Vector3.new(-1.5, 1.0, 1.1),
        Vector3.new(0.4, 1.1, -1.7),
    }) do
        local pod = Instance.new("Part")
        pod.Name = string.format("SlimePod_%02d", podIndex)
        pod.Shape = Enum.PartType.Ball
        pod.Size = Vector3.new(1.6, 1.6, 1.6)
        pod.CFrame = root.CFrame * CFrame.new(offset)
        pod.Anchored = true
        pod.CanCollide = false
        pod.CanTouch = false
        pod.CanQuery = false
        pod.Material = Enum.Material.Neon
        pod.Color = podIndex == 2
            and Color3.fromRGB(91, 153, 255)
            or Color3.fromRGB(101, 232, 116)
        pod.Parent = model
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "NestOutline"
    highlight.FillTransparency = 1
    highlight.OutlineColor = Color3.fromRGB(215, 124, 255)
    highlight.OutlineTransparency = 0.08
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = model

    local humanoid = Instance.new("Humanoid")
    humanoid.Name = "Humanoid"
    humanoid.MaxHealth = math.max(1, math.floor(tonumber(maxHealth) or 70))
    humanoid.Health = humanoid.MaxHealth
    humanoid.DisplayName = "Ninho de Slime"
    humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    humanoid.BreakJointsOnDeath = false
    humanoid.Parent = model

    model.PrimaryPart = root
    model.Parent = encounter.Context.IslandModel

    CollectionService:AddTag(model, "CombatTarget")
    CollectionService:AddTag(model, "DungeonObjectiveTarget")
    CollectionService:AddTag(model, "DungeonSlimeNest")

    createNestHealthBar(model, root, humanoid)

    local reported = false
    humanoid.Died:Connect(function()
        if reported then
            return
        end
        reported = true

        model:SetAttribute("ObjectiveTargetCompleted", true)
        model:SetAttribute("SimulationActive", false)
        root.CanCollide = false

        ObjectiveSignalBridge.Report("NestDestroyed", {
            Target = model,
            GlobalIslandIndex = definition.GlobalIslandIndex,
            Amount = 1,
            SourceUserId = model:GetAttribute("LastDamagedByUserId"),
        })

        task.delay(0.65, function()
            if model.Parent then
                model:Destroy()
            end
        end)
    end)

    return model
end

local function createNestsEncounter(encounter, config, definition)
    local markers = sortedMarkers(encounter.Context.EnemySpawns)
    local fallback = encounter.Context.ObjectiveAnchor or encounter.Context.SafeSpawn
    local nestCount = math.max(1, math.floor(tonumber(config.NestCount) or 2))

    workspace:SetAttribute("DungeonEncounterWaveIndex", 0)
    workspace:SetAttribute("DungeonEncounterWaveCount", 0)
    workspace:SetAttribute("DungeonEncounterWaveState", "NestsActive")
    workspace:SetAttribute("DungeonEncounterExpectedKillCount", 0)
    workspace:SetAttribute("DungeonEncounterExpectedNestCount", nestCount)
    workspace:SetAttribute("DungeonEncounterSpawnedCount", 0)

    encounter.Nests = {}

    for index = 1, nestCount do
        local marker = markerFor(markers, fallback, index)
        if not marker or not marker:IsA("BasePart") then
            workspace:SetAttribute("DungeonEncounterLastSpawnError", "NestMarkerMissing")
            update("SpawnFailed")
            return false, "NestMarkerMissing"
        end

        local nest = createNest(
            encounter,
            definition,
            marker,
            index,
            config.NestHealth
        )

        table.insert(encounter.Nests, nest)
        workspace:SetAttribute("DungeonEncounterSpawnedCount", index)

        if index == 1 and nest.PrimaryPart then
            workspace:SetAttribute("DungeonObjectiveWaypointPosition", nest.PrimaryPart.Position)
            workspace:SetAttribute("DungeonObjectiveWaypointTarget", nest:GetFullName())
            workspace:SetAttribute(
                "DungeonObjectiveWaypointSerial",
                (tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
            )
        end
    end

    update("NestsActive")
    return true
end

local function createWard(encounter, definition, marker, index, maxHealth, onDestroyed)
    local model = Instance.new("Model")
    model.Name = string.format("RebuildGuardWard_%02d", index)
    model:SetAttribute("ObjectiveActorType", "GuardWard")
    model:SetAttribute("MonsterRole", "GuardWard")
    model:SetAttribute("RuntimeMonster", false)
    model:SetAttribute("ObjectiveSpawned", false)
    model:SetAttribute("ObjectiveId", definition.Id)
    model:SetAttribute("GlobalIslandIndex", definition.GlobalIslandIndex)
    model:SetAttribute("RouteRoundIndex", definition.RoundIndex)
    model:SetAttribute("RouteIslandIndex", definition.IslandIndex)
    model:SetAttribute("ObjectiveTargetCompleted", false)
    model:SetAttribute("NoKnockback", true)
    model:SetAttribute("CanBeKnockedBack", false)
    model:SetAttribute("CanBeStunned", false)
    model:SetAttribute("UseCentralAI", false)
    model:SetAttribute("SimulationActive", true)
    model:SetAttribute("ObjectiveEncounterId", encounter.Id)

    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Shape = Enum.PartType.Ball
    root.Size = Vector3.new(3.2, 5.4, 3.2)
    root.CFrame = marker.CFrame * CFrame.new(0, 2.5, 0)
    root.Anchored = true
    root.CanCollide = true
    root.CanTouch = false
    root.CanQuery = true
    root.Material = Enum.Material.Neon
    root.Color = Color3.fromRGB(91, 169, 255)
    root:SetAttribute("ObjectiveId", definition.Id)
    root:SetAttribute("GlobalIslandIndex", definition.GlobalIslandIndex)
    root.Parent = model

    local ring = Instance.new("Part")
    ring.Name = "WardRing"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.35, 5.4, 5.4)
    ring.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(90))
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanTouch = false
    ring.CanQuery = false
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(159, 218, 255)
    ring.Transparency = 0.18
    ring.Parent = model

    local light = Instance.new("PointLight")
    light.Name = "WardLight"
    light.Color = root.Color
    light.Brightness = 2.1
    light.Range = 12
    light.Shadows = false
    light.Parent = root

    local humanoid = Instance.new("Humanoid")
    humanoid.Name = "Humanoid"
    humanoid.MaxHealth = math.max(1, math.floor(tonumber(maxHealth) or 55))
    humanoid.Health = humanoid.MaxHealth
    humanoid.DisplayName = "Cristal de Proteção"
    humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    humanoid.BreakJointsOnDeath = false
    humanoid.Parent = model

    model.PrimaryPart = root
    model.Parent = encounter.Context.IslandModel

    CollectionService:AddTag(model, "CombatTarget")
    CollectionService:AddTag(model, "DungeonObjectiveTarget")
    CollectionService:AddTag(model, "DungeonGuardWard")

    createNestHealthBar(model, root, humanoid)

    local reported = false
    humanoid.Died:Connect(function()
        if reported then
            return
        end
        reported = true

        model:SetAttribute("ObjectiveTargetCompleted", true)
        model:SetAttribute("SimulationActive", false)
        root.CanCollide = false

        if type(onDestroyed) == "function" then
            onDestroyed(model)
        end

        task.delay(0.55, function()
            if model.Parent then
                model:Destroy()
            end
        end)
    end)

    return model
end

local function unprotectGuards(encounter)
    if not encounter or encounter.GuardsReleased == true then
        return
    end
    encounter.GuardsReleased = true

    workspace:SetAttribute("DungeonGuardWardsRemaining", 0)
    workspace:SetAttribute("DungeonGuardPhase", "DefeatGuards")

    for _, guard in ipairs(encounter.Guards or {}) do
        if guard and guard.Parent then
            guard:SetAttribute("GuardWardProtected", false)
            guard:SetAttribute("Invulnerable", false)
            guard:SetAttribute("SimulationActive", true)
            guard:SetAttribute("ObjectivePriorityTarget", true)

            local shield = guard:FindFirstChild("RebuildGuardShield")
            if shield then
                shield:Destroy()
            end
        end
    end
end

local function protectGuard(guard)
    guard:SetAttribute("GuardWardProtected", true)
    guard:SetAttribute("Invulnerable", true)
    guard:SetAttribute("SimulationActive", false)

    local highlight = Instance.new("Highlight")
    highlight.Name = "RebuildGuardShield"
    highlight.FillColor = Color3.fromRGB(76, 170, 255)
    highlight.FillTransparency = 0.68
    highlight.OutlineColor = Color3.fromRGB(172, 226, 255)
    highlight.OutlineTransparency = 0.05
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = guard
end

local function createGuardEncounter(encounter, config, definition)
    local markers = sortedMarkers(encounter.Context.EnemySpawns)
    local fallback = encounter.Context.ObjectiveAnchor or encounter.Context.SafeSpawn

    local wardCount = math.max(1, math.floor(tonumber(config.WardCount) or 2))
    local guardCount = math.max(1, math.floor(tonumber(config.GuardCount) or 2))

    encounter.Wards = {}
    encounter.Guards = {}
    encounter.WardsDestroyed = 0
    encounter.GuardsReleased = false

    workspace:SetAttribute("DungeonEncounterWaveIndex", 0)
    workspace:SetAttribute("DungeonEncounterWaveCount", 0)
    workspace:SetAttribute("DungeonEncounterWaveState", "GuardWards")
    workspace:SetAttribute("DungeonEncounterExpectedKillCount", guardCount)
    workspace:SetAttribute("DungeonEncounterExpectedWardCount", wardCount)
    workspace:SetAttribute("DungeonEncounterSpawnedCount", 0)
    workspace:SetAttribute("DungeonGuardWardsRemaining", wardCount)
    workspace:SetAttribute("DungeonGuardPhase", "BreakWards")

    -- Spawn Guards first, but keep them invulnerable and dormant.
    for index = 1, guardCount do
        local guard, reason = spawnSingle(
            encounter,
            config,
            markers,
            fallback,
            1,
            index,
            index
        )
        if not guard then
            workspace:SetAttribute("DungeonEncounterLastSpawnError", tostring(reason))
            update("SpawnFailed")
            return false, reason
        end

        protectGuard(guard)
        table.insert(encounter.Guards, guard)
        workspace:SetAttribute("DungeonEncounterSpawnedCount", index)
    end

    -- Place wards after Guard markers when possible so they do not overlap.
    for index = 1, wardCount do
        local marker = markerFor(markers, fallback, guardCount + index)
        if not marker or not marker:IsA("BasePart") then
            workspace:SetAttribute("DungeonEncounterLastSpawnError", "GuardWardMarkerMissing")
            update("SpawnFailed")
            return false, "GuardWardMarkerMissing"
        end

        local ward = createWard(
            encounter,
            definition,
            marker,
            index,
            config.WardHealth,
            function()
                if current ~= encounter then
                    return
                end

                encounter.WardsDestroyed += 1
                local remaining = math.max(0, wardCount - encounter.WardsDestroyed)
                workspace:SetAttribute("DungeonGuardWardsRemaining", remaining)

                if remaining <= 0 then
                    unprotectGuards(encounter)
                end
            end
        )

        table.insert(encounter.Wards, ward)

        if index == 1 and ward.PrimaryPart then
            workspace:SetAttribute("DungeonObjectiveWaypointPosition", ward.PrimaryPart.Position)
            workspace:SetAttribute("DungeonObjectiveWaypointTarget", ward:GetFullName())
            workspace:SetAttribute(
                "DungeonObjectiveWaypointSerial",
                (tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
            )
        end
    end

    update("GuardWards")
    return true
end

local function livingPlayerRoot(player)
    if not player or player.Parent ~= Players then
        return nil
    end
    if player:GetAttribute("DungeonEliminated") == true
        or player:GetAttribute("IsDowned") == true
    then
        return nil
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
        return nil
    end
    return root
end

local function playerInsideBeacon(center, radius)
    for _, player in ipairs(Players:GetPlayers()) do
        local root = livingPlayerRoot(player)
        if root then
            local offset = root.Position - center
            local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
            if horizontal <= radius and math.abs(offset.Y) <= 10 then
                return player
            end
        end
    end
    return nil
end

local function createBeaconEncounter(encounter, config, definition)
    local marker = encounter.Context.ObjectiveAnchor or encounter.Context.SafeSpawn
    if not marker or not marker:IsA("BasePart") then
        workspace:SetAttribute("DungeonEncounterLastSpawnError", "BeaconMarkerMissing")
        update("SpawnFailed")
        return false, "BeaconMarkerMissing"
    end

    local radius = math.max(6, tonumber(config.BeaconRadius) or 14)
    local targetSeconds = math.max(1, math.floor(tonumber(config.BeaconTargetSeconds) or 25))

    local model = Instance.new("Model")
    model.Name = "RebuildHoldBeacon"
    model:SetAttribute("ObjectiveActorType", "Beacon")
    model:SetAttribute("ObjectiveId", definition.Id)
    model:SetAttribute("GlobalIslandIndex", definition.GlobalIslandIndex)
    model:SetAttribute("RouteRoundIndex", definition.RoundIndex)
    model:SetAttribute("RouteIslandIndex", definition.IslandIndex)
    model:SetAttribute("ObjectiveTargetCompleted", false)
    model:SetAttribute("BeaconRadius", radius)
    model:SetAttribute("BeaconTargetSeconds", targetSeconds)
    model:SetAttribute("BeaconHeldSeconds", 0)
    model:SetAttribute("BeaconOccupantCount", 0)
    model:SetAttribute("BeaconActive", false)
    model:SetAttribute("SimulationActive", true)
    model:SetAttribute("ObjectiveEncounterId", encounter.Id)
    model.Parent = encounter.Context.IslandModel

    local base = Instance.new("Part")
    base.Name = "BeaconBase"
    base.Shape = Enum.PartType.Cylinder
    base.Size = Vector3.new(1.2, 5.5, 5.5)
    base.CFrame = marker.CFrame * CFrame.new(0, 0.65, 0) * CFrame.Angles(0, 0, math.rad(90))
    base.Anchored = true
    base.CanCollide = true
    base.CanTouch = false
    base.CanQuery = true
    base.Material = Enum.Material.Metal
    base.Color = Color3.fromRGB(77, 67, 112)
    base.Parent = model

    local core = Instance.new("Part")
    core.Name = "BeaconCore"
    core.Shape = Enum.PartType.Ball
    core.Size = Vector3.new(2.3, 2.3, 2.3)
    core.CFrame = marker.CFrame * CFrame.new(0, 3.2, 0)
    core.Anchored = true
    core.CanCollide = false
    core.CanTouch = false
    core.CanQuery = false
    core.Material = Enum.Material.Neon
    core.Color = Color3.fromRGB(143, 103, 255)
    core.Parent = model

    local light = Instance.new("PointLight")
    light.Name = "BeaconLight"
    light.Color = core.Color
    light.Brightness = 2.3
    light.Range = radius + 7
    light.Shadows = false
    light.Parent = core

    local zone = Instance.new("Part")
    zone.Name = "BeaconHoldZone"
    zone.Shape = Enum.PartType.Cylinder
    zone.Size = Vector3.new(0.18, radius * 2, radius * 2)
    zone.CFrame = marker.CFrame * CFrame.new(0, 0.13, 0) * CFrame.Angles(0, 0, math.rad(90))
    zone.Anchored = true
    zone.CanCollide = false
    zone.CanTouch = false
    zone.CanQuery = false
    zone.Material = Enum.Material.Neon
    zone.Color = Color3.fromRGB(143, 103, 255)
    zone.Transparency = 0.72
    zone.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BeaconProgress"
    billboard.Adornee = core
    billboard.Size = UDim2.fromOffset(150, 40)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 100
    billboard.Parent = model

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundColor3 = Color3.fromRGB(20, 18, 34)
    label.BackgroundTransparency = 0.15
    label.BorderSizePixel = 0
    label.Text = string.format("FAROL 0 / %d", targetSeconds)
    label.TextColor3 = Color3.fromRGB(222, 205, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.Parent = billboard
    Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)

    CollectionService:AddTag(model, "DungeonObjectiveTarget")
    CollectionService:AddTag(model, "DungeonHoldBeacon")

    encounter.Beacon = model

    workspace:SetAttribute("DungeonEncounterWaveIndex", 0)
    workspace:SetAttribute("DungeonEncounterWaveCount", 0)
    workspace:SetAttribute("DungeonEncounterWaveState", "BeaconActive")
    workspace:SetAttribute("DungeonEncounterExpectedKillCount", 0)
    workspace:SetAttribute("DungeonEncounterBeaconRadius", radius)
    workspace:SetAttribute("DungeonEncounterBeaconTargetSeconds", targetSeconds)
    workspace:SetAttribute("DungeonBeaconOccupantCount", 0)
    workspace:SetAttribute("DungeonBeaconHeldSeconds", 0)

    workspace:SetAttribute("DungeonObjectiveWaypointPosition", core.Position)
    workspace:SetAttribute("DungeonObjectiveWaypointTarget", model:GetFullName())
    workspace:SetAttribute(
        "DungeonObjectiveWaypointSerial",
        (tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
    )

    local fractionalSeconds = 0
    local lastTick = workspace:GetServerTimeNow()

    encounter.BeaconHeartbeat = RunService.Heartbeat:Connect(function()
        if current ~= encounter
            or not model.Parent
            or model:GetAttribute("SimulationActive") == false
            or model:GetAttribute("ObjectiveTargetCompleted") == true
        then
            return
        end

        local currentTime = workspace:GetServerTimeNow()
        local delta = math.clamp(currentTime - lastTick, 0, 0.25)
        lastTick = currentTime

        local occupant = playerInsideBeacon(marker.Position, radius)
        local occupied = occupant ~= nil

        model:SetAttribute("BeaconActive", occupied)
        model:SetAttribute("BeaconOccupantCount", occupied and 1 or 0)
        workspace:SetAttribute("DungeonBeaconOccupantCount", occupied and 1 or 0)

        if not occupied then
            return
        end

        fractionalSeconds += delta
        local wholeSeconds = math.floor(fractionalSeconds)
        if wholeSeconds <= 0 then
            return
        end
        fractionalSeconds -= wholeSeconds

        local accepted = ObjectiveSignalBridge.Report("BeaconHoldSeconds", {
            Target = model,
            GlobalIslandIndex = definition.GlobalIslandIndex,
            SourceUserId = occupant.UserId,
            Amount = wholeSeconds,
        })

        if accepted then
            local held = math.max(
                0,
                math.floor(tonumber(model:GetAttribute("BeaconHeldSeconds")) or 0)
            )
            workspace:SetAttribute("DungeonBeaconHeldSeconds", held)
            label.Text = string.format("FAROL %d / %d", held, targetSeconds)

            if held >= targetSeconds then
                model:SetAttribute("ObjectiveTargetCompleted", true)
                model:SetAttribute("BeaconActive", false)
                workspace:SetAttribute("DungeonBeaconOccupantCount", 0)
            end
        end
    end)

    update("BeaconActive")
    return true
end

local function runEncounter(encounter, config)
    task.spawn(function()
        local markers = sortedMarkers(encounter.Context.EnemySpawns)
        local fallback = encounter.Context.ObjectiveAnchor or encounter.Context.SafeSpawn
        local globalSequence = 0
        local totalExpected = 0

        for _, count in ipairs(config.Waves) do
            totalExpected += count
        end

        workspace:SetAttribute("DungeonEncounterWaveCount", #config.Waves)
        workspace:SetAttribute("DungeonEncounterExpectedKillCount", totalExpected)
        workspace:SetAttribute("DungeonEncounterSpawnedCount", 0)

        local startDelay = math.max(0, tonumber(config.StartDelay) or 0)
        if startDelay > 0 then
            local introState = tostring(config.IntroState or "AmbushWarning")
            workspace:SetAttribute("DungeonEncounterWaveState", introState)
            update(introState)
            task.wait(startDelay)
        end

        for waveIndex, waveCount in ipairs(config.Waves) do
            if not started or current ~= encounter or token ~= encounter.Token then
                return
            end

            workspace:SetAttribute("DungeonEncounterWaveIndex", waveIndex)
            workspace:SetAttribute("DungeonEncounterWaveState", "Spawning")
            update("WaveSpawning")

            for indexInWave = 1, waveCount do
                globalSequence += 1
                local model, reason = spawnSingle(
                    encounter,
                    config,
                    markers,
                    fallback,
                    waveIndex,
                    indexInWave,
                    globalSequence
                )

                if not model then
                    workspace:SetAttribute("DungeonEncounterSpawnFailureIndex", globalSequence)
                    workspace:SetAttribute("DungeonEncounterLastSpawnError", tostring(reason))
                    update("SpawnFailed")
                    return
                end

                table.insert(encounter.Spawned, model)
                encounter.SpawnedCount += 1
                workspace:SetAttribute("DungeonEncounterSpawnedCount", encounter.SpawnedCount)

                if globalSequence == 1 then
                    local root = model:FindFirstChild("HumanoidRootPart", true) or model.PrimaryPart
                    if root and root:IsA("BasePart") then
                        workspace:SetAttribute("DungeonObjectiveWaypointPosition", root.Position)
                        workspace:SetAttribute("DungeonObjectiveWaypointTarget", model:GetFullName())
                        workspace:SetAttribute(
                            "DungeonObjectiveWaypointSerial",
                            (tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
                        )
                    end
                end

                task.wait(0.10)
            end

            workspace:SetAttribute("DungeonEncounterWaveState", "Active")
            update("Active")

            if waveIndex < #config.Waves then
                if not waitForWaveClear(encounter) then
                    return
                end

                workspace:SetAttribute("DungeonEncounterWaveState", "Cleared")
                update("WaveCleared")

                -- Pequena pausa fixa. Não há pacing service.
                task.wait(0.65)
            end
        end

        if started and current == encounter and token == encounter.Token then
            workspace:SetAttribute("DungeonEncounterAllWavesSpawned", true)
            workspace:SetAttribute("DungeonEncounterWaveState", "FinalWaveActive")
            update("AllWavesSpawned")
        end
    end)
end

function ObjectiveEncounterService.Start()
    if started then
        return
    end

    started = true
    token += 1
    workspace:SetAttribute("DungeonEncounterServiceReady", true)
    workspace:SetAttribute("DungeonEncounterPolicy", "RebuildDeterministicV13")
    workspace:SetAttribute("DungeonEncounterWaveIndex", 0)
    workspace:SetAttribute("DungeonEncounterWaveCount", 0)
    workspace:SetAttribute("DungeonEncounterWaveState", "Idle")
    update("Idle")
end

function ObjectiveEncounterService.Stop()
    token += 1
    destroyCurrent("ServiceStopped")
    started = false
    workspace:SetAttribute("DungeonEncounterServiceReady", false)
end

function ObjectiveEncounterService.BeginObjective(definition, context)
    if not started then
        return false, "EncounterServiceNotStarted"
    end
    if type(definition) ~= "table" or type(context) ~= "table" or not context.IslandModel then
        return false, "InvalidEncounterContext"
    end

    local config = ENCOUNTERS[definition.Id]
    if not config then
        return false, "ObjectiveNotImplemented"
    end

    -- Idempotence is mandatory because compatibility/runtime layers may ask
    -- to begin the same objective more than once.
    if current
        and current.ObjectiveId == definition.Id
        and current.GlobalIslandIndex == definition.GlobalIslandIndex
        and current.Context == context
    then
        workspace:SetAttribute("DungeonEncounterDuplicateStartPrevented", true)
        return true, current.Id
    end

    destroyCurrent("ReplacingEncounter")

    token += 1
    local encounterToken = token
    local id = "Rebuild_" .. definition.Id .. "_" .. HttpService:GenerateGUID(false)

    local encounter = {
        Id = id,
        ObjectiveId = definition.Id,
        GlobalIslandIndex = definition.GlobalIslandIndex,
        Token = encounterToken,
        Context = context,
        Spawned = {},
        SpawnedCount = 0,
    }

    current = encounter

    workspace:SetAttribute("DungeonEncounterAllWavesSpawned", false)
    workspace:SetAttribute("DungeonEncounterWaveIndex", 0)
    workspace:SetAttribute("DungeonEncounterWaveCount", #(config.Waves or {}))
    workspace:SetAttribute("DungeonEncounterWaveState", "Preparing")
    update("Preparing")

    if config.Mode == "Nests" then
        local success, reason = createNestsEncounter(encounter, config, definition)
        if not success then
            return false, reason
        end
    elseif config.Mode == "GuardWards" then
        local success, reason = createGuardEncounter(encounter, config, definition)
        if not success then
            return false, reason
        end
    elseif config.Mode == "Beacon" then
        local success, reason = createBeaconEncounter(encounter, config, definition)
        if not success then
            return false, reason
        end
    else
        runEncounter(encounter, config)
    end

    return true, id
end

function ObjectiveEncounterService.CompleteObjective(objectiveId)
    if not current then
        update("Completed")
        return true
    end
    if objectiveId and current.ObjectiveId ~= objectiveId then
        return false, "EncounterObjectiveMismatch"
    end

    local finished = current
    local id = finished.Id

    if finished.BeaconHeartbeat then
        finished.BeaconHeartbeat:Disconnect()
        finished.BeaconHeartbeat = nil
    end

    current = nil
    workspace:SetAttribute("DungeonEncounterWaveState", "Completed")
    update("Completed")

    task.delay(1.0, function()
        MonsterSpawner.DespawnObjectiveMonsters(id)
        for _, nest in ipairs(finished.Nests or {}) do
            if nest and nest.Parent then
                nest:Destroy()
            end
        end
        for _, ward in ipairs(finished.Wards or {}) do
            if ward and ward.Parent then
                ward:Destroy()
            end
        end
        if finished.Beacon and finished.Beacon.Parent then
            finished.Beacon:Destroy()
        end
    end)

    return true
end

function ObjectiveEncounterService.Recover(definition, context, snapshot)
    if not started or not definition then
        return false
    end

    local target = math.max(
        1,
        math.floor(tonumber(snapshot and snapshot.Target or definition.Target) or 1)
    )
    local progress = math.max(
        0,
        math.floor(tonumber(snapshot and snapshot.Progress) or 0)
    )

    if progress >= target then
        return true
    end

    -- Nesta fase inicial recovery reinicia apenas o encontro físico.
    -- O contador autoritativo continua no DungeonProgressionService.
    workspace:SetAttribute("DungeonEncounterRecoveryRemaining", target - progress)
    return ObjectiveEncounterService.BeginObjective(definition, context)
end

function ObjectiveEncounterService.SetCombatEnabled(enabled)
    if not current then
        return false
    end

    MonsterSpawner.SetObjectiveMonstersActive(current.Id, enabled == true)
    update(enabled and "Active" or "Paused")
    return true
end

function ObjectiveEncounterService.GetSnapshot()
    return {
        Started = started,
        State = workspace:GetAttribute("DungeonEncounterState"),
        EncounterId = current and current.Id or nil,
        ObjectiveId = current and current.ObjectiveId or nil,
        GlobalIslandIndex = current and current.GlobalIslandIndex or nil,
        ActiveEnemies = activeCount(),
        WaveIndex = workspace:GetAttribute("DungeonEncounterWaveIndex"),
        WaveCount = workspace:GetAttribute("DungeonEncounterWaveCount"),
    }
end

return ObjectiveEncounterService
