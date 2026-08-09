-- DungeonArtHUDController.client.luau
-- Authored HUD Controller V7
--
-- REGRA PRINCIPAL:
-- Este script NAO desenha HUD por codigo.
-- Nao cria ScreenGui/Frame/TextLabel/ImageLabel/UICorner/UIStroke/UIScale.
-- Ele apenas:
--   1) encontra os componentes criados manualmente no Studio;
--   2) atualiza propriedades/textos;
--   3) anima propriedades existentes;
--   4) clona templates visuais que o designer criou manualmente.
--
-- Tags obrigatorias nos quatro blocos principais:
--   ObjectivePanel -> DungeonHUD_Objective
--   PlayerStatus   -> DungeonHUD_PlayerStatus
--   MiniMap        -> DungeonHUD_Minimap
--   MissionsPanel -> DungeonHUD_Missions

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TAGS = {
	Objective = "DungeonHUD_Objective",
	PlayerStatus = "DungeonHUD_PlayerStatus",
	Minimap = "DungeonHUD_Minimap",
	Missions = "DungeonHUD_Missions",
	ItemHotbar = "DungeonHUD_ItemHotbar",       -- opcional/futuro
	BasicControls = "DungeonHUD_BasicControls", -- opcional/futuro
}

local OBJECTIVE_DESCRIPTION_MAX = 43
local MINIMAP_RANGE = 420
local MINIMAP_UPDATE_INTERVAL = 0.10
local ROUND_LENGTHS = { 3, 4, 5 }

local function normalize(value)
	return string.lower(string.gsub(tostring(value or ""), "[^%w]", ""))
end

local function isText(object)
	return object
		and (
			object:IsA("TextLabel")
			or object:IsA("TextButton")
			or object:IsA("TextBox")
		)
end

local function isGui(object)
	return object and object:IsA("GuiObject")
end

local function descendantsIncludingChildren(root)
	local result = {}
	for _, child in ipairs(root:GetChildren()) do
		table.insert(result, child)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Parent ~= root then
			table.insert(result, descendant)
		end
	end
	return result
end

local SAFE_SUFFIXES = {
	"frame",
	"label",
	"text",
	"image",
	"button",
	"panel",
	"container",
	"holder",
	"bar",
	"icon",
	"background",
}

local function semanticName(value)
	local name = normalize(value)
	local changed = true
	while changed do
		changed = false
		for _, suffix in ipairs(SAFE_SUFFIXES) do
			if #name > #suffix + 3 and string.sub(name, -#suffix) == suffix then
				name = string.sub(name, 1, #name - #suffix)
				changed = true
				break
			end
		end
	end
	return name
end

local function findAuthored(root, aliases, predicate)
	if not root then
		return nil
	end

	local pool = descendantsIncludingChildren(root)

	-- 1) match exato normalizado.
	for _, alias in ipairs(aliases) do
		local wanted = normalize(alias)
		for _, object in ipairs(pool) do
			if (not predicate or predicate(object)) and normalize(object.Name) == wanted then
				return object
			end
		end
	end

	-- 2) equivalencia segura removendo apenas sufixos comuns de GUI.
	for _, alias in ipairs(aliases) do
		local wanted = semanticName(alias)
		if #wanted >= 4 then
			for _, object in ipairs(pool) do
				if (not predicate or predicate(object))
					and semanticName(object.Name) == wanted
				then
					return object
				end
			end
		end
	end

	return nil
end

local missingWarnings = {}

local function warnMissing(path, aliases)
	if missingWarnings[path] then
		return
	end
	missingWarnings[path] = true
	warn(string.format(
		"[AuthoredHUD] Elemento manual ausente: %s | esperado: %s",
		path,
		table.concat(aliases, " / ")
	))
end

local function authored(root, path, aliases, predicate)
	local object = findAuthored(root, aliases, predicate)
	if not object then
		warnMissing(path, aliases)
	end
	return object
end

local function setText(object, value)
	if isText(object) then
		object.Text = tostring(value or "")
	end
end

local function truncateUtf8(value, maximum)
	local text = tostring(value or "")
	local ok, length = pcall(utf8.len, text)
	if not ok or not length or length <= maximum then
		return text
	end

	local byteIndex = utf8.offset(text, maximum + 1)
	return byteIndex and string.sub(text, 1, byteIndex - 1) or text
end

local function tween(object, duration, properties)
	if not object or not object.Parent then
		return
	end
	TweenService:Create(
		object,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		properties
	):Play()
end

local function taggedInPlayerGui(tagName)
	for _, object in ipairs(CollectionService:GetTagged(tagName)) do
		if object:IsA("GuiObject") and object:IsDescendantOf(playerGui) then
			return object
		end
	end
	return nil
end

local function waitForDungeonHUD(timeout)
	local hud = playerGui:FindFirstChild("DungeonHUD")
	if hud and hud:IsA("ScreenGui") then
		return hud
	end

	local deadline = os.clock() + (timeout or 10)
	while os.clock() < deadline do
		task.wait(0.05)
		hud = playerGui:FindFirstChild("DungeonHUD")
		if hud and hud:IsA("ScreenGui") then
			return hud
		end
	end

	return nil
end

-- Primary resolution strategy:
-- 1) exact DungeonHUD authored by the designer;
-- 2) exact known child names inside that ScreenGui;
-- 3) CollectionService tags only as a fallback.
--
-- This prevents false positives from SettingsUI while avoiding a hard
-- dependency on tags being copied into PlayerGui.
local hud = waitForDungeonHUD(10)

local function directOrTagged(parent, exactName, tagName)
	if parent then
		local direct = parent:FindFirstChild(exactName)
		if direct and direct:IsA("GuiObject") then
			return direct
		end
	end
	return taggedInPlayerGui(tagName)
end

local objectivePanel = directOrTagged(hud, "ObjectivePanel", TAGS.Objective)
local playerStatus = directOrTagged(hud, "PlayerStatus", TAGS.PlayerStatus)
local miniMap = directOrTagged(hud, "MiniMap", TAGS.Minimap)
local missionsPanel = directOrTagged(hud, "MissionsPanel", TAGS.Missions)

if not hud then
	warn("[AuthoredHUD] DungeonHUD nao foi encontrado em PlayerGui.")
end

if not objectivePanel then
	warn("[AuthoredHUD] ObjectivePanel nao encontrado dentro de DungeonHUD.")
end
if not playerStatus then
	warn("[AuthoredHUD] PlayerStatus nao encontrado dentro de DungeonHUD.")
end
if not miniMap then
	warn("[AuthoredHUD] MiniMap nao encontrado dentro de DungeonHUD.")
end
if not missionsPanel then
	warn("[AuthoredHUD] MissionsPanel nao encontrado dentro de DungeonHUD.")
end

if not objectivePanel and not playerStatus and not miniMap and not missionsPanel then
	player:SetAttribute("DungeonArtHUDControllerReady", false)
	player:SetAttribute("DungeonArtHUDFailure", "AuthoredDungeonHUDNotFound")
	warn("[AuthoredHUD] Nenhum bloco manual foi encontrado. Controller encerrado.")
	return
end

if not hud then
	local function ownerScreenGui(object)
		local current = object
		while current and current ~= playerGui do
			if current:IsA("ScreenGui") then
				return current
			end
			current = current.Parent
		end
		return nil
	end

	hud = ownerScreenGui(objectivePanel)
		or ownerScreenGui(playerStatus)
		or ownerScreenGui(miniMap)
		or ownerScreenGui(missionsPanel)
end

if hud then
	hud.Enabled = true
	hud.ResetOnSpawn = false
	hud:SetAttribute("ResponsiveGenericOptOut", true)
	hud:SetAttribute("ControllerVersion", "AuthoredHUDStrictV8")
	hud:SetAttribute("ControllerCreatesVisuals", false)
end

-- Compatibility flag for legacy gameplay controllers such as SprintController.
-- It prevents them from showing their old fallback stamina HUD.
player:SetAttribute("DungeonUnifiedHUDReady", true)
---------------------------------------------------------------------
-- Objective
---------------------------------------------------------------------

local objectiveTitle
local objectiveDescription
local objectiveCounter
local objectiveProgressBackground
local objectiveProgressFill
local objectiveCompletedIcon
local objectiveFullX
local currentObjective
local lastObjectiveProgress

if objectivePanel then
	objectiveTitle = authored(
		objectivePanel,
		"Objective.Title",
		{ "Title", "ObjectiveTitle", "Titulo" },
		isText
	)

	objectiveDescription = authored(
		objectivePanel,
		"Objective.Description",
		{ "Description", "ObjectiveDescription", "Descricao", "Detail" },
		isText
	)

	objectiveCounter = authored(
		objectivePanel,
		"Objective.Counter",
		{ "Counter", "ProgressText", "ObjectiveCounter", "Count" },
		isText
	)

	objectiveProgressBackground = authored(
		objectivePanel,
		"Objective.ProgressBackground",
		{ "ProgressBackground", "BarBackground", "Track" },
		isGui
	)

	objectiveProgressFill = authored(
		objectivePanel,
		"Objective.ProgressFill",
		{ "ProgressFill", "BarFill", "Fill" },
		isGui
	)

	objectiveCompletedIcon = authored(
		objectivePanel,
		"Objective.CompletedIcon",
		{ "CompletedIcon", "CompleteIcon", "CheckIcon", "Completed" },
		isGui
	)

	setText(objectiveTitle, "Objetivo")

	if objectiveProgressFill then
		local x = objectiveProgressFill.Size.X
		if objectiveProgressBackground then
			if objectiveProgressFill.Parent == objectiveProgressBackground then
				objectiveFullX = UDim.new(1, 0)
			elseif objectiveProgressFill.Parent == objectiveProgressBackground.Parent then
				objectiveFullX = objectiveProgressBackground.Size.X
			end
		end
		objectiveFullX = objectiveFullX or x
	end
end

local function readObjective()
	return {
		State = tostring(workspace:GetAttribute("DungeonObjectiveState") or "Inactive"),
		Id = workspace:GetAttribute("DungeonObjectiveId"),
		Title = workspace:GetAttribute("DungeonObjectiveTitle"),
		Description = workspace:GetAttribute("DungeonObjectiveDescription"),
		RoundIndex = workspace:GetAttribute("DungeonObjectiveRoundIndex"),
		IslandIndex = workspace:GetAttribute("DungeonObjectiveIslandIndex"),
		GlobalIslandIndex = workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex"),
		Progress = workspace:GetAttribute("DungeonObjectiveProgress") or 0,
		Target = workspace:GetAttribute("DungeonObjectiveTarget") or 1,
		WaypointEscalated = workspace:GetAttribute("DungeonObjectiveWaypointEscalated") == true,
		ExitLocked = workspace:GetAttribute("DungeonObjectiveExitLocked") == true,
	}
end

local function setFillRatio(fill, fullX, ratio, duration)
	if not fill or not fullX then
		return
	end

	ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
	local y = fill.Size.Y

	tween(fill, duration or 0.20, {
		Size = UDim2.new(
			fullX.Scale * ratio,
			math.floor(fullX.Offset * ratio + 0.5),
			y.Scale,
			y.Offset
		),
	})
end

local function renderObjective(snapshot)
	snapshot = snapshot or readObjective()
	currentObjective = snapshot

	if not objectivePanel then
		return
	end

	local state = tostring(snapshot.State or "Inactive")
	local active = state == "Active" or state == "Completed"
	objectivePanel.Visible = active

	if not active then
		return
	end

	local progress = math.max(0, math.floor(tonumber(snapshot.Progress) or 0))
	local target = math.max(1, math.floor(tonumber(snapshot.Target) or 1))

	setText(objectiveTitle, "Objetivo")
	setText(
		objectiveDescription,
		truncateUtf8(snapshot.Title or snapshot.Description or "Explore a ilha", OBJECTIVE_DESCRIPTION_MAX)
	)
	setText(objectiveCounter, string.format("%d / %d", progress, target))

	setFillRatio(objectiveProgressFill, objectiveFullX, progress / target, 0.28)

	if objectiveCompletedIcon then
		objectiveCompletedIcon.Visible = state == "Completed"
	end

	lastObjectiveProgress = progress
end

---------------------------------------------------------------------
-- Player Status
---------------------------------------------------------------------

local playerName
local avatarImage
local levelText

local function resolveBar(root, rootAliases, label)
	if not root then
		return nil
	end

	local barRoot = authored(root, label, rootAliases, isGui)
	if not barRoot then
		return nil
	end

	local background = authored(
		barRoot,
		label .. ".Background",
		{ "Background", "BarBackground", "Track", "Back" },
		isGui
	)

	local fill = authored(
		barRoot,
		label .. ".Fill",
		{ "Fill", "BarFill", "ProgressFill", "ValueFill" },
		isGui
	)

	local value = authored(
		barRoot,
		label .. ".Value",
		{ "Value", "ValueText", "Counter", "Amount", "Text" },
		isText
	)

	local fullX
	if fill then
		if background then
			if fill.Parent == background then
				fullX = UDim.new(1, 0)
			elseif fill.Parent == background.Parent then
				fullX = background.Size.X
			end
		end
		fullX = fullX or fill.Size.X
	end

	return {
		Root = barRoot,
		Background = background,
		Fill = fill,
		Value = value,
		FullX = fullX,
	}
end

local healthBar
local staminaBar
local xpBar

if playerStatus then
	playerStatus.Visible = true

	playerName = authored(
		playerStatus,
		"PlayerStatus.PlayerName",
		{ "PlayerName", "DisplayName", "NameLabel", "Username" },
		isText
	)

	local portrait = authored(
		playerStatus,
		"PlayerStatus.Portrait",
		{ "Portrait", "PlayerPortrait", "AvatarHolder" },
		isGui
	) or playerStatus

	avatarImage = authored(
		portrait,
		"PlayerStatus.AvatarImage",
		{ "AvatarImage", "Avatar", "Headshot", "PlayerImage" },
		function(object)
			return object:IsA("ImageLabel") or object:IsA("ImageButton")
		end
	)

	levelText = authored(
		portrait,
		"PlayerStatus.LevelText",
		{ "LevelText", "Level", "Lvl", "PlayerLevel" },
		isText
	) or authored(
		playerStatus,
		"PlayerStatus.LevelText",
		{ "LevelText", "Level", "Lvl", "PlayerLevel" },
		isText
	)

	healthBar = resolveBar(
		playerStatus,
		{ "HealthBar", "HPBar", "Health", "Vida" },
		"HealthBar"
	)

	staminaBar = resolveBar(
		playerStatus,
		{ "StaminaBar", "EnergyBar", "Stamina", "Energia" },
		"StaminaBar"
	)

	xpBar = resolveBar(
		playerStatus,
		{ "XPBar", "ExperienceBar", "ExpBar", "XP", "Experience" },
		"XPBar"
	)

	setText(playerName, player.DisplayName)
end

local function setBar(bar, ratio, text)
	if not bar then
		return
	end

	setText(bar.Value, text)
	setFillRatio(bar.Fill, bar.FullX, ratio, 0.18)
end

local currentCharacter
local currentHumanoid
local characterConnections = {}

local function clearCharacterConnections()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function updateHealth()
	if not currentHumanoid or not currentHumanoid.Parent then
		setBar(healthBar, 0, "0 / 0")
		return
	end

	local maximum = math.max(1, currentHumanoid.MaxHealth)
	local current = math.max(0, currentHumanoid.Health)

	setBar(
		healthBar,
		current / maximum,
		string.format("%d / %d", math.floor(current + 0.5), math.floor(maximum + 0.5))
	)
end

local function updateStamina()
	if not currentCharacter or not currentCharacter.Parent then
		return
	end

	local maximum = tonumber(currentCharacter:GetAttribute("SprintStaminaMax"))
	local current = tonumber(currentCharacter:GetAttribute("SprintStamina"))

	if not maximum or maximum <= 0 or current == nil then
		return
	end

	setBar(
		staminaBar,
		current / maximum,
		string.format("%.1f / %.1f", math.max(0, current), maximum)
	)
end

local lastLevel = math.max(1, math.floor(tonumber(player:GetAttribute("RunLevel")) or 1))

local function updateXP()
	local level = math.max(1, math.floor(tonumber(player:GetAttribute("RunLevel")) or 1))
	local distance = math.max(0, tonumber(player:GetAttribute("RunDistance")) or 0)
	local levelStart = math.max(0, tonumber(player:GetAttribute("RunLevelStartDistance")) or 0)
	local levelEnd = math.max(
		levelStart + 1,
		tonumber(player:GetAttribute("RunLevelEndDistance")) or levelStart + 1
	)

	local current = math.max(0, distance - levelStart)
	local required = math.max(1, levelEnd - levelStart)

	setText(levelText, level)
	setBar(
		xpBar,
		current / required,
		string.format("%d / %d XP", math.floor(current + 0.5), math.floor(required + 0.5))
	)

	lastLevel = level
end

local function bindCharacter(character)
	clearCharacterConnections()

	currentCharacter = character
	currentHumanoid = character:WaitForChild("Humanoid", 10)

	if currentHumanoid then
		table.insert(characterConnections, currentHumanoid.HealthChanged:Connect(updateHealth))
		table.insert(
			characterConnections,
			currentHumanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)
		)
	end

	for _, attribute in ipairs({ "SprintStamina", "SprintStaminaMax", "Sprinting" }) do
		table.insert(
			characterConnections,
			character:GetAttributeChangedSignal(attribute):Connect(updateStamina)
		)
	end

	updateHealth()
	updateStamina()
end

player.CharacterAdded:Connect(bindCharacter)

if player.Character then
	task.spawn(bindCharacter, player.Character)
end

for _, attribute in ipairs({
	"RunLevel",
	"RunDistance",
	"RunLevelStartDistance",
	"RunLevelEndDistance",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(updateXP)
end

updateXP()

if avatarImage then
	task.spawn(function()
		local ok, image = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			player.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)

		if ok
			and avatarImage.Parent
			and (avatarImage:IsA("ImageLabel") or avatarImage:IsA("ImageButton"))
		then
			avatarImage.Image = image
		end
	end)
end

---------------------------------------------------------------------
-- MiniMap
-- Runtime markers are clones of authored templates.
---------------------------------------------------------------------

local mapArea
local islandContainer
local markerContainer
local playerArrow
local smallIslandTemplate
local mediumIslandTemplate
local largeIslandTemplate
local hostileMobTemplate
local objectiveMarkerTemplate
local roundGateTemplate

if miniMap then
	miniMap.Visible = true

	mapArea = findAuthored(
		miniMap,
		{ "MapArea", "MapContent", "ContentArea", "RadarArea" },
		isGui
	) or miniMap

	islandContainer = authored(
		mapArea,
		"MiniMap.IslandContainer",
		{ "IslandContainer", "IslandsContainer", "Islands", "IslandLayer" },
		isGui
	)

	markerContainer = authored(
		mapArea,
		"MiniMap.MarkerContainer",
		{ "MarkerContainer", "MarkersContainer", "Markers", "MarkerLayer" },
		isGui
	)

	playerArrow = authored(
		mapArea,
		"MiniMap.PlayerArrow",
		{ "PlayerArrow", "PlayerMarker", "PlayerIcon", "Arrow" },
		isGui
	)

	if playerArrow then
		playerArrow.Visible = true
	end

	if islandContainer then
		smallIslandTemplate = authored(
			islandContainer,
			"MiniMap.SmallIslandTemplate",
			{ "SmallIslandTemplate", "SmallIsland", "IslandSmall" },
			isGui
		)

		mediumIslandTemplate = authored(
			islandContainer,
			"MiniMap.MediumIslandTemplate",
			{ "MediumIslandTemplate", "MediumIsland", "IslandMedium" },
			isGui
		)

		largeIslandTemplate = authored(
			islandContainer,
			"MiniMap.LargeIslandTemplate",
			{ "LargeIslandTemplate", "LargeIsland", "IslandLarge" },
			isGui
		)

		for _, template in ipairs({
			smallIslandTemplate,
			mediumIslandTemplate,
			largeIslandTemplate,
		}) do
			if template then
				template.Visible = false
			end
		end
	end

	if markerContainer then
		hostileMobTemplate = authored(
			markerContainer,
			"MiniMap.HostileMobMarker",
			{ "HostileMobMarker", "HostileMarker", "EnemyMarker", "MobMarker" },
			isGui
		)

		objectiveMarkerTemplate = authored(
			markerContainer,
			"MiniMap.CurrentObjectiveMarker",
			{ "CurrentObjectiveMarker", "ObjectiveMarker", "CurrentObjective", "TargetMarker" },
			isGui
		)

		roundGateTemplate = authored(
			markerContainer,
			"MiniMap.RoundGateMarker",
			{ "RoundGateMarker", "GateMarker", "RoundMarker", "RoundExitMarker" },
			isGui
		)

		for _, template in ipairs({
			hostileMobTemplate,
			objectiveMarkerTemplate,
			roundGateTemplate,
		}) do
			if template then
				template.Visible = false
			end
		end
	end
end

local islandMarkers = {}
local hostileMarkers = {}
local gateMarkers = {}
local objectiveMarkerClone

local function cloneAuthoredTemplate(template, name, parent)
	if not template or not parent then
		return nil
	end

	local clone = template:Clone()
	clone.Name = name
	clone.Visible = true
	clone:SetAttribute("RuntimeCloneOfAuthoredTemplate", true)
	clone.Parent = parent
	return clone
end

local function mapPosition(worldPosition, playerPosition)
	if not miniMap then
		return nil
	end

	local range = math.max(80, tonumber(miniMap:GetAttribute("MapRangeStuds")) or MINIMAP_RANGE)
	local delta = worldPosition - playerPosition
	local nx = delta.X / range
	local ny = delta.Z / range

	if Vector2.new(nx, ny).Magnitude > 1 then
		return nil
	end

	local radius = 0.44
	return UDim2.fromScale(0.5 + nx * radius, 0.5 + ny * radius)
end

local function markerIslandCenter(markerFolder)
	local island = markerFolder.Parent
	if not island then
		return nil, nil
	end

	local anchor = markerFolder:FindFirstChild("ObjectiveAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position, island
	end

	if island:IsA("Model") then
		local floor = island:FindFirstChild("IslandFloor") or island.PrimaryPart
		if floor and floor:IsA("BasePart") then
			return floor.Position, island
		end
	end

	return nil, island
end

local function templateForIsland(island)
	if not island then
		return mediumIslandTemplate
	end

	local declared = tostring(
		island:GetAttribute("IslandSize")
			or island:GetAttribute("SizeClass")
			or ""
	)

	if declared == "Small" then
		return smallIslandTemplate
	elseif declared == "Large" then
		return largeIslandTemplate
	elseif declared == "Medium" then
		return mediumIslandTemplate
	end

	if island:IsA("Model") then
		local floor = island:FindFirstChild("IslandFloor") or island.PrimaryPart
		if floor and floor:IsA("BasePart") then
			local minimum = math.min(floor.Size.X, floor.Size.Z)
			if minimum < 72 then
				return smallIslandTemplate
			elseif minimum >= 108 then
				return largeIslandTemplate
			end
		end
	end

	return mediumIslandTemplate
end

local function updateIslands(playerPosition)
	if not islandContainer then
		return
	end

	local seen = {}

	for _, folder in ipairs(CollectionService:GetTagged("DungeonGameplayMarkers")) do
		if folder:IsA("Folder") and folder.Parent then
			local worldPosition, island = markerIslandCenter(folder)

			if worldPosition and island then
				seen[folder] = true

				local template = templateForIsland(island)
				if template then
					local marker = islandMarkers[folder]

					if not marker or not marker.Parent
						or marker:GetAttribute("AuthoredTemplateName") ~= template.Name
					then
						if marker then
							marker:Destroy()
						end

						marker = cloneAuthoredTemplate(
							template,
							"Island_" .. island.Name,
							islandContainer
						)

						if marker then
							marker:SetAttribute("AuthoredTemplateName", template.Name)
							islandMarkers[folder] = marker
						end
					end

					if marker then
						local position = mapPosition(worldPosition, playerPosition)
						marker.Visible = position ~= nil
						if position then
							marker.Position = position
						end
					end
				end
			end
		end
	end

	for source, marker in pairs(islandMarkers) do
		if not seen[source] or not source.Parent then
			marker:Destroy()
			islandMarkers[source] = nil
		end
	end
end

local function updateGates(playerPosition)
	if not markerContainer or not roundGateTemplate then
		return
	end

	local seen = {}

	for _, folder in ipairs(CollectionService:GetTagged("DungeonGameplayMarkers")) do
		if folder:IsA("Folder") and folder.Parent then
			local island = folder.Parent

			if island:GetAttribute("IsRoundExit") == true then
				seen[island] = true
				local marker = gateMarkers[island]

				if not marker or not marker.Parent then
					marker = cloneAuthoredTemplate(
						roundGateTemplate,
						"RoundGate_" .. island.Name,
						markerContainer
					)
					gateMarkers[island] = marker
				end

				local worldPosition = select(1, markerIslandCenter(folder))
				local position = worldPosition and mapPosition(worldPosition, playerPosition) or nil

				if marker then
					marker.Visible = position ~= nil
					if position then
						marker.Position = position
					end
				end
			end
		end
	end

	for island, marker in pairs(gateMarkers) do
		if not seen[island] or not island.Parent then
			marker:Destroy()
			gateMarkers[island] = nil
		end
	end
end

local function targetRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function updateHostiles(playerPosition)
	if not markerContainer or not hostileMobTemplate then
		return
	end

	local seen = {}

	for _, target in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if target:IsA("Model")
			and target.Parent
			and target:GetAttribute("Peaceful") ~= true
		then
			local humanoid = target:FindFirstChildWhichIsA("Humanoid", true)
			local root = targetRoot(target)

			if root and (not humanoid or humanoid.Health > 0) then
				seen[target] = true

				local marker = hostileMarkers[target]
				if not marker or not marker.Parent then
					marker = cloneAuthoredTemplate(
						hostileMobTemplate,
						"HostileMob",
						markerContainer
					)
					hostileMarkers[target] = marker
				end

				if marker then
					local position = mapPosition(root.Position, playerPosition)
					marker.Visible = position ~= nil
					if position then
						marker.Position = position
					end
				end
			end
		end
	end

	for target, marker in pairs(hostileMarkers) do
		if not seen[target] or not target.Parent then
			marker:Destroy()
			hostileMarkers[target] = nil
		end
	end
end

local function findObjectiveAnchor(snapshot)
	local globalIndex = snapshot and tonumber(snapshot.GlobalIslandIndex)
	if not globalIndex then
		return nil
	end

	for _, folder in ipairs(CollectionService:GetTagged("DungeonGameplayMarkers")) do
		if folder:IsA("Folder") and folder.Parent then
			local island = folder.Parent
			local index = tonumber(island:GetAttribute("GlobalIslandIndex"))
				or tonumber(folder:GetAttribute("GlobalIslandIndex"))

			if index == globalIndex then
				local anchor = folder:FindFirstChild("ObjectiveAnchor", true)
				if anchor and anchor:IsA("BasePart") then
					return anchor
				end
			end
		end
	end

	return nil
end

local function updateObjectiveMarker(playerPosition)
	if not markerContainer or not objectiveMarkerTemplate then
		return
	end

	local anchor = currentObjective and findObjectiveAnchor(currentObjective) or nil

	if not anchor then
		if objectiveMarkerClone then
			objectiveMarkerClone.Visible = false
		end
		return
	end

	if not objectiveMarkerClone or not objectiveMarkerClone.Parent then
		objectiveMarkerClone = cloneAuthoredTemplate(
			objectiveMarkerTemplate,
			"CurrentObjectiveRuntime",
			markerContainer
		)
	end

	if objectiveMarkerClone then
		local position = mapPosition(anchor.Position, playerPosition)
		objectiveMarkerClone.Visible = position ~= nil
		if position then
			objectiveMarkerClone.Position = position
		end
	end
end

local minimapElapsed = 0

RunService.RenderStepped:Connect(function(dt)
	if not miniMap then
		return
	end

	minimapElapsed += dt
	if minimapElapsed < MINIMAP_UPDATE_INTERVAL then
		return
	end
	minimapElapsed = 0

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	updateIslands(root.Position)
	updateGates(root.Position)
	updateHostiles(root.Position)
	updateObjectiveMarker(root.Position)

	if playerArrow then
		local look = root.CFrame.LookVector
		playerArrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end
end)

---------------------------------------------------------------------
-- Missions
-- MissionTemplate e todo seu visual devem existir no Studio.
---------------------------------------------------------------------

local missionList
local missionTemplate
local collapseButton
local missionRows = {}
local missionsCollapsed = false

if missionsPanel then
	missionsPanel.Visible = true

	missionList = authored(
		missionsPanel,
		"Missions.MissionList",
		{ "MissionList", "MissionsList", "QuestList", "List", "Content" },
		isGui
	)

	if missionList then
		missionTemplate = authored(
			missionList,
			"Missions.MissionTemplate",
			{ "MissionTemplate", "QuestTemplate", "MissionItem", "QuestItem", "Template" },
			isGui
		)

		if missionTemplate then
			missionTemplate.Visible = false
		end
	end

	collapseButton = authored(
		missionsPanel,
		"Missions.CollapseButton",
		{ "CollapseButton", "Collapse", "ToggleButton", "MinimizeButton", "ArrowButton" },
		function(object)
			return object:IsA("GuiButton")
		end
	)
end

local function clearMissionRows()
	for _, row in ipairs(missionRows) do
		if row.Parent then
			row:Destroy()
		end
	end
	table.clear(missionRows)
end

local function addMission(order, titleText, descriptionText, progressText)
	if not missionTemplate or not missionList then
		return
	end

	local row = missionTemplate:Clone()
	row.Name = "RuntimeMission_" .. tostring(order)
	row.LayoutOrder = order
	row.Visible = true
	row:SetAttribute("RuntimeCloneOfAuthoredTemplate", true)
	row.Parent = missionList

	local title = findAuthored(
		row,
		{ "MissionTitle", "QuestTitle", "Title", "Name" },
		isText
	)

	local description = findAuthored(
		row,
		{ "Description", "MissionDescription", "QuestDescription", "Detail" },
		isText
	)

	local progress = findAuthored(
		row,
		{ "Progress", "ProgressText", "Counter", "Count" },
		isText
	)

	setText(title, titleText)
	setText(description, descriptionText)
	setText(progress, progressText or "")

	if progress and isGui(progress) then
		progress.Visible = progressText ~= nil and progressText ~= ""
	end

	table.insert(missionRows, row)
end

local function renderMissions(snapshot)
	if not missionsPanel then
		return
	end

	clearMissionRows()
	snapshot = snapshot or readObjective()

	local state = tostring(snapshot.State or "Inactive")
	local round = math.max(1, math.floor(tonumber(snapshot.RoundIndex) or 1))
	local island = math.max(1, math.floor(tonumber(snapshot.IslandIndex) or 1))
	local roundLength = ROUND_LENGTHS[round] or math.max(1, island)

	if state == "Active" then
		local progress = math.max(0, math.floor(tonumber(snapshot.Progress) or 0))
		local target = math.max(1, math.floor(tonumber(snapshot.Target) or 1))

		addMission(
			1,
			"Missão Principal",
			truncateUtf8(snapshot.Title or snapshot.Description or "Conclua o objetivo atual", 68),
			string.format("(%d/%d)", progress, target)
		)

		addMission(
			2,
			"Progresso da Rodada",
			string.format("Avance pelas ilhas da rodada %d.", round),
			string.format("(%d/%d)", math.min(island, roundLength), roundLength)
		)
	elseif state == "Completed" then
		addMission(1, "Objetivo Concluído", "Avance para a próxima ilha.", "✓")
	else
		addMission(1, "Exploração", "Encontre a próxima ilha da rota.", nil)
	end
end

if collapseButton and missionList then
	collapseButton.Activated:Connect(function()
		missionsCollapsed = not missionsCollapsed
		missionList.Visible = not missionsCollapsed
	end)
end

---------------------------------------------------------------------
-- Dispatcher
---------------------------------------------------------------------

local function dispatchObjective(snapshot)
	renderObjective(snapshot)
	renderMissions(snapshot)
end

for _, attribute in ipairs({
	"DungeonObjectiveState",
	"DungeonObjectiveId",
	"DungeonObjectiveTitle",
	"DungeonObjectiveDescription",
	"DungeonObjectiveRoundIndex",
	"DungeonObjectiveIslandIndex",
	"DungeonObjectiveGlobalIslandIndex",
	"DungeonObjectiveProgress",
	"DungeonObjectiveTarget",
	"DungeonObjectiveWaypointEscalated",
	"DungeonObjectiveExitLocked",
}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(function()
		dispatchObjective(readObjective())
	end)
end

task.spawn(function()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
		or ReplicatedStorage:WaitForChild("Shared", 20)

	if not shared then
		return
	end

	local utilities = shared:FindFirstChild("Utilities")
		or shared:WaitForChild("Utilities", 10)

	if not utilities then
		return
	end

	local registryModule = utilities:FindFirstChild("RemoteRegistry")
	if not registryModule then
		return
	end

	local okRegistry, registry = pcall(require, registryModule)
	if not okRegistry or not registry then
		return
	end

	local okRemote, remote = pcall(
		registry.Get,
		"Dungeon",
		"ObjectiveState",
		"RemoteEvent"
	)

	if not okRemote or not remote then
		return
	end

	remote.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.Action == "ObjectiveSnapshot" then
			dispatchObjective(payload.Objective)
		end
	end)
end)

dispatchObjective(readObjective())

player:SetAttribute("DungeonArtHUDControllerReady", true)
player:SetAttribute("DungeonArtHUDMode", "AuthoredOnlyV8")
player:SetAttribute("DungeonArtHUDCreatesVisuals", false)

if hud then
	hud:SetAttribute("ControllerReady", true)
end

print("[AuthoredHUD] Strict V8 ready. Nenhum HUD foi desenhado pelo controller.")
