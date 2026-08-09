--!strict
-- DungeonArtHUDController.client.luau
--
-- Controla o HUD artesanal criado no Roblox Studio.
-- Se algum elemento esperado nao existir, cria um fallback funcional.
--
-- Estrutura suportada:
--
-- DungeonHUD [ScreenGui]
-- ├── ObjectivePanel
-- ├── PlayerStatus
-- ├── Minimap
-- └── MissionsPanel
--
-- Coloque este arquivo em:
-- StarterPlayer > StarterPlayerScripts
-- ou, no projeto Rojo: src/client/DungeonArtHUDController.client.luau

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUD_NAME = "DungeonHUD"
local OBJECTIVE_DESCRIPTION_MAX = 43
local OBJECTIVE_MAX_WIDTH = 276
local MINIMAP_RANGE = 420
local MINIMAP_UPDATE_INTERVAL = 0.10
local ROUND_LENGTHS = { 3, 4, 5 }

local COLORS = {
	Panel = Color3.fromRGB(12, 31, 51),
	Panel2 = Color3.fromRGB(20, 48, 75),
	Border = Color3.fromRGB(221, 187, 104),
	Text = Color3.fromRGB(244, 249, 255),
	Muted = Color3.fromRGB(171, 201, 222),
	Health = Color3.fromRGB(222, 55, 75),
	Stamina = Color3.fromRGB(43, 149, 238),
	XP = Color3.fromRGB(238, 192, 88),
	Objective = Color3.fromRGB(107, 221, 255),
	Success = Color3.fromRGB(93, 230, 154),
	Danger = Color3.fromRGB(255, 88, 99),
	Island = Color3.fromRGB(94, 149, 116),
}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function textObject(instance: Instance?): boolean
	return instance ~= nil
		and (
			instance:IsA("TextLabel")
			or instance:IsA("TextButton")
			or instance:IsA("TextBox")
		)
end

local function setText(instance: Instance?, value: any)
	if textObject(instance) then
		(instance :: any).Text = tostring(value or "")
	end
end

local function truncateUtf8(value: any, maximum: number): string
	local text = tostring(value or "")
	local ok, length = pcall(utf8.len, text)
	if not ok or not length or length <= maximum then
		return text
	end

	local byteIndex = utf8.offset(text, maximum + 1)
	if not byteIndex then
		return text
	end

	return string.sub(text, 1, byteIndex - 1)
end

local function findGui(parent: Instance, name: string): GuiObject?
	local object = parent:FindFirstChild(name)
	if object and object:IsA("GuiObject") then
		return object
	end
	return nil
end

local function ensureFrame(
	parent: Instance,
	name: string,
	properties: { [string]: any }?
): GuiObject
	local object = findGui(parent, name)
	if not object then
		object = Instance.new("Frame")
		object.Name = name
		object.BackgroundTransparency = 1
		object.BorderSizePixel = 0
		object.Parent = parent
	end

	for key, value in pairs(properties or {}) do
		pcall(function()
			(object :: any)[key] = value
		end)
	end

	return object
end

local function ensureImage(
	parent: Instance,
	name: string,
	properties: { [string]: any }?
): GuiObject
	local object = findGui(parent, name)
	if not object then
		local image = Instance.new("ImageLabel")
		image.Name = name
		image.BackgroundTransparency = 1
		image.BorderSizePixel = 0
		image.Parent = parent
		object = image
	end

	for key, value in pairs(properties or {}) do
		pcall(function()
			(object :: any)[key] = value
		end)
	end

	return object
end

local function ensureLabel(
	parent: Instance,
	name: string,
	defaultText: string,
	properties: { [string]: any }?
): GuiObject
	local object = parent:FindFirstChild(name)

	if not textObject(object) then
		if object then
			object.Name = name .. "_Art"
		end

		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamMedium
		label.TextColor3 = COLORS.Text
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Text = defaultText
		label.Parent = parent
		object = label
	elseif (object :: any).Text == "" then
		(object :: any).Text = defaultText
	end

	for key, value in pairs(properties or {}) do
		pcall(function()
			(object :: any)[key] = value
		end)
	end

	return object :: GuiObject
end

local function ensureCorner(parent: GuiObject, radius: number)
	local corner = parent:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = parent
	end
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function ensureStroke(
	parent: GuiObject,
	color: Color3,
	transparency: number?,
	thickness: number?
)
	local stroke = parent:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end
	stroke.Color = color
	stroke.Transparency = transparency or 0.2
	stroke.Thickness = thickness or 1.5
	return stroke
end

local function ensureAspect(parent: GuiObject)
	local aspect = parent:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not aspect then
		aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = parent
	end
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	return aspect
end

local function ensureScale(parent: GuiObject): UIScale
	local scale = parent:FindFirstChild("HUDAnimationScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end

	if scale then
		scale:Destroy()
	end

	local created = Instance.new("UIScale")
	created.Name = "HUDAnimationScale"
	created.Scale = 1
	created.Parent = parent
	return created
end

local activeTweens = setmetatable({}, { __mode = "k" })

local function playTween(
	instance: Instance,
	info: TweenInfo,
	properties: { [string]: any }
): Tween
	local previous = activeTweens[instance]
	if previous then
		previous:Cancel()
	end

	local current = TweenService:Create(instance, info, properties)
	activeTweens[instance] = current

	current.Completed:Connect(function()
		if activeTweens[instance] == current then
			activeTweens[instance] = nil
		end
	end)

	current:Play()
	return current
end

local popSerials = setmetatable({}, { __mode = "k" })

local function pop(object: GuiObject, scaleAmount: number?, duration: number?)
	local uiScale = ensureScale(object)
	local serial = (popSerials[object] or 0) + 1
	popSerials[object] = serial

	local amount = scaleAmount or 0.10
	local halfDuration = duration or 0.10

	uiScale.Scale = 1
	playTween(
		uiScale,
		TweenInfo.new(halfDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1 + amount }
	)

	task.delay(halfDuration, function()
		if popSerials[object] ~= serial or not uiScale.Parent then
			return
		end

		playTween(
			uiScale,
			TweenInfo.new(halfDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Scale = 1 }
		)
	end)
end

local function ensureGlyph(
	parent: GuiObject,
	glyph: string,
	color: Color3
): GuiObject?
	if parent:IsA("ImageLabel") or parent:IsA("ImageButton") then
		if parent.Image ~= "" then
			local fallback = parent:FindFirstChild("FallbackGlyph")
			if fallback and fallback:IsA("GuiObject") then
				fallback.Visible = false
			end
			return fallback :: GuiObject?
		end
	end

	local fallback = ensureLabel(parent, "FallbackGlyph", glyph, {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = color,
		ZIndex = parent.ZIndex + 1,
	})
	setText(fallback, glyph)
	fallback.Visible = true
	return fallback
end

---------------------------------------------------------------------
-- DungeonHUD
---------------------------------------------------------------------

local hud = playerGui:FindFirstChild(HUD_NAME)

if not hud or not hud:IsA("ScreenGui") then
	if hud then
		hud:Destroy()
	end

	local newHud = Instance.new("ScreenGui")
	newHud.Name = HUD_NAME
	newHud.ResetOnSpawn = false
	newHud.IgnoreGuiInset = false
	newHud.DisplayOrder = 55
	newHud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	newHud.Parent = playerGui
	hud = newHud

	warn(
		"[DungeonArtHUD] DungeonHUD nao foi encontrado no StarterGui. "
			.. "Um HUD fallback foi criado em runtime."
	)
end

local dungeonHud = hud :: ScreenGui
dungeonHud.ResetOnSpawn = false
dungeonHud.Enabled = true
dungeonHud:SetAttribute("ControllerVersion", "ArtHUDV1")
dungeonHud:SetAttribute("ControllerReady", false)

---------------------------------------------------------------------
-- Hide only the old visual panels we are replacing.
-- The rest of DungeonUnifiedHUD remains alive.
---------------------------------------------------------------------

local function suppressOldPanels(candidate: Instance?)
	if not candidate
		or candidate.Name ~= "DungeonUnifiedHUD"
		or not candidate:IsA("ScreenGui")
	then
		return
	end

	task.defer(function()
		if not candidate.Parent then
			return
		end

		local root = candidate:FindFirstChild("Root")
			or candidate:WaitForChild("Root", 8)

		if not root then
			return
		end

		for _, name in ipairs({ "Objective", "Vitals" }) do
			local panel = root:FindFirstChild(name)
			if panel and panel:IsA("GuiObject") then
				panel.Visible = false
				panel:SetAttribute("ReplacedByDungeonArtHUD", true)
			end
		end
	end)
end

suppressOldPanels(playerGui:FindFirstChild("DungeonUnifiedHUD"))
playerGui.ChildAdded:Connect(suppressOldPanels)

---------------------------------------------------------------------
-- ObjectivePanel
---------------------------------------------------------------------

type ObjectiveUI = {
	Panel: GuiObject,
	Title: GuiObject,
	Description: GuiObject,
	Counter: GuiObject,
	ProgressBackground: GuiObject,
	ProgressFill: GuiObject,
	CompletedIcon: GuiObject,
	TargetPosition: UDim2,
	LastId: any,
	LastProgress: number?,
	LastState: string?,
}

local function buildObjectiveUI(): ObjectiveUI
	local panel = findGui(dungeonHud, "ObjectivePanel")

	if not panel then
		panel = ensureFrame(dungeonHud, "ObjectivePanel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 22),
			Size = UDim2.fromOffset(340, 116),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.18,
			ZIndex = 20,
		})
		ensureCorner(panel, 10)
		ensureStroke(panel, COLORS.Border, 0.15, 2)
	end

	local title = ensureLabel(panel, "Title", "Objetivo", {
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.new(1, -36, 0, 22),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = COLORS.Muted,
		ZIndex = panel.ZIndex + 2,
	})

	local description = ensureLabel(panel, "Description", "Explore a ilha", {
		Position = UDim2.fromOffset(18, 31),
		Size = UDim2.new(1, -36, 0, 28),
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextColor3 = COLORS.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = panel.ZIndex + 2,
	})

	local counter = ensureLabel(panel, "Counter", "0 / 3", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 63),
		Size = UDim2.fromOffset(76, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = panel.ZIndex + 3,
	})

	local progressBackground = findGui(panel, "ProgressBackground")
	if not progressBackground then
		progressBackground = ensureFrame(panel, "ProgressBackground", {
			Position = UDim2.fromOffset(18, 88),
			Size = UDim2.fromOffset(OBJECTIVE_MAX_WIDTH, 12),
			BackgroundColor3 = Color3.fromRGB(7, 19, 31),
			BackgroundTransparency = 0.10,
			ZIndex = panel.ZIndex + 1,
		})
		ensureCorner(progressBackground, 4)
	end

	local progressFill = findGui(progressBackground, "ProgressFill")
	if not progressFill then
		progressFill = ensureFrame(progressBackground, "ProgressFill", {
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = COLORS.Objective,
			BackgroundTransparency = 0,
			ZIndex = progressBackground.ZIndex + 1,
		})
		ensureCorner(progressFill, 4)
	end

	local completedIcon = findGui(panel, "CompletedIcon")
	if not completedIcon then
		completedIcon = ensureImage(panel, "CompletedIcon", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -24, 0, 22),
			Size = UDim2.fromOffset(26, 26),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = panel.ZIndex + 4,
		})
	end
	ensureGlyph(completedIcon, "✓", COLORS.Success)

	setText(title, "Objetivo")

	return {
		Panel = panel,
		Title = title,
		Description = description,
		Counter = counter,
		ProgressBackground = progressBackground,
		ProgressFill = progressFill,
		CompletedIcon = completedIcon,
		TargetPosition = panel.Position,
		LastId = nil,
		LastProgress = nil,
		LastState = nil,
	}
end

local objectiveUI = buildObjectiveUI()

type ObjectiveSnapshot = {
	State: string?,
	Id: string?,
	Title: string?,
	Description: string?,
	RoundIndex: number?,
	IslandIndex: number?,
	GlobalIslandIndex: number?,
	Progress: number?,
	Target: number?,
	WaypointEscalated: boolean?,
	ExitLocked: boolean?,
}

local currentObjective: ObjectiveSnapshot? = nil

local function objectiveFillWidth(): number
	local width = objectiveUI.ProgressBackground.Size.X

	-- User explicitly designed the full bar at X=276.
	-- If the art uses a different positive pixel width, respect it.
	if width.Offset > 0 then
		return width.Offset
	end

	return OBJECTIVE_MAX_WIDTH
end

local function animateObjectiveProgress(current: number, required: number)
	local target = math.max(1, required)
	local ratio = math.clamp(current / target, 0, 1)
	local width = objectiveFillWidth()
	local y = objectiveUI.ProgressFill.Size.Y

	if y.Scale == 0 and y.Offset == 0 then
		y = UDim.new(1, 0)
	end

	playTween(
		objectiveUI.ProgressFill,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = UDim2.new(
				0,
				math.floor(width * ratio + 0.5),
				y.Scale,
				y.Offset
			),
		}
	)
end

local function animateObjectiveEntry()
	local panel = objectiveUI.Panel
	local target = objectiveUI.TargetPosition
	local animationScale = ensureScale(panel)

	panel.Visible = true
	panel.Position = UDim2.new(
		target.X.Scale,
		target.X.Offset,
		target.Y.Scale,
		target.Y.Offset - 12
	)
	animationScale.Scale = 0.96

	playTween(
		panel,
		TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = target }
	)

	playTween(
		animationScale,
		TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
end

local function renderObjective(snapshot: ObjectiveSnapshot?)
	snapshot = snapshot or {}
	currentObjective = snapshot

	local state = tostring(snapshot.State or "Inactive")
	local active = state == "Active" or state == "Completed"

	objectiveUI.Panel.Visible = active

	if not active then
		objectiveUI.LastState = state
		return
	end

	local progress = math.max(0, math.floor(tonumber(snapshot.Progress) or 0))
	local target = math.max(1, math.floor(tonumber(snapshot.Target) or 1))

	setText(objectiveUI.Title, "Objetivo")

	-- Prefer Title: it is short and action-oriented in ObjectiveCatalog.
	local objectiveText = snapshot.Title
		or snapshot.Description
		or "Explore a ilha"

	setText(
		objectiveUI.Description,
		truncateUtf8(objectiveText, OBJECTIVE_DESCRIPTION_MAX)
	)

	setText(
		objectiveUI.Counter,
		string.format("%d / %d", progress, target)
	)

	animateObjectiveProgress(progress, target)

	if objectiveUI.LastId ~= snapshot.Id then
		objectiveUI.LastId = snapshot.Id
		objectiveUI.LastProgress = progress
		objectiveUI.CompletedIcon.Visible = false
		animateObjectiveEntry()
	elseif objectiveUI.LastProgress ~= nil
		and objectiveUI.LastProgress ~= progress
	then
		pop(objectiveUI.Counter, 0.12, 0.08)
	end

	objectiveUI.LastProgress = progress
	objectiveUI.LastState = state

	if state == "Completed" then
		objectiveUI.CompletedIcon.Visible = true
		pop(objectiveUI.CompletedIcon, 0.28, 0.11)
		pop(objectiveUI.Panel, 0.025, 0.10)
	else
		objectiveUI.CompletedIcon.Visible = false
	end
end

local function readObjectiveFromWorkspace(): ObjectiveSnapshot
	return {
		State = workspace:GetAttribute("DungeonObjectiveState") or "Inactive",
		Id = workspace:GetAttribute("DungeonObjectiveId"),
		Title = workspace:GetAttribute("DungeonObjectiveTitle"),
		Description = workspace:GetAttribute("DungeonObjectiveDescription"),
		RoundIndex = workspace:GetAttribute("DungeonObjectiveRoundIndex"),
		IslandIndex = workspace:GetAttribute("DungeonObjectiveIslandIndex"),
		GlobalIslandIndex = workspace:GetAttribute(
			"DungeonObjectiveGlobalIslandIndex"
		),
		Progress = workspace:GetAttribute("DungeonObjectiveProgress") or 0,
		Target = workspace:GetAttribute("DungeonObjectiveTarget") or 1,
		WaypointEscalated = workspace:GetAttribute(
			"DungeonObjectiveWaypointEscalated"
		) == true,
		ExitLocked = workspace:GetAttribute(
			"DungeonObjectiveExitLocked"
		) == true,
	}
end

---------------------------------------------------------------------
-- PlayerStatus
---------------------------------------------------------------------

type BarUI = {
	Root: GuiObject,
	Background: GuiObject,
	Fill: GuiObject,
	Border: GuiObject,
	Value: GuiObject,
	FullSize: UDim2,
}

local function buildBar(
	parent: GuiObject,
	name: string,
	color: Color3,
	fallbackY: number
): BarUI
	local root = findGui(parent, name)

	if not root then
		root = ensureFrame(parent, name, {
			Position = UDim2.fromOffset(126, fallbackY),
			Size = UDim2.fromOffset(300, 22),
			BackgroundTransparency = 1,
		})
	end

	local background = findGui(root, "Background")
	if not background then
		background = ensureImage(root, "Background", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = Color3.fromRGB(8, 18, 29),
			BackgroundTransparency = 0.10,
			ZIndex = root.ZIndex + 1,
		})
		ensureCorner(background, 5)
	end

	local fill = findGui(root, "Fill")
	if not fill then
		fill = ensureImage(root, "Fill", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			ZIndex = root.ZIndex + 2,
		})
		ensureCorner(fill, 5)
	end

	local border = findGui(root, "Border")
	if not border then
		border = ensureImage(root, "Border", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundTransparency = 1,
			ZIndex = root.ZIndex + 3,
		})
	end

	if border:IsA("ImageLabel") and border.Image == "" then
		ensureStroke(root, COLORS.Border, 0.35, 1)
	end

	local value = ensureLabel(root, "Value", "100 / 100", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		ZIndex = root.ZIndex + 4,
	})

	return {
		Root = root,
		Background = background,
		Fill = fill,
		Border = border,
		Value = value,
		FullSize = fill.Size,
	}
end

type PlayerStatusUI = {
	Panel: GuiObject,
	AvatarImage: GuiObject,
	PlayerName: GuiObject,
	LevelBadge: GuiObject,
	LevelText: GuiObject,
	Health: BarUI,
	Stamina: BarUI,
	XP: BarUI,
}

local function buildPlayerStatus(): PlayerStatusUI
	local panel = findGui(dungeonHud, "PlayerStatus")

	if not panel then
		panel = ensureFrame(dungeonHud, "PlayerStatus", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 22, 1, -20),
			Size = UDim2.fromOffset(460, 132),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.18,
			ZIndex = 20,
		})
		ensureCorner(panel, 12)
		ensureStroke(panel, COLORS.Border, 0.16, 2)
	end

	ensureImage(panel, "Background", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		ZIndex = panel.ZIndex,
	})

	local portrait = findGui(panel, "Portrait")
	if not portrait then
		portrait = ensureFrame(panel, "Portrait", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(112, 112),
			BackgroundTransparency = 1,
			ZIndex = panel.ZIndex + 2,
		})
	end
	ensureAspect(portrait)

	local portraitBackground = findGui(portrait, "PortraitBackground")
	if not portraitBackground then
		portraitBackground = ensureImage(portrait, "PortraitBackground", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = COLORS.Panel2,
			BackgroundTransparency = 0.05,
			ZIndex = portrait.ZIndex,
		})
		ensureCorner(portraitBackground, 56)
	end

	local avatarImage = findGui(portrait, "AvatarImage")
	if not avatarImage then
		avatarImage = ensureImage(portrait, "AvatarImage", {
			Position = UDim2.fromOffset(5, 5),
			Size = UDim2.new(1, -10, 1, -10),
			BackgroundTransparency = 1,
			ZIndex = portrait.ZIndex + 1,
		})
		ensureCorner(avatarImage, 52)
	end

	local portraitBorder = findGui(portrait, "PortraitBorder")
	if not portraitBorder then
		portraitBorder = ensureImage(portrait, "PortraitBorder", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = portrait.ZIndex + 3,
		})
	end
	if portraitBorder:IsA("ImageLabel")
		and portraitBorder.Image == ""
	then
		ensureStroke(portrait, COLORS.Border, 0.10, 2)
	end

	local levelBadge = findGui(portrait, "LevelBadge")
	if not levelBadge then
		levelBadge = ensureFrame(portrait, "LevelBadge", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, -2, 1, 4),
			Size = UDim2.fromOffset(42, 42),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.05,
			ZIndex = portrait.ZIndex + 5,
		})
		ensureCorner(levelBadge, 21)
		ensureStroke(levelBadge, COLORS.Border, 0.08, 2)
	end
	ensureAspect(levelBadge)

	ensureImage(levelBadge, "BadgeBackground", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = levelBadge.ZIndex,
	})

	local levelText = ensureLabel(levelBadge, "LevelText", "1", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = levelBadge.ZIndex + 2,
	})

	local playerName = ensureLabel(panel, "PlayerName", player.DisplayName, {
		Position = UDim2.fromOffset(126, 5),
		Size = UDim2.new(1, -140, 0, 25),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		ZIndex = panel.ZIndex + 4,
	})

	return {
		Panel = panel,
		AvatarImage = avatarImage,
		PlayerName = playerName,
		LevelBadge = levelBadge,
		LevelText = levelText,
		Health = buildBar(panel, "HealthBar", COLORS.Health, 34),
		Stamina = buildBar(panel, "StaminaBar", COLORS.Stamina, 62),
		XP = buildBar(panel, "XPBar", COLORS.XP, 90),
	}
end

local playerStatus = buildPlayerStatus()
setText(playerStatus.PlayerName, player.DisplayName)

local barTweens = setmetatable({}, { __mode = "k" })

local function setBar(bar: BarUI, ratio: number, text: string)
	ratio = math.clamp(ratio, 0, 1)
	setText(bar.Value, text)

	local full = bar.FullSize
	if full.X.Scale == 0 and full.X.Offset == 0 then
		full = UDim2.new(1, 0, full.Y.Scale, full.Y.Offset)
		bar.FullSize = full
	end

	local target = UDim2.new(
		full.X.Scale * ratio,
		math.floor(full.X.Offset * ratio + 0.5),
		full.Y.Scale,
		full.Y.Offset
	)

	local previous = barTweens[bar.Fill]
	if previous then
		previous:Cancel()
	end

	local current = TweenService:Create(
		bar.Fill,
		TweenInfo.new(
			0.18,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{ Size = target }
	)

	barTweens[bar.Fill] = current
	current:Play()
end

local currentCharacter: Model? = nil
local currentHumanoid: Humanoid? = nil
local characterConnections: { RBXScriptConnection } = {}

local function clearCharacterConnections()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function updateHealth()
	local humanoid = currentHumanoid

	if not humanoid or not humanoid.Parent then
		setBar(playerStatus.Health, 0, "0 / 0")
		return
	end

	local maximum = math.max(1, humanoid.MaxHealth)
	local current = math.max(0, humanoid.Health)

	setBar(
		playerStatus.Health,
		current / maximum,
		string.format(
			"%d / %d",
			math.floor(current + 0.5),
			math.floor(maximum + 0.5)
		)
	)
end

local function updateStamina()
	local character = currentCharacter

	if not character or not character.Parent then
		setBar(playerStatus.Stamina, 1, "-- / --")
		return
	end

	local maximum = tonumber(character:GetAttribute("SprintStaminaMax"))
	local current = tonumber(character:GetAttribute("SprintStamina"))

	if not maximum or maximum <= 0 or current == nil then
		setBar(playerStatus.Stamina, 1, "-- / --")
		return
	end

	setBar(
		playerStatus.Stamina,
		current / maximum,
		string.format("%.1f / %.1f", math.max(0, current), maximum)
	)
end

local lastRunLevel = math.max(
	1,
	math.floor(tonumber(player:GetAttribute("RunLevel")) or 1)
)

local function updateRunLevel()
	local level = math.max(
		1,
		math.floor(tonumber(player:GetAttribute("RunLevel")) or 1)
	)
	local distance = math.max(
		0,
		tonumber(player:GetAttribute("RunDistance")) or 0
	)
	local levelStart = math.max(
		0,
		tonumber(player:GetAttribute("RunLevelStartDistance")) or 0
	)
	local levelEnd = math.max(
		levelStart + 1,
		tonumber(player:GetAttribute("RunLevelEndDistance"))
			or levelStart + 1
	)

	local currentWithinLevel = math.max(0, distance - levelStart)
	local requiredWithinLevel = math.max(1, levelEnd - levelStart)

	setText(playerStatus.LevelText, level)

	-- There is no separate XP resource in the current dungeon runtime.
	-- This third bar visualizes the existing RunLevel progress.
	setBar(
		playerStatus.XP,
		currentWithinLevel / requiredWithinLevel,
		string.format(
			"%d / %d XP",
			math.floor(currentWithinLevel + 0.5),
			math.floor(requiredWithinLevel + 0.5)
		)
	)

	if level > lastRunLevel then
		pop(playerStatus.LevelBadge, 0.25, 0.11)
	end

	lastRunLevel = level
end

local function bindCharacter(character: Model)
	clearCharacterConnections()

	currentCharacter = character
	currentHumanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?

	if currentHumanoid then
		table.insert(
			characterConnections,
			currentHumanoid.HealthChanged:Connect(updateHealth)
		)
		table.insert(
			characterConnections,
			currentHumanoid:GetPropertyChangedSignal(
				"MaxHealth"
			):Connect(updateHealth)
		)
	end

	for _, attributeName in ipairs({
		"SprintStamina",
		"SprintStaminaMax",
		"Sprinting",
	}) do
		table.insert(
			characterConnections,
			character:GetAttributeChangedSignal(
				attributeName
			):Connect(updateStamina)
		)
	end

	updateHealth()
	updateStamina()
end

player.CharacterAdded:Connect(bindCharacter)

if player.Character then
	task.spawn(bindCharacter, player.Character)
end

for _, attributeName in ipairs({
	"RunLevel",
	"RunDistance",
	"RunLevelStartDistance",
	"RunLevelEndDistance",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(updateRunLevel)
end

task.spawn(function()
	local ok, image = pcall(
		Players.GetUserThumbnailAsync,
		Players,
		player.UserId,
		Enum.ThumbnailType.HeadShot,
		Enum.ThumbnailSize.Size150x150
	)

	if ok
		and playerStatus.AvatarImage.Parent
		and (
			playerStatus.AvatarImage:IsA("ImageLabel")
			or playerStatus.AvatarImage:IsA("ImageButton")
		)
	then
		playerStatus.AvatarImage.Image = image
	end
end)

updateRunLevel()

---------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------

type MinimapUI = {
	Root: GuiObject,
	MapArea: GuiObject,
	IslandContainer: GuiObject,
	MarkerContainer: GuiObject,
	SmallIslandTemplate: GuiObject,
	MediumIslandTemplate: GuiObject,
	LargeIslandTemplate: GuiObject,
	RoundGateMarker: GuiObject,
	HostileMobMarker: GuiObject,
	CurrentObjectiveMarker: GuiObject,
	PlayerArrow: GuiObject,
}

local function prepareTemplate(
	template: GuiObject,
	glyph: string,
	color: Color3
): GuiObject
	template.Visible = false
	template.BackgroundTransparency = 1
	template.AnchorPoint = Vector2.new(0.5, 0.5)
	ensureAspect(template)
	ensureGlyph(template, glyph, color)
	return template
end

local function buildMinimap(): MinimapUI
	local minimap = findGui(dungeonHud, "Minimap")

	if not minimap then
		minimap = ensureFrame(dungeonHud, "Minimap", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -22, 0, 22),
			Size = UDim2.fromOffset(220, 220),
			BackgroundTransparency = 1,
			ZIndex = 20,
		})
	end
	ensureAspect(minimap)

	ensureImage(minimap, "Shadow", {
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.72,
		ZIndex = minimap.ZIndex,
	})

	local background = findGui(minimap, "Background")
	if not background then
		background = ensureImage(minimap, "Background", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(13, 45, 76),
			BackgroundTransparency = 0.10,
			ZIndex = minimap.ZIndex + 1,
		})
		ensureCorner(background, 110)
	end

	local mapArea = findGui(minimap, "MapArea")
	if not mapArea then
		mapArea = ensureFrame(minimap, "MapArea", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -16, 1, -16),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = minimap.ZIndex + 2,
		})
	end

	mapArea.BackgroundTransparency = 1
	mapArea.ClipsDescendants = true

	local mapCorner = mapArea:FindFirstChildOfClass("UICorner")
	if not mapCorner then
		mapCorner = Instance.new("UICorner")
		mapCorner.Parent = mapArea
	end
	mapCorner.CornerRadius = UDim.new(1, 0)

	local islandContainer = findGui(mapArea, "IslandContainer")
		or ensureFrame(mapArea, "IslandContainer", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = mapArea.ZIndex + 1,
		})

	local small = findGui(islandContainer, "SmallIslandTemplate")
		or ensureImage(
			islandContainer,
			"SmallIslandTemplate",
			{
				Size = UDim2.fromOffset(20, 20),
				ZIndex = islandContainer.ZIndex + 1,
			}
		)

	local medium = findGui(islandContainer, "MediumIslandTemplate")
		or ensureImage(
			islandContainer,
			"MediumIslandTemplate",
			{
				Size = UDim2.fromOffset(28, 28),
				ZIndex = islandContainer.ZIndex + 1,
			}
		)

	local large = findGui(islandContainer, "LargeIslandTemplate")
		or ensureImage(
			islandContainer,
			"LargeIslandTemplate",
			{
				Size = UDim2.fromOffset(36, 36),
				ZIndex = islandContainer.ZIndex + 1,
			}
		)

	prepareTemplate(small, "•", COLORS.Island)
	prepareTemplate(medium, "◆", COLORS.Island)
	prepareTemplate(large, "◆", COLORS.Island)

	local markerContainer = findGui(mapArea, "MarkerContainer")
		or ensureFrame(mapArea, "MarkerContainer", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = mapArea.ZIndex + 4,
		})

	local roundGate = findGui(markerContainer, "RoundGateMarker")
		or ensureImage(markerContainer, "RoundGateMarker", {
			Size = UDim2.fromOffset(20, 20),
			ZIndex = markerContainer.ZIndex + 1,
		})
	prepareTemplate(roundGate, "◆", COLORS.XP)

	local hostile = findGui(markerContainer, "HostileMobMarker")
		or ensureImage(markerContainer, "HostileMobMarker", {
			Size = UDim2.fromOffset(10, 10),
			ZIndex = markerContainer.ZIndex + 2,
		})
	prepareTemplate(hostile, "●", COLORS.Danger)

	local currentObjectiveMarker = findGui(
		markerContainer,
		"CurrentObjectiveMarker"
	) or ensureImage(markerContainer, "CurrentObjectiveMarker", {
		Size = UDim2.fromOffset(24, 24),
		ZIndex = markerContainer.ZIndex + 4,
	})
	prepareTemplate(
		currentObjectiveMarker,
		"✦",
		COLORS.Objective
	)

	local playerArrow = findGui(mapArea, "PlayerArrow")
		or ensureImage(mapArea, "PlayerArrow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(25, 25),
			BackgroundTransparency = 1,
			Visible = true,
			ZIndex = mapArea.ZIndex + 10,
		})

	playerArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	playerArrow.Position = UDim2.fromScale(0.5, 0.5)
	playerArrow.Visible = true
	ensureAspect(playerArrow)
	ensureGlyph(playerArrow, "▲", COLORS.Objective)

	local border = findGui(minimap, "Border")
	if not border then
		border = ensureImage(minimap, "Border", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = minimap.ZIndex + 12,
		})
	end

	if border:IsA("ImageLabel") and border.Image == "" then
		ensureStroke(minimap, COLORS.Border, 0.05, 3)
	end

	ensureLabel(minimap, "NorthLabel", "N", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(24, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		ZIndex = minimap.ZIndex + 13,
	})

	return {
		Root = minimap,
		MapArea = mapArea,
		IslandContainer = islandContainer,
		MarkerContainer = markerContainer,
		SmallIslandTemplate = small,
		MediumIslandTemplate = medium,
		LargeIslandTemplate = large,
		RoundGateMarker = roundGate,
		HostileMobMarker = hostile,
		CurrentObjectiveMarker = currentObjectiveMarker,
		PlayerArrow = playerArrow,
	}
end

local minimap = buildMinimap()

local islandMarkers: { [Instance]: GuiObject } = {}
local roundGateMarkers: { [Instance]: GuiObject } = {}
local hostileMarkers: { [Instance]: GuiObject } = {}
local objectiveMarkerClone: GuiObject? = nil

local function cloneTemplate(
	template: GuiObject,
	name: string,
	parent: GuiObject
): GuiObject
	local clone = template:Clone()
	clone.Name = name
	clone.Visible = true
	clone:SetAttribute("MinimapRuntimeClone", true)
	clone.Parent = parent

	local fallback = clone:FindFirstChild("FallbackGlyph")
	if fallback and fallback:IsA("GuiObject") then
		fallback.Visible = true
	end

	return clone
end

local function minimapPosition(
	worldPosition: Vector3,
	playerPosition: Vector3
): UDim2?
	local range = tonumber(minimap.Root:GetAttribute("MapRangeStuds"))
		or MINIMAP_RANGE
	range = math.max(80, range)

	local delta = worldPosition - playerPosition

	-- North-up:
	-- +X = right
	-- -Z = up
	local nx = delta.X / range
	local ny = delta.Z / range
	local radius = Vector2.new(nx, ny).Magnitude

	if radius > 1 then
		return nil
	end

	local mapRadius = 0.46

	return UDim2.fromScale(
		0.5 + nx * mapRadius,
		0.5 + ny * mapRadius
	)
end

local function islandCenter(
	markersFolder: Instance
): (Vector3?, Instance?)
	local island = markersFolder.Parent
	if not island then
		return nil, nil
	end

	local objectiveAnchor = markersFolder:FindFirstChild(
		"ObjectiveAnchor",
		true
	)
	if objectiveAnchor and objectiveAnchor:IsA("BasePart") then
		return objectiveAnchor.Position, island
	end

	if island:IsA("Model") then
		local floor = island:FindFirstChild("IslandFloor")
			or island.PrimaryPart
		if floor and floor:IsA("BasePart") then
			return floor.Position, island
		end
	end

	return nil, island
end

local function islandTemplate(island: Instance): GuiObject
	local declared = tostring(
		island:GetAttribute("IslandSize")
			or island:GetAttribute("SizeClass")
			or ""
	)

	if declared == "Small" then
		return minimap.SmallIslandTemplate
	elseif declared == "Large" then
		return minimap.LargeIslandTemplate
	elseif declared == "Medium" then
		return minimap.MediumIslandTemplate
	end

	if island:IsA("Model") then
		local floor = island:FindFirstChild("IslandFloor")
			or island.PrimaryPart

		if floor and floor:IsA("BasePart") then
			local minimum = math.min(
				floor.Size.X,
				floor.Size.Z
			)

			if minimum < 72 then
				return minimap.SmallIslandTemplate
			elseif minimum >= 108 then
				return minimap.LargeIslandTemplate
			end
		end
	end

	return minimap.MediumIslandTemplate
end

local function updateIslands(playerPosition: Vector3)
	local seen: { [Instance]: boolean } = {}

	for _, markerFolder in ipairs(
		CollectionService:GetTagged("DungeonGameplayMarkers")
	) do
		if markerFolder:IsA("Folder") and markerFolder.Parent then
			local worldPosition, island = islandCenter(markerFolder)

			if worldPosition and island then
				seen[markerFolder] = true

				local template = islandTemplate(island)
				local marker = islandMarkers[markerFolder]

				if not marker
					or not marker.Parent
					or marker:GetAttribute(
						"SourceTemplate"
					) ~= template.Name
				then
					if marker then
						marker:Destroy()
					end

					marker = cloneTemplate(
						template,
						"Island_" .. island.Name,
						minimap.IslandContainer
					)

					marker:SetAttribute(
						"SourceTemplate",
						template.Name
					)

					islandMarkers[markerFolder] = marker
				end

				local mapPos = minimapPosition(
					worldPosition,
					playerPosition
				)

				marker.Visible = mapPos ~= nil
				if mapPos then
					marker.Position = mapPos
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

local function updateRoundGates(playerPosition: Vector3)
	local seen: { [Instance]: boolean } = {}

	for _, markerFolder in ipairs(
		CollectionService:GetTagged("DungeonGameplayMarkers")
	) do
		if markerFolder:IsA("Folder") and markerFolder.Parent then
			local island = markerFolder.Parent

			if island:GetAttribute("IsRoundExit") == true then
				seen[island] = true

				local marker = roundGateMarkers[island]
				if not marker or not marker.Parent then
					marker = cloneTemplate(
						minimap.RoundGateMarker,
						"RoundGate_" .. island.Name,
						minimap.MarkerContainer
					)
					roundGateMarkers[island] = marker
				end

				local worldPosition = select(
					1,
					islandCenter(markerFolder)
				)

				local mapPos = worldPosition
					and minimapPosition(
						worldPosition,
						playerPosition
					)
					or nil

				marker.Visible = mapPos ~= nil
				if mapPos then
					marker.Position = mapPos
				end
			end
		end
	end

	for island, marker in pairs(roundGateMarkers) do
		if not seen[island] or not island.Parent then
			marker:Destroy()
			roundGateMarkers[island] = nil
		end
	end
end

local function targetRoot(model: Model): BasePart?
	local root = model:FindFirstChild(
		"HumanoidRootPart",
		true
	)

	if root and root:IsA("BasePart") then
		return root
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA(
		"BasePart",
		true
	)
end

local function updateHostiles(playerPosition: Vector3)
	local seen: { [Instance]: boolean } = {}

	for _, target in ipairs(
		CollectionService:GetTagged("CombatTarget")
	) do
		if target:IsA("Model")
			and target.Parent
			and target:GetAttribute("Peaceful") ~= true
		then
			local humanoid = target:FindFirstChildWhichIsA(
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
				seen[target] = true

				local marker = hostileMarkers[target]
				if not marker or not marker.Parent then
					marker = cloneTemplate(
						minimap.HostileMobMarker,
						"HostileMob",
						minimap.MarkerContainer
					)
					hostileMarkers[target] = marker
				end

				local mapPos = minimapPosition(
					root.Position,
					playerPosition
				)

				marker.Visible = mapPos ~= nil
				if mapPos then
					marker.Position = mapPos
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

local function findObjectiveAnchor(
	snapshot: ObjectiveSnapshot?
): BasePart?
	local globalIndex = snapshot
		and tonumber(snapshot.GlobalIslandIndex)

	if not globalIndex then
		return nil
	end

	for _, markerFolder in ipairs(
		CollectionService:GetTagged("DungeonGameplayMarkers")
	) do
		if markerFolder:IsA("Folder") and markerFolder.Parent then
			local island = markerFolder.Parent
			local islandIndex = tonumber(
				island:GetAttribute("GlobalIslandIndex")
			) or tonumber(
				markerFolder:GetAttribute(
					"GlobalIslandIndex"
				)
			)

			if islandIndex == globalIndex then
				local anchor = markerFolder:FindFirstChild(
					"ObjectiveAnchor",
					true
				)

				if anchor and anchor:IsA("BasePart") then
					return anchor
				end
			end
		end
	end

	return nil
end

local function updateObjectiveMarker(
	playerPosition: Vector3
)
	local snapshot = currentObjective
	local active = snapshot
		and (
			snapshot.State == "Active"
			or snapshot.State == "Completed"
		)

	local anchor = active and findObjectiveAnchor(snapshot)
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
		objectiveMarkerClone = cloneTemplate(
			minimap.CurrentObjectiveMarker,
			"CurrentObjective",
			minimap.MarkerContainer
		)
	end

	local mapPos = minimapPosition(
		anchor.Position,
		playerPosition
	)

	objectiveMarkerClone.Visible = mapPos ~= nil

	if mapPos then
		objectiveMarkerClone.Position = mapPos
	end

	local fallback = objectiveMarkerClone:FindFirstChild(
		"FallbackGlyph"
	)

	if fallback and textObject(fallback) then
		(fallback :: any).TextColor3 =
			snapshot
				and snapshot.WaypointEscalated
				and COLORS.XP
			or COLORS.Objective
	end
end

local minimapAccumulator = 0

RunService.RenderStepped:Connect(function(deltaTime)
	minimapAccumulator += deltaTime

	if minimapAccumulator < MINIMAP_UPDATE_INTERVAL then
		return
	end

	minimapAccumulator = 0

	local character = player.Character
	local root = character
		and character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	local position = root.Position

	updateIslands(position)
	updateRoundGates(position)
	updateHostiles(position)
	updateObjectiveMarker(position)

	local look = root.CFrame.LookVector
	local heading = math.deg(
		math.atan2(look.X, -look.Z)
	)

	minimap.PlayerArrow.Rotation = heading
end)

---------------------------------------------------------------------
-- MissionsPanel
---------------------------------------------------------------------

type MissionsUI = {
	Panel: GuiObject,
	MissionList: GuiObject,
	Template: GuiObject,
	CollapseButton: GuiButton,
	Collapsed: boolean,
}

local function buildMissionsPanel(): MissionsUI
	local panel = findGui(dungeonHud, "MissionsPanel")

	if not panel then
		panel = ensureFrame(dungeonHud, "MissionsPanel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -22, 0, 258),
			Size = UDim2.fromOffset(300, 190),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.18,
			ZIndex = 20,
		})
		ensureCorner(panel, 10)
		ensureStroke(panel, COLORS.Border, 0.20, 1.5)
	end

	ensureImage(panel, "Background", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = panel.ZIndex,
	})

	ensureImage(panel, "Border", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = panel.ZIndex + 8,
	})

	local header = findGui(panel, "Header")
		or ensureFrame(panel, "Header", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			ZIndex = panel.ZIndex + 2,
		})

	ensureLabel(header, "Title", "Missões", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -52, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		ZIndex = header.ZIndex + 1,
	})

	local collapse = header:FindFirstChild("CollapseButton")

	if not collapse or not collapse:IsA("GuiButton") then
		if collapse then
			collapse.Name = "CollapseButton_Art"
		end

		local button = Instance.new("ImageButton")
		button.Name = "CollapseButton"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.fromOffset(26, 26)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.ZIndex = header.ZIndex + 2
		button.Parent = header
		collapse = button
	end

	ensureGlyph(collapse :: GuiObject, "⌃", COLORS.Text)

	local missionList = findGui(panel, "MissionList")
		or ensureFrame(panel, "MissionList", {
			Position = UDim2.fromOffset(10, 38),
			Size = UDim2.new(1, -20, 1, -46),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = panel.ZIndex + 2,
		})

	local layout = missionList:FindFirstChildOfClass(
		"UIListLayout"
	)

	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Name = "UIListLayout"
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = missionList
	end

	local template = findGui(missionList, "MissionTemplate")

	if not template then
		template = ensureFrame(
			missionList,
			"MissionTemplate",
			{
				Size = UDim2.new(1, 0, 0, 68),
				BackgroundTransparency = 1,
				Visible = false,
				ZIndex = missionList.ZIndex + 1,
			}
		)
	end

	template.Visible = false

	local icon = findGui(template, "Icon")
		or ensureImage(template, "Icon", {
			Position = UDim2.fromOffset(2, 8),
			Size = UDim2.fromOffset(26, 26),
			BackgroundTransparency = 1,
			ZIndex = template.ZIndex + 2,
		})
	ensureAspect(icon)
	ensureGlyph(icon, "◆", COLORS.XP)

	local textContainer = findGui(
		template,
		"TextContainer"
	) or ensureFrame(template, "TextContainer", {
		Position = UDim2.fromOffset(36, 2),
		Size = UDim2.new(1, -40, 1, -4),
		BackgroundTransparency = 1,
		ZIndex = template.ZIndex + 1,
	})

	ensureLabel(
		textContainer,
		"MissionTitle",
		"Missão Principal",
		{
			Size = UDim2.new(1, 0, 0, 18),
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = COLORS.XP,
			ZIndex = textContainer.ZIndex + 1,
		}
	)

	ensureLabel(
		textContainer,
		"Description",
		"Explore a ilha",
		{
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 22),
			Font = Enum.Font.GothamMedium,
			TextSize = 10,
			TextWrapped = true,
			ZIndex = textContainer.ZIndex + 1,
		}
	)

	ensureLabel(
		textContainer,
		"Progress",
		"0 / 1",
		{
			Position = UDim2.fromOffset(0, 41),
			Size = UDim2.new(1, 0, 0, 18),
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = COLORS.Success,
			ZIndex = textContainer.ZIndex + 1,
		}
	)

	ensureFrame(template, "Divider", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 34, 1, 0),
		Size = UDim2.new(1, -34, 0, 1),
		BackgroundColor3 = COLORS.Muted,
		BackgroundTransparency = 0.70,
		ZIndex = template.ZIndex + 1,
	})

	return {
		Panel = panel,
		MissionList = missionList,
		Template = template,
		CollapseButton = collapse :: GuiButton,
		Collapsed = false,
	}
end

local missions = buildMissionsPanel()
local missionRows: { GuiObject } = {}

local function clearMissionRows()
	for _, row in ipairs(missionRows) do
		if row.Parent then
			row:Destroy()
		end
	end
	table.clear(missionRows)
end

type MissionRowData = {
	Title: string,
	Description: string,
	Progress: string?,
	Glyph: string?,
	Color: Color3?,
}

local function addMission(
	data: MissionRowData,
	order: number
)
	local row = missions.Template:Clone()
	row.Name = "Mission_" .. tostring(order)
	row.Visible = true
	row.LayoutOrder = order
	row:SetAttribute("RuntimeMission", true)
	row.Parent = missions.MissionList

	local icon = row:FindFirstChild("Icon")
	local textContainer = row:FindFirstChild(
		"TextContainer"
	)
	local title = textContainer
		and textContainer:FindFirstChild(
			"MissionTitle"
		)
	local description = textContainer
		and textContainer:FindFirstChild(
			"Description"
		)
	local progress = textContainer
		and textContainer:FindFirstChild(
			"Progress"
		)

	setText(title, data.Title)
	setText(description, data.Description)
	setText(progress, data.Progress or "")

	if title and textObject(title) then
		(title :: any).TextColor3 =
			data.Color or COLORS.XP
	end

	if progress and textObject(progress) then
		(progress :: GuiObject).Visible =
			data.Progress ~= nil
			and data.Progress ~= ""
	end

	if icon and icon:IsA("GuiObject") then
		local glyph = icon:FindFirstChild(
			"FallbackGlyph"
		)
		if glyph and textObject(glyph) then
			setText(glyph, data.Glyph or "◆")
			(glyph :: any).TextColor3 =
				data.Color or COLORS.XP
		end
	end

	table.insert(missionRows, row)
end

local function renderMissions(snapshot: ObjectiveSnapshot?)
	clearMissionRows()

	snapshot = snapshot or readObjectiveFromWorkspace()

	local state = tostring(snapshot.State or "Inactive")
	local progress = math.max(
		0,
		math.floor(tonumber(snapshot.Progress) or 0)
	)
	local target = math.max(
		1,
		math.floor(tonumber(snapshot.Target) or 1)
	)
	local round = math.max(
		1,
		math.floor(tonumber(snapshot.RoundIndex) or 1)
	)
	local island = math.max(
		1,
		math.floor(tonumber(snapshot.IslandIndex) or 1)
	)
	local roundLength = ROUND_LENGTHS[round]
		or math.max(1, island)

	if state == "Active" then
		addMission({
			Title = "Missão Principal",
			Description = truncateUtf8(
				snapshot.Title
					or snapshot.Description
					or "Conclua o objetivo atual",
				68
			),
			Progress = string.format(
				"(%d/%d)",
				progress,
				target
			),
			Glyph = "◆",
			Color = COLORS.XP,
		}, 1)

		addMission({
			Title = "Progresso da Rodada",
			Description = string.format(
				"Avance pelas ilhas da rodada %d.",
				round
			),
			Progress = string.format(
				"(%d/%d)",
				math.min(island, roundLength),
				roundLength
			),
			Glyph = "◇",
			Color = COLORS.Objective,
		}, 2)
	elseif state == "Completed" then
		addMission({
			Title = "Objetivo Concluído",
			Description = "Avance para a próxima ilha.",
			Progress = "✓",
			Glyph = "✓",
			Color = COLORS.Success,
		}, 1)
	else
		addMission({
			Title = "Exploração",
			Description = "Encontre a próxima ilha da rota.",
			Progress = nil,
			Glyph = "◇",
			Color = COLORS.Objective,
		}, 1)
	end
end

local function setMissionsCollapsed(collapsed: boolean)
	missions.Collapsed = collapsed
	missions.MissionList.Visible = not collapsed

	local fallback = missions.CollapseButton:FindFirstChild(
		"FallbackGlyph"
	)

	if fallback and textObject(fallback) then
		setText(fallback, collapsed and "⌄" or "⌃")
	end

	pop(missions.Panel, 0.018, 0.08)
end

missions.CollapseButton.Activated:Connect(function()
	setMissionsCollapsed(not missions.Collapsed)
end)

---------------------------------------------------------------------
-- One dispatcher for ObjectivePanel + MissionsPanel + Minimap state.
---------------------------------------------------------------------

local function dispatchObjective(snapshot: ObjectiveSnapshot?)
	renderObjective(snapshot)
	renderMissions(snapshot)
end

local watchedObjectiveAttributes = {
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
}

for _, attributeName in ipairs(watchedObjectiveAttributes) do
	workspace:GetAttributeChangedSignal(
		attributeName
	):Connect(function()
		dispatchObjective(
			readObjectiveFromWorkspace()
		)
	end)
end

-- Consume the authoritative ObjectiveService RemoteEvent when available.
-- Workspace attributes remain as a fallback, so the HUD still works if the
-- remote has not been created yet during initial loading.
task.spawn(function()
	local shared = ReplicatedStorage:FindFirstChild(
		"Shared"
	) or ReplicatedStorage:WaitForChild("Shared", 20)

	if not shared then
		return
	end

	local utilities = shared:FindFirstChild(
		"Utilities"
	) or shared:WaitForChild("Utilities", 10)

	if not utilities then
		return
	end

	local registryModule = utilities:FindFirstChild(
		"RemoteRegistry"
	)

	if not registryModule then
		return
	end

	local okRegistry, RemoteRegistry = pcall(
		require,
		registryModule
	)

	if not okRegistry or not RemoteRegistry then
		return
	end

	local okRemote, remote = pcall(
		RemoteRegistry.Get,
		"Dungeon",
		"ObjectiveState",
		"RemoteEvent"
	)

	if not okRemote or not remote then
		return
	end

	remote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table"
			or payload.Action ~= "ObjectiveSnapshot"
		then
			return
		end

		dispatchObjective(payload.Objective)
	end)
end)

---------------------------------------------------------------------
-- Initial render
---------------------------------------------------------------------

dispatchObjective(readObjectiveFromWorkspace())

player:SetAttribute(
	"DungeonArtHUDControllerReady",
	true
)
dungeonHud:SetAttribute("ControllerReady", true)

print("[DungeonArtHUD] Controller ready.")
