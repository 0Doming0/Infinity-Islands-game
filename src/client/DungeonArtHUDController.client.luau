-- DungeonArtHUDController.client.luau
-- Authored HUD Controller V12 - New Core Binding
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
--   MissionsPanel -> DungeonHUD_Missions (opcional; oculto no MVP simplificado)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local IslandAdvanceFeedbackConfig = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("IslandAdvanceFeedbackConfig")
)

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
	hud:SetAttribute("ControllerVersion", "AuthoredHUDStrictV11ReadableDistance")
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

local islandClearFeedbackSerial =
	math.floor(
		tonumber(
			workspace:GetAttribute(
				"DungeonIslandClearFeedbackSerial"
			)
		) or 0
	)

local objectivePulseSerial = 0

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

local function objectiveIslandMetadata(globalIndex)
	globalIndex = math.floor(
		tonumber(globalIndex) or 0
	)

	if globalIndex <= 0 then
		return nil
	end

	for _, folder in ipairs(
		CollectionService:GetTagged(
			"DungeonGameplayMarkers"
		)
	) do
		if folder:IsA("Folder")
			and folder.Parent
		then
			local island = folder.Parent

			local index =
				math.floor(
					tonumber(
						island:GetAttribute(
							"GlobalIslandIndex"
						)
							or folder:GetAttribute(
								"GlobalIslandIndex"
							)
					) or 0
				)

			if index == globalIndex then
				return {
					Island = island,
					GlobalIslandIndex = index,
					IslandLevel =
						math.max(
							1,
							math.floor(
								tonumber(
									island:GetAttribute(
										"IslandLevel"
									)
								) or 1
							)
						),
					RecommendedLevel =
						math.max(
							1,
							math.floor(
								tonumber(
									island:GetAttribute(
										"RecommendedLevel"
									)
								)
									or tonumber(
										island:GetAttribute(
											"IslandLevel"
										)
									)
									or 1
							)
						),
					Cleared =
						island:GetAttribute(
							"Cleared"
						) == true,
					CombatState =
						tostring(
							island:GetAttribute(
								"CombatState"
							) or "Dormant"
						),
				}
			end
		end
	end

	return nil
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

local function pulseAuthoredText(
	textObject,
	scale,
	upSeconds,
	downSeconds
)
	if not textObject
		or not textObject.Parent
		or not (
			textObject:IsA("TextLabel")
				or textObject:IsA("TextButton")
		)
	then
		return
	end

	objectivePulseSerial += 1
	local serial = objectivePulseSerial
	local originalSize = textObject.TextSize

	if originalSize <= 0 then
		return
	end

	local up =
		TweenService:Create(
			textObject,
			TweenInfo.new(
				upSeconds,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				TextSize = originalSize * scale,
			}
		)

	up:Play()

	up.Completed:Once(function()
		if objectivePulseSerial ~= serial
			or not textObject.Parent
		then
			return
		end

		TweenService:Create(
			textObject,
			TweenInfo.new(
				downSeconds,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
			{
				TextSize = originalSize,
			}
		):Play()
	end)
end

local function pulseObjectiveClear()
	pulseAuthoredText(
		objectiveTitle,
		IslandAdvanceFeedbackConfig.ClearPulseScale,
		IslandAdvanceFeedbackConfig.ClearPulseUpSeconds,
		IslandAdvanceFeedbackConfig.ClearPulseDownSeconds
	)

	pulseAuthoredText(
		objectiveDescription,
		1
			+ (
				IslandAdvanceFeedbackConfig.ClearPulseScale - 1
			) * 0.55,
		IslandAdvanceFeedbackConfig.ClearPulseUpSeconds,
		IslandAdvanceFeedbackConfig.ClearPulseDownSeconds
	)
end

local function updateIslandClearFeedbackSerial()
	local serial =
		math.floor(
			tonumber(
				workspace:GetAttribute(
					"DungeonIslandClearFeedbackSerial"
				)
			) or 0
		)

	if serial <= islandClearFeedbackSerial then
		return
	end

	islandClearFeedbackSerial = serial

	player:SetAttribute(
		"DungeonIslandClearFeedbackSerialSeen",
		serial
	)
	player:SetAttribute(
		"DungeonIslandClearFeedbackSeenAt",
		workspace:GetServerTimeNow()
	)

	task.defer(pulseObjectiveClear)
end

local function advanceMarkerScale()
	if workspace:GetAttribute(
		"DungeonIslandAdvanceActive"
	) ~= true
	then
		return 1
	end

	local minimum =
		IslandAdvanceFeedbackConfig.MarkerPulseMinimumScale

	local maximum =
		IslandAdvanceFeedbackConfig.MarkerPulseMaximumScale

	local wave =
		(
			math.sin(
				os.clock()
					* math.pi
					* 2
					* IslandAdvanceFeedbackConfig
						.MarkerPulseCyclesPerSecond
			)
				+ 1
		) * 0.5

	return minimum
		+ (maximum - minimum) * wave
end

local function renderObjective(snapshot)
	snapshot = snapshot or readObjective()
	currentObjective = snapshot

	if not objectivePanel then
		return
	end

	local state =
		tostring(snapshot.State or "Inactive")

	local active =
		state == "Active"
			or state == "Completed"

	objectivePanel.Visible = active

	if not active then
		return
	end

	local progress =
		math.max(
			0,
			math.floor(
				tonumber(snapshot.Progress) or 0
			)
		)

	local target =
		math.max(
			1,
			math.floor(
				tonumber(snapshot.Target) or 1
			)
		)

	local metadata =
		objectiveIslandMetadata(
			snapshot.GlobalIslandIndex
				or workspace:GetAttribute(
					"DungeonCurrentObjectiveIsland"
				)
		)

	if state == "Completed" then
		setText(
			objectiveTitle,
			workspace:GetAttribute(
				"DungeonLinearRouteComplete"
			) == true
				and "ROTA CONCLUÍDA"
				or "ILHA LIMPA"
		)

		local routeComplete =
			workspace:GetAttribute(
				"DungeonLinearRouteComplete"
			) == true

		local nextIsland =
			tonumber(
				workspace:GetAttribute(
					"DungeonIslandAdvanceToIsland"
				)
					or workspace:GetAttribute(
						"DungeonNextCombatIslandUnlocked"
					)
			)

		setText(
			objectiveDescription,
			routeComplete
				and IslandAdvanceFeedbackConfig.RouteCompleteDescription
				or nextIsland
					and string.format(
						IslandAdvanceFeedbackConfig
							.AdvanceDescriptionFormat,
						math.floor(nextIsland)
					)
					or "AVANCE"
		)

		setText(
			objectiveCounter,
			"✓"
		)

		setFillRatio(
			objectiveProgressFill,
			objectiveFullX,
			1,
			0.24
		)
	else
		setText(
			objectiveTitle,
			truncateUtf8(
				snapshot.Title
					or "DERROTE OS INIMIGOS",
				OBJECTIVE_DESCRIPTION_MAX
			)
		)

		local description

		if metadata then
			description =
				string.format(
					"ILHA %d  •  RECOMENDADO: NÍVEL %d",
					metadata.GlobalIslandIndex,
					metadata.RecommendedLevel
				)
		else
			description =
				snapshot.Description
					or "ELIMINE TODOS OS INIMIGOS"
		end

		setText(
			objectiveDescription,
			truncateUtf8(
				description,
				OBJECTIVE_DESCRIPTION_MAX
			)
		)

		setText(
			objectiveCounter,
			string.format(
				"%d / %d",
				math.min(progress, target),
				target
			)
		)

		setFillRatio(
			objectiveProgressFill,
			objectiveFullX,
			progress / target,
			0.28
		)
	end

	if objectiveCompletedIcon then
		objectiveCompletedIcon.Visible =
			state == "Completed"
	end

	objectivePanel:SetAttribute(
		"RuntimeCombatState",
		metadata
			and metadata.CombatState
			or state
	)

	objectivePanel:SetAttribute(
		"RuntimeGlobalIslandIndex",
		metadata
			and metadata.GlobalIslandIndex
			or snapshot.GlobalIslandIndex
	)

	objectivePanel:SetAttribute(
		"RuntimeRecommendedLevel",
		metadata
			and metadata.RecommendedLevel
			or nil
	)

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

local lastLevel =
	math.max(
		1,
		math.floor(
			tonumber(
				player:GetAttribute(
					"PlayerLevel"
				)
			) or 1
		)
	)

local function updateXP()
	local level =
		math.max(
			1,
			math.floor(
				tonumber(
					player:GetAttribute(
						"PlayerLevel"
					)
				) or 1
			)
		)

	local current =
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute(
						"PlayerXP"
					)
				) or 0
			)
		)

	local required =
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute(
						"PlayerXPToNextLevel"
					)
				) or 0
			)
		)

	local ratio =
		required > 0
			and math.clamp(
				current / required,
				0,
				1
			)
			or 1

	setText(
		levelText,
		tostring(level)
	)

	setBar(
		xpBar,
		ratio,
		required > 0
			and string.format(
				"%d / %d XP",
				current,
				required
			)
			or "MAX"
	)

	if playerStatus then
		playerStatus:SetAttribute(
			"RuntimePlayerLevel",
			level
		)
		playerStatus:SetAttribute(
			"RuntimePlayerXP",
			current
		)
		playerStatus:SetAttribute(
			"RuntimePlayerXPToNextLevel",
			required
		)
		playerStatus:SetAttribute(
			"RuntimePlayerXPProgress",
			ratio
		)
	end

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
	"PlayerLevel",
	"PlayerXP",
	"PlayerXPToNextLevel",
	"PlayerXPProgress",
	"LastXPGain",
}) do
	player:GetAttributeChangedSignal(
		attribute
	):Connect(updateXP)
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
--
-- Dynamic-size rules:
-- - every position is derived from the REAL AbsoluteSize/AbsolutePosition;
-- - player arrow is always at the geometric center;
-- - usable radius automatically respects the smallest map dimension;
-- - default world range scales with the minimap's actual pixel diameter;
-- - nearby markers are expanded radially for readability;
-- - overlapping markers are gently separated using their REAL icon size;
-- - map orientation is FIXED north-up;
-- - only the player's arrow rotates;
-- - islands are filtered by vertical distance BEFORE an icon is cloned;
-- - vertical visibility range also derives from the real minimap size.
--
-- Optional MiniMap Attributes:
-- MapRangeStuds                 -> explicit horizontal world radius in studs
-- MapStudsPerPixel              -> horizontal dynamic default = 1.20
-- MapMaxHeightDifferenceStuds   -> explicit vertical slice half-height
-- MapVerticalStudsPerPixel      -> vertical dynamic default = 0.45
-- MapEdgePaddingRatio           -> dynamic default = 0.075
-- MapMarkerGapRatio             -> dynamic default = 0.025
-- MapSpreadExponent             -> dynamic default = 0.62
-- MapIslandShrinkStartRatio     -> island shrinks after 0.75 of map range
-- MapIslandMinimumScale         -> island reaches 0.70 scale at edge
-- MapMobVisibleRangeRatio       -> mob icons only until 0.68 of map range
---------------------------------------------------------------------

local mapArea
local islandContainer
local markerContainer
local playerArrow
local northLabel

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

	northLabel = findAuthored(
		mapArea,
		{ "NorthLabel", "North", "NorthIndicator" },
		isGui
	)

	if playerArrow then
		playerArrow.Visible = true
		playerArrow.AnchorPoint = Vector2.new(0.5, 0.5)
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

local islandOccupied = {}
local markerOccupied = {}

-- Exact designer-authored Size for runtime clones.
-- Scaling is always recalculated from this base, never compounded.
local runtimeBaseSizes = setmetatable({}, { __mode = "k" })

local function cloneAuthoredTemplate(template, name, parent)
	if not template or not parent then
		return nil
	end

	local clone = template:Clone()
	clone.Name = name
	clone.Visible = true
	clone.AnchorPoint = Vector2.new(0.5, 0.5)
	clone:SetAttribute("RuntimeCloneOfAuthoredTemplate", true)
	clone.Parent = parent
	runtimeBaseSizes[clone] = clone.Size
	return clone
end

local function scaledUDim2(size, factor)
	factor = math.max(0, tonumber(factor) or 1)

	return UDim2.new(
		size.X.Scale * factor,
		math.floor(size.X.Offset * factor + 0.5),
		size.Y.Scale * factor,
		math.floor(size.Y.Offset * factor + 0.5)
	)
end

local function setRuntimeScale(object, factor)
	if not object or not object.Parent then
		return
	end

	local baseSize = runtimeBaseSizes[object]
	if not baseSize then
		baseSize = object.Size
		runtimeBaseSizes[object] = baseSize
	end

	factor = math.clamp(tonumber(factor) or 1, 0.1, 2)
	object.Size = scaledUDim2(baseSize, factor)
	object:SetAttribute("RuntimeDistanceScale", factor)
end

local function validAbsoluteSize(object)
	if not object or not object:IsA("GuiObject") then
		return nil
	end

	local size = object.AbsoluteSize
	if size.X <= 1 or size.Y <= 1 then
		return nil
	end

	return size
end

local function minimapMetrics()
	if not miniMap or not mapArea then
		return nil
	end

	local size = validAbsoluteSize(mapArea)
		or validAbsoluteSize(miniMap)

	if not size then
		return nil
	end

	local area = validAbsoluteSize(mapArea) and mapArea or miniMap
	local areaSize = area.AbsoluteSize
	local areaPosition = area.AbsolutePosition

	local minimumDimension = math.min(areaSize.X, areaSize.Y)
	local centerAbsolute =
		areaPosition
		+ Vector2.new(areaSize.X * 0.5, areaSize.Y * 0.5)

	local edgePaddingRatio = math.clamp(
		tonumber(miniMap:GetAttribute("MapEdgePaddingRatio")) or 0.075,
		0.02,
		0.20
	)

	local edgePaddingPixels = math.max(
		6,
		minimumDimension * edgePaddingRatio
	)

	local radiusPixels = math.max(
		16,
		minimumDimension * 0.5 - edgePaddingPixels
	)

	local explicitRange = tonumber(
		miniMap:GetAttribute("MapRangeStuds")
	)

	local studsPerPixel = math.clamp(
		tonumber(miniMap:GetAttribute("MapStudsPerPixel")) or 1.20,
		0.55,
		3.0
	)

	-- Example:
	-- 216px minimap -> ~259 studs of world radius by default.
	local worldRange = explicitRange
		or math.clamp(
			minimumDimension * studsPerPixel,
			150,
			480
		)

	local explicitVerticalRange = tonumber(
		miniMap:GetAttribute("MapMaxHeightDifferenceStuds")
	)

	local verticalStudsPerPixel = math.clamp(
		tonumber(miniMap:GetAttribute("MapVerticalStudsPerPixel")) or 0.45,
		0.20,
		1.50
	)

	-- The minimap represents a horizontal "slice" around the player.
	-- Example: 216px minimap -> ~97 studs above/below the player.
	local maxHeightDifference = explicitVerticalRange
		or math.clamp(
			minimumDimension * verticalStudsPerPixel,
			55,
			180
		)

	local markerGapPixels = math.max(
		3,
		minimumDimension
			* math.clamp(
				tonumber(miniMap:GetAttribute("MapMarkerGapRatio")) or 0.025,
				0.005,
				0.08
			)
	)

	local spreadExponent = math.clamp(
		tonumber(miniMap:GetAttribute("MapSpreadExponent")) or 0.62,
		0.45,
		1.0
	)

	return {
		Area = area,
		Size = areaSize,
		MinimumDimension = minimumDimension,
		CenterAbsolute = centerAbsolute,
		RadiusPixels = radiusPixels,
		WorldRange = worldRange,
		MaxHeightDifference = maxHeightDifference,
		GapPixels = markerGapPixels,
		SpreadExponent = spreadExponent,
	}
end

local function approximateGuiSize(object, metrics)
	if not object or not metrics then
		return Vector2.new(12, 12)
	end

	local absolute = object.AbsoluteSize
	if absolute.X > 1 and absolute.Y > 1 then
		return absolute
	end

	local size = object.Size
	return Vector2.new(
		math.max(4, metrics.Size.X * size.X.Scale + size.X.Offset),
		math.max(4, metrics.Size.Y * size.Y.Scale + size.Y.Offset)
	)
end

local function centerObjectInMap(object, metrics)
	if not object or not object.Parent or not metrics then
		return
	end

	local parent = object.Parent
	if not parent:IsA("GuiObject") then
		return
	end

	object.AnchorPoint = Vector2.new(0.5, 0.5)

	local localCenter =
		metrics.CenterAbsolute
		- parent.AbsolutePosition

	object.Position = UDim2.fromOffset(
		math.floor(localCenter.X + 0.5),
		math.floor(localCenter.Y + 0.5)
	)
end

local function clampPixelToMapCircle(pixel, markerRadius, metrics)
	local delta = pixel - metrics.CenterAbsolute

	local allowedRadius = math.max(
		8,
		metrics.RadiusPixels - markerRadius
	)

	if delta.Magnitude <= allowedRadius then
		return pixel
	end

	if delta.Magnitude <= 0.001 then
		return metrics.CenterAbsolute
	end

	return metrics.CenterAbsolute + delta.Unit * allowedRadius
end

local function reserveReadablePosition(
	desiredPixel,
	object,
	metrics,
	occupied
)
	if not desiredPixel or not object or not metrics then
		return desiredPixel
	end

	local size = approximateGuiSize(object, metrics)
	local objectRadius =
		math.max(size.X, size.Y) * 0.5

	local desired = clampPixelToMapCircle(
		desiredPixel,
		objectRadius,
		metrics
	)

	local function free(candidate)
		for _, record in ipairs(occupied) do
			local required =
				objectRadius
				+ record.Radius
				+ metrics.GapPixels

			if (candidate - record.Position).Magnitude < required then
				return false
			end
		end
		return true
	end

	if free(desired) then
		table.insert(occupied, {
			Position = desired,
			Radius = objectRadius,
		})
		return desired
	end

	-- Small spiral search around the true position.
	-- Uses the actual icon dimensions, so large icons naturally get more room.
	local step =
		math.max(
			metrics.GapPixels + objectRadius * 0.55,
			5
		)

	for ring = 1, 5 do
		local radius = step * ring
		local samples = 8 + ring * 4

		for sample = 1, samples do
			local angle =
				(sample - 1)
				/ samples
				* math.pi
				* 2

			local candidate =
				desired
				+ Vector2.new(
					math.cos(angle),
					math.sin(angle)
				)
				* radius

			candidate = clampPixelToMapCircle(
				candidate,
				objectRadius,
				metrics
			)

			if free(candidate) then
				table.insert(occupied, {
					Position = candidate,
					Radius = objectRadius,
				})
				return candidate
			end
		end
	end

	-- If the map is extremely crowded, keep the best truthful position.
	table.insert(occupied, {
		Position = desired,
		Radius = objectRadius,
	})

	return desired
end

local function pixelToParentPosition(
	absolutePixel,
	parent
)
	if not absolutePixel
		or not parent
		or not parent:IsA("GuiObject")
	then
		return nil
	end

	local localPixel =
		absolutePixel
		- parent.AbsolutePosition

	return UDim2.fromOffset(
		math.floor(localPixel.X + 0.5),
		math.floor(localPixel.Y + 0.5)
	)
end

local function withinVerticalMapSlice(
	worldPosition,
	playerRoot,
	metrics
)
	if not worldPosition or not playerRoot or not metrics then
		return false
	end

	return math.abs(
		worldPosition.Y - playerRoot.Position.Y
	) <= metrics.MaxHeightDifference
end

local function planarMapDirection(
	worldPosition,
	playerRoot
)
	local delta =
		worldPosition
		- playerRoot.Position

	-- FIXED NORTH-UP MAP:
	-- Roblox world north is -Z.
	-- The world never rotates with the player.
	return Vector2.new(
		delta.X,
		-delta.Z
	)
end

local function horizontalDistanceRatio(
	worldPosition,
	playerRoot,
	metrics
)
	if not worldPosition or not playerRoot or not metrics then
		return math.huge
	end

	return planarMapDirection(
		worldPosition,
		playerRoot
	).Magnitude / math.max(1, metrics.WorldRange)
end

local function islandScaleForDistance(
	worldPosition,
	playerRoot,
	metrics
)
	local ratio = horizontalDistanceRatio(
		worldPosition,
		playerRoot,
		metrics
	)

	local shrinkStart = math.clamp(
		tonumber(
			miniMap:GetAttribute("MapIslandShrinkStartRatio")
		) or 0.75,
		0.40,
		0.95
	)

	local minimumScale = math.clamp(
		tonumber(
			miniMap:GetAttribute("MapIslandMinimumScale")
		) or 0.70,
		0.40,
		1.00
	)

	if ratio <= shrinkStart then
		return 1
	end

	local progress = math.clamp(
		(ratio - shrinkStart)
			/ math.max(0.001, 1 - shrinkStart),
		0,
		1
	)

	return 1
		+ (minimumScale - 1)
			* progress
end

local function mapAbsolutePixel(
	worldPosition,
	playerRoot,
	object,
	occupied
)
	local metrics = minimapMetrics()
	if not metrics or not playerRoot then
		return nil
	end

	if not withinVerticalMapSlice(
		worldPosition,
		playerRoot,
		metrics
	) then
		return nil
	end

	local planar = planarMapDirection(
		worldPosition,
		playerRoot
	)

	local worldDistance = planar.Magnitude

	if worldDistance > metrics.WorldRange then
		return nil
	end

	if worldDistance <= 0.001 then
		return reserveReadablePosition(
			metrics.CenterAbsolute,
			object,
			metrics,
			occupied
		)
	end

	local normalizedDistance = math.clamp(
		worldDistance / metrics.WorldRange,
		0,
		1
	)

	-- Values below 1 spread close objects away from the center.
	-- 0.62 is intentionally readable without becoming exaggerated.
	local visualDistance =
		normalizedDistance ^ metrics.SpreadExponent

	local direction = planar.Unit

	-- UI Y grows downward; local forward should appear upward.
	local screenDirection =
		Vector2.new(
			direction.X,
			-direction.Y
		)

	local desired =
		metrics.CenterAbsolute
		+ screenDirection
			* metrics.RadiusPixels
			* visualDistance

	return reserveReadablePosition(
		desired,
		object,
		metrics,
		occupied
	)
end

local function markerIslandCenter(markerFolder)
	local island = markerFolder.Parent
	if not island then
		return nil, nil
	end

	local anchor = markerFolder:FindFirstChild(
		"ObjectiveAnchor",
		true
	)

	if anchor and anchor:IsA("BasePart") then
		return anchor.Position, island
	end

	if island:IsA("Model") then
		local floor =
			island:FindFirstChild("IslandFloor")
			or island.PrimaryPart

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
		island:GetAttribute("TerrainSize")
			or island:GetAttribute("IslandSize")
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
		local floor =
			island:FindFirstChild("IslandFloor")
			or island.PrimaryPart

		if floor and floor:IsA("BasePart") then
			local minimum =
				math.min(
					floor.Size.X,
					floor.Size.Z
				)

			if minimum < 72 then
				return smallIslandTemplate
			elseif minimum >= 108 then
				return largeIslandTemplate
			end
		end
	end

	return mediumIslandTemplate
end

local islandMarkerStateRefs =
	setmetatable({}, { __mode = "k" })

local function islandMarkerStateRefsFor(marker)
	local cached =
		islandMarkerStateRefs[marker]

	if cached then
		return cached
	end

	cached = {
		LevelText =
			findAuthored(
				marker,
				{
					"LevelText",
					"IslandLevelText",
					"RecommendedLevelText",
					"Level",
				},
				isText
			),

		CurrentIcon =
			findAuthored(
				marker,
				{
					"CurrentIslandIcon",
					"CurrentIcon",
					"PlayerIslandIcon",
				},
				isGui
			),

		UnclearedIcon =
			findAuthored(
				marker,
				{
					"UnclearedIcon",
					"NotClearedIcon",
					"IncompleteIcon",
					"PendingIcon",
				},
				isGui
			),

		MobsIcon =
			findAuthored(
				marker,
				{
					"MobsIcon",
					"MobAliveIcon",
					"EnemiesIcon",
					"EnemyIcon",
				},
				isGui
			),

		ClearedIcon =
			findAuthored(
				marker,
				{
					"ClearedIcon",
					"CompleteIcon",
					"CompletedIcon",
				},
				isGui
			),

		NextIslandIcon =
			findAuthored(
				marker,
				{
					"NextIslandIcon",
					"NextIcon",
					"AdvanceIcon",
					"GoHereIcon",
				},
				isGui
			),
	}

	islandMarkerStateRefs[marker] = cached

	return cached
end

local function updateIslandMarkerState(
	marker,
	island
)
	if not marker
		or not island
	then
		return
	end

	local index =
		math.floor(
			tonumber(
				island:GetAttribute(
					"GlobalIslandIndex"
				)
			) or 0
		)

	local islandLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					island:GetAttribute(
						"IslandLevel"
					)
				) or 1
			)
		)

	local recommendedLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					island:GetAttribute(
						"RecommendedLevel"
					)
				) or islandLevel
			)
		)

	local cleared =
		island:GetAttribute(
			"Cleared"
		) == true
			or island:GetAttribute(
				"CombatState"
			) == "Cleared"

	local mobsAlive =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute(
						"MobAliveCount"
					)
				) or 0
			)
		)

	local currentIndex =
		math.floor(
			tonumber(
				player:GetAttribute(
					"CurrentGlobalIslandIndex"
				)
			) or 0
		)

	local isCurrent =
		index > 0
			and index == currentIndex

	local advanceIndex =
		math.floor(
			tonumber(
				workspace:GetAttribute(
					"DungeonIslandAdvanceToIsland"
				)
			) or 0
		)

	local isAdvanceTarget =
		workspace:GetAttribute(
			"DungeonIslandAdvanceActive"
		) == true
			and index > 0
			and index == advanceIndex

	marker:SetAttribute(
		"RuntimeGlobalIslandIndex",
		index > 0 and index or nil
	)
	marker:SetAttribute(
		"RuntimeIslandLevel",
		islandLevel
	)
	marker:SetAttribute(
		"RuntimeRecommendedLevel",
		recommendedLevel
	)
	marker:SetAttribute(
		"RuntimeCleared",
		cleared
	)
	marker:SetAttribute(
		"RuntimeMobAliveCount",
		mobsAlive
	)
	marker:SetAttribute(
		"RuntimeCurrentIsland",
		isCurrent
	)
	marker:SetAttribute(
		"RuntimeAdvanceTarget",
		isAdvanceTarget
	)

	local refs =
		islandMarkerStateRefsFor(
			marker
		)

	if refs.LevelText then
		setText(
			refs.LevelText,
			tostring(
				recommendedLevel
			)
		)
	end

	if refs.CurrentIcon then
		refs.CurrentIcon.Visible =
			isCurrent
	end

	if refs.UnclearedIcon then
		refs.UnclearedIcon.Visible =
			not cleared
	end

	if refs.MobsIcon then
		refs.MobsIcon.Visible =
			not cleared
				and mobsAlive > 0
	end

	if refs.ClearedIcon then
		refs.ClearedIcon.Visible =
			cleared
	end

	if refs.NextIslandIcon then
		refs.NextIslandIcon.Visible =
			isAdvanceTarget
	end
end

local function updateIslands(playerRoot)
	if not islandContainer then
		return
	end

	local metrics = minimapMetrics()
	if not metrics then
		return
	end

	local seen = {}

	for _, folder in ipairs(
		CollectionService:GetTagged("DungeonGameplayMarkers")
	) do
		if folder:IsA("Folder") and folder.Parent then
			local worldPosition, island =
				markerIslandCenter(folder)

			if worldPosition and island then
				-- Filter BEFORE cloning:
				-- no UI object exists for islands outside the useful slice.
				local inVerticalSlice =
					withinVerticalMapSlice(
						worldPosition,
						playerRoot,
						metrics
					)

				local planar =
					planarMapDirection(
						worldPosition,
						playerRoot
					)

				local inHorizontalRange =
					planar.Magnitude <= metrics.WorldRange

				if inVerticalSlice and inHorizontalRange then
					seen[folder] = true

					local template =
						templateForIsland(island)

					if template then
						local marker =
							islandMarkers[folder]

						if not marker
							or not marker.Parent
							or marker:GetAttribute(
								"AuthoredTemplateName"
							) ~= template.Name
						then
							if marker then
								marker:Destroy()
							end

							marker =
								cloneAuthoredTemplate(
									template,
									"Island_" .. island.Name,
									islandContainer
								)

							if marker then
								marker:SetAttribute(
									"AuthoredTemplateName",
									template.Name
								)
								islandMarkers[folder] =
									marker
							end
						end

						if marker then
							updateIslandMarkerState(
								marker,
								island
							)

							-- 0-75%: exact authored size.
							-- 75-100%: smoothly shrinks to 70% by default.
							setRuntimeScale(
								marker,
								islandScaleForDistance(
									worldPosition,
									playerRoot,
									metrics
								)
							)

							local pixel =
								mapAbsolutePixel(
									worldPosition,
									playerRoot,
									marker,
									islandOccupied
								)

							marker.Visible =
								pixel ~= nil

							if pixel then
								local position =
									pixelToParentPosition(
										pixel,
										islandContainer
									)

								if position then
									marker.Position =
										position
								end
							end
						end
					end
				end
			end
		end
	end

	-- Outside the range = no icon object kept around.
	for source, marker in pairs(islandMarkers) do
		if not seen[source]
			or not source.Parent
		then
			marker:Destroy()
			islandMarkers[source] = nil
		end
	end
end

local function combatExitMarker(folder)
	if not folder
		or not folder.Parent
	then
		return nil
	end

	local exits =
		folder:FindFirstChild(
			"Exits",
			true
		)

	if exits then
		for _, child in ipairs(
			exits:GetChildren()
		) do
			if child:IsA("BasePart") then
				if child:GetAttribute(
					"ExitLocked"
				) == true
					or child:GetAttribute(
						"ObjectiveLocked"
					) == true
				then
					return child
				end
			end
		end

		for _, child in ipairs(
			exits:GetChildren()
		) do
			if child:IsA("BasePart") then
				return child
			end
		end
	end

	local direct =
		folder:FindFirstChild(
			"Exit",
			true
		)

	if direct
		and direct:IsA("BasePart")
	then
		return direct
	end

	return nil
end

local function updateGates(playerRoot)
	if not markerContainer
		or not roundGateTemplate
	then
		return
	end

	local seen = {}

	for _, folder in ipairs(
		CollectionService:GetTagged(
			"DungeonGameplayMarkers"
		)
	) do
		if folder:IsA("Folder")
			and folder.Parent
		then
			local island = folder.Parent

			local locked =
				island:GetAttribute(
					"CombatExitLocked"
				) == true
					or island:GetAttribute(
						"ObjectiveExitLocked"
					) == true

			if locked then
				local exitMarker =
					combatExitMarker(folder)

				if exitMarker then
					seen[island] = true

					local marker =
						gateMarkers[island]

					if not marker
						or not marker.Parent
					then
						marker =
							cloneAuthoredTemplate(
								roundGateTemplate,
								"CombatGate_"
									.. island.Name,
								markerContainer
							)

						gateMarkers[island] =
							marker
					end

					if marker then
						setRuntimeScale(
							marker,
							1
						)

						marker:SetAttribute(
							"RuntimeCombatGate",
							true
						)

						marker:SetAttribute(
							"RuntimeGlobalIslandIndex",
							island:GetAttribute(
								"GlobalIslandIndex"
							)
						)
					end

					local pixel =
						mapAbsolutePixel(
							exitMarker.Position,
							playerRoot,
							marker,
							markerOccupied
						)

					if marker then
						marker.Visible =
							pixel ~= nil

						if pixel then
							local position =
								pixelToParentPosition(
									pixel,
									markerContainer
								)

							if position then
								marker.Position =
									position
							end
						end
					end
				end
			end
		end
	end

	for island, marker in pairs(
		gateMarkers
	) do
		if not seen[island]
			or not island.Parent
		then
			marker:Destroy()
			gateMarkers[island] = nil
		end
	end
end

local function targetRoot(model)
	local root =
		model:FindFirstChild(
			"HumanoidRootPart",
			true
		)

	if root and root:IsA("BasePart") then
		return root
	end

	return model.PrimaryPart
		or model:FindFirstChildWhichIsA(
			"BasePart",
			true
		)
end

local function updateHostiles(playerRoot)
	if not markerContainer or not hostileMobTemplate then
		return
	end

	local metrics = minimapMetrics()
	if not metrics then
		return
	end

	local visibleRatio = math.clamp(
		tonumber(
			miniMap:GetAttribute("MapMobVisibleRangeRatio")
		) or 0.68,
		0.25,
		1.00
	)

	local maximumMobDistance =
		metrics.WorldRange * visibleRatio

	local seen = {}

	for _, target in ipairs(
		CollectionService:GetTagged("CombatTarget")
	) do
		if target:IsA("Model")
			and target.Parent
			and target:GetAttribute("Peaceful") ~= true
			and target:GetAttribute(
				"IslandCombatManaged"
			) == true
		then
			local humanoid =
				target:FindFirstChildWhichIsA(
					"Humanoid",
					true
				)

			local root = targetRoot(target)

			if root
				and (
					not humanoid
					or humanoid.Health > 0
				)
			then
				local inVerticalSlice =
					withinVerticalMapSlice(
						root.Position,
						playerRoot,
						metrics
					)

				local horizontalDistance =
					planarMapDirection(
						root.Position,
						playerRoot
					).Magnitude

				-- Distant mobs disappear completely instead of becoming tiny.
				-- Filtering happens BEFORE cloning an icon.
				local usefulDistance =
					inVerticalSlice
					and horizontalDistance
						<= maximumMobDistance

				if usefulDistance then
					seen[target] = true

					local marker =
						hostileMarkers[target]

					if not marker or not marker.Parent then
						marker =
							cloneAuthoredTemplate(
								hostileMobTemplate,
								"HostileMob",
								markerContainer
							)

						hostileMarkers[target] =
							marker
					end

					if marker then
						setRuntimeScale(marker, 1)

						local pixel =
							mapAbsolutePixel(
								root.Position,
								playerRoot,
								marker,
								markerOccupied
							)

						marker.Visible =
							pixel ~= nil

						if pixel then
							local position =
								pixelToParentPosition(
									pixel,
									markerContainer
								)

							if position then
								marker.Position =
									position
							end
						end
					end
				end
			end
		end
	end

	for target, marker in pairs(hostileMarkers) do
		if not seen[target]
			or not target.Parent
		then
			marker:Destroy()
			hostileMarkers[target] = nil
		end
	end
end

local function findObjectiveAnchor(snapshot)
	local globalIndex =
		snapshot
			and tonumber(
				snapshot.GlobalIslandIndex
			)

	if not globalIndex then
		return nil
	end

	local completed =
		tostring(
			snapshot.State or ""
		) == "Completed"

	for _, folder in ipairs(
		CollectionService:GetTagged(
			"DungeonGameplayMarkers"
		)
	) do
		if folder:IsA("Folder")
			and folder.Parent
		then
			local island = folder.Parent

			local index =
				tonumber(
					island:GetAttribute(
						"GlobalIslandIndex"
					)
				)
					or tonumber(
						folder:GetAttribute(
							"GlobalIslandIndex"
						)
					)

			if index == globalIndex then
				if completed then
					return combatExitMarker(
						folder
					)
				end

				local anchor =
					folder:FindFirstChild(
						"ObjectiveAnchor",
						true
					)

				if anchor
					and anchor:IsA("BasePart")
				then
					return anchor
				end

				local center =
					select(
						1,
						markerIslandCenter(
							folder
						)
					)

				if center then
					return {
						Position = center,
						Parent = folder,
					}
				end
			end
		end
	end

	return nil
end

local function updateObjectiveMarker(playerRoot)
	if not markerContainer
		or not objectiveMarkerTemplate
	then
		return
	end

	local anchor =
		currentObjective
		and findObjectiveAnchor(
			currentObjective
		)
		or nil

	if not anchor then
		if objectiveMarkerClone then
			objectiveMarkerClone.Visible = false
		end
		return
	end

	if not objectiveMarkerClone
		or not objectiveMarkerClone.Parent
	then
		objectiveMarkerClone =
			cloneAuthoredTemplate(
				objectiveMarkerTemplate,
				"CurrentObjectiveRuntime",
				markerContainer
			)
	end

	if objectiveMarkerClone then
		-- After a clear, the authored CurrentObjectiveMarker becomes the
		-- persistent "go this way" signal at the Exit.
		setRuntimeScale(
			objectiveMarkerClone,
			advanceMarkerScale()
		)

		objectiveMarkerClone:SetAttribute(
			"RuntimeAdvanceActive",
			workspace:GetAttribute(
				"DungeonIslandAdvanceActive"
			) == true
		)
		objectiveMarkerClone:SetAttribute(
			"RuntimeAdvanceToIsland",
			workspace:GetAttribute(
				"DungeonIslandAdvanceToIsland"
			)
		)

		local pixel =
			mapAbsolutePixel(
				anchor.Position,
				playerRoot,
				objectiveMarkerClone,
				markerOccupied
			)

		objectiveMarkerClone.Visible =
			pixel ~= nil

		if pixel then
			local position =
				pixelToParentPosition(
					pixel,
					markerContainer
				)

			if position then
				objectiveMarkerClone.Position =
					position
			end
		end
	end
end

local function updateNorthLabel(_playerRoot, metrics)
	if not northLabel
		or not northLabel.Parent
		or not metrics
	then
		return
	end

	-- North is always fixed at the top because the map itself never rotates.
	local northSize =
		approximateGuiSize(
			northLabel,
			metrics
		)

	local labelRadius =
		math.max(
			northSize.X,
			northSize.Y
		) * 0.5

	local northPixel =
		metrics.CenterAbsolute
		+ Vector2.new(
			0,
			-math.max(
				8,
				metrics.RadiusPixels
					- labelRadius
					- 2
			)
		)

	if northLabel.Parent:IsA("GuiObject") then
		local position =
			pixelToParentPosition(
				northPixel,
				northLabel.Parent
			)

		if position then
			northLabel.AnchorPoint =
				Vector2.new(0.5, 0.5)
			northLabel.Position =
				position
			northLabel.Rotation = 0
			northLabel.Visible = true
		end
	end
end

local function updatePlayerArrowRotation(playerRoot)
	if not playerArrow or not playerRoot then
		return
	end

	-- North (-Z) = 0°
	-- East  (+X) = +90°
	-- South (+Z) = 180°
	-- West  (-X) = -90°
	local look = playerRoot.CFrame.LookVector

	playerArrow.Rotation =
		math.deg(
			math.atan2(
				look.X,
				-look.Z
			)
		)
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
	local root =
		character
		and character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root or not root:IsA("BasePart") then
		return
	end

	local metrics = minimapMetrics()
	if not metrics then
		return
	end

	-- Fresh collision layout every visual update.
	table.clear(islandOccupied)
	table.clear(markerOccupied)

	-- Reserve the real player icon area so other markers do not cover it.
	if playerArrow then
		centerObjectInMap(
			playerArrow,
			metrics
		)

		updatePlayerArrowRotation(root)

		local arrowSize =
			approximateGuiSize(
				playerArrow,
				metrics
			)

		table.insert(markerOccupied, {
			Position = metrics.CenterAbsolute,
			Radius =
				math.max(
					arrowSize.X,
					arrowSize.Y
				) * 0.5,
		})
	end

	updateIslands(root)
	updateGates(root)
	updateHostiles(root)
	updateObjectiveMarker(root)
	updateNorthLabel(root, metrics)

	-- Useful live diagnostics without adding any visual debug UI.
	miniMap:SetAttribute(
		"RuntimeMapPixelWidth",
		math.floor(metrics.Size.X + 0.5)
	)
	miniMap:SetAttribute(
		"RuntimeMapPixelHeight",
		math.floor(metrics.Size.Y + 0.5)
	)
	miniMap:SetAttribute(
		"RuntimeMapRadiusPixels",
		math.floor(metrics.RadiusPixels + 0.5)
	)
	miniMap:SetAttribute(
		"RuntimeMapRangeStuds",
		math.floor(metrics.WorldRange + 0.5)
	)
	miniMap:SetAttribute(
		"RuntimeMapMaxHeightDifferenceStuds",
		math.floor(metrics.MaxHeightDifference + 0.5)
	)

	local visibleIslandCount = 0
	for _, marker in pairs(islandMarkers) do
		if marker
			and marker.Parent
			and marker.Visible
		then
			visibleIslandCount += 1
		end
	end
	miniMap:SetAttribute(
		"RuntimeVisibleIslandCount",
		visibleIslandCount
	)
	miniMap:SetAttribute(
		"RuntimeIslandShrinkStartRatio",
		math.clamp(
			tonumber(
				miniMap:GetAttribute("MapIslandShrinkStartRatio")
			) or 0.75,
			0.40,
			0.95
		)
	)
	miniMap:SetAttribute(
		"RuntimeIslandMinimumScale",
		math.clamp(
			tonumber(
				miniMap:GetAttribute("MapIslandMinimumScale")
			) or 0.70,
			0.40,
			1.00
		)
	)
	miniMap:SetAttribute(
		"RuntimeMobVisibleRangeRatio",
		math.clamp(
			tonumber(
				miniMap:GetAttribute("MapMobVisibleRangeRatio")
			) or 0.68,
			0.25,
			1.00
		)
	)
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

local function renderMissions(_snapshot)
	if not missionsPanel then
		return
	end

	-- MVP simplificado:
	-- ObjectivePanel is the single objective surface.
	-- The old Missions/Round list would duplicate information and reintroduce
	-- obsolete Round language. Keep the designer-authored panel untouched but
	-- hidden until a later mission system genuinely needs it.
	clearMissionRows()
	missionsPanel.Visible = false
	missionsPanel:SetAttribute(
		"RuntimeDisabledReason",
		"SimplifiedCombatMVP"
	)
end

if collapseButton and missionList then
	collapseButton.Activated:Connect(function()
		if missionsPanel
			and missionsPanel.Visible
		then
			missionsCollapsed =
				not missionsCollapsed
			missionList.Visible =
				not missionsCollapsed
		end
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
	"DungeonLinearRouteComplete",
	"DungeonCurrentObjectiveIsland",
	"DungeonHighestUnlockedCombatIsland",
	"DungeonIslandAdvanceActive",
	"DungeonIslandAdvanceToIsland",
	"DungeonIslandClearFeedbackSerial",
}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(function()
		dispatchObjective(readObjective())
	end)
end

workspace:GetAttributeChangedSignal(
	"DungeonIslandClearFeedbackSerial"
):Connect(function()
	updateIslandClearFeedbackSerial()
end)

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
		if workspace:GetAttribute(
			"DungeonRouteProgressionAuthority"
		) == "CombatRouteProgressionService"
		then
			-- Task 09 publishes the authoritative simplified objective through
			-- Workspace Attributes. Ignore legacy ObjectiveService snapshots.
			return
		end

		if type(payload) == "table"
			and payload.Action
				== "ObjectiveSnapshot"
		then
			dispatchObjective(
				payload.Objective
			)
		end
	end)
end)

dispatchObjective(readObjective())

player:SetAttribute(
	"DungeonArtHUDBindingVersion",
	"NewCoreV1"
)
player:SetAttribute(
	"DungeonArtHUDPlayerProgressionSource",
	"PlayerLevelService"
)
player:SetAttribute(
	"DungeonArtHUDObjectiveSource",
	"CombatRouteProgressionService"
)
player:SetAttribute(
	"DungeonArtHUDMinimapMobPolicy",
	"IslandCombatManagedOnly"
)
player:SetAttribute(
	"DungeonIslandAdvanceFeedbackVersion",
	IslandAdvanceFeedbackConfig.Version
)
player:SetAttribute(
	"DungeonIslandAdvanceFeedbackCreatesVisuals",
	false
)

player:SetAttribute("DungeonArtHUDControllerReady", true)
player:SetAttribute("DungeonArtHUDMode", "AuthoredOnlyV12NewCore")
player:SetAttribute("DungeonArtHUDCreatesVisuals", false)

if hud then
	hud:SetAttribute("ControllerReady", true)
end

print("[AuthoredHUD] V12 NewCore ready. Studio desenha; controller apenas controla.")
