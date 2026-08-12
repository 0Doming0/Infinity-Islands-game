--[[
	Infinity Islands - DungeonArtHUDController V18
	Menu-Safe Authored HUD + Contextual Objective Notice

	Goal:
	- NEVER fail permanently because the HUD loaded late.
	- NEVER depend on a 10s/20s generation timeout.
	- NEVER require tags when the authored names are correct.
	- Re-find and re-bind the authored UI if PlayerGui is rebuilt after respawn,
	  map generation, Rojo sync, or another system changes GUI hierarchy.

	This controller does not construct the HUD art.
	It may only:
	- clone the complete designer-authored StarterGui.DungeonHUD;
	- clone authored minimap templates;
	- update properties/text of existing authored elements.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "AuthoredHUDV19DirectionalObjectiveFade"

local OBJECTIVE_NOTICE_SECONDS = 6
local OBJECTIVE_COMPLETION_SECONDS = 2.75
local OBJECTIVE_TRANSITION_SECONDS = 0.25
local OBJECTIVE_ENTER_OFFSET_X = -48
local OBJECTIVE_EXIT_OFFSET_X = 48

local CORE_ALIASES = {
	ObjectivePanel = {
		"ObjectivePanel", "Objective", "ObjectiveFrame",
		"ObjectiveContainer", "ObjectiveHolder",
	},
	PlayerStatus = {
		"PlayerStatus", "Status", "PlayerStatusFrame",
		"StatusPanel", "PlayerHUD", "PlayerInfo",
	},
	MiniMap = {
		"MiniMap", "Minimap", "Map", "MiniMapFrame",
		"MapPanel", "Radar",
	},
	MissionsPanel = {
		"MissionsPanel", "Missions", "MissionPanel",
		"QuestPanel", "QuestsPanel", "QuestListPanel",
	},
}

local TAGS = {
	ObjectivePanel = "DungeonHUD_Objective",
	PlayerStatus = "DungeonHUD_PlayerStatus",
	MiniMap = "DungeonHUD_Minimap",
	MissionsPanel = "DungeonHUD_Missions",
}

local function normalize(value)
	return string.lower(
		string.gsub(tostring(value or ""), "[^%w]", "")
	)
end

local SAFE_SUFFIXES = {
	"frame", "label", "text", "image", "button",
	"panel", "container", "holder", "bar",
	"icon", "background", "gui",
}

local function semantic(value)
	local result = normalize(value)
	local changed = true

	while changed do
		changed = false

		for _, suffix in ipairs(SAFE_SUFFIXES) do
			if #result > #suffix + 3
				and string.sub(result, -#suffix) == suffix
			then
				result = string.sub(
					result,
					1,
					#result - #suffix
				)
				changed = true
				break
			end
		end
	end

	return result
end

local function isGui(object)
	return object and object:IsA("GuiObject")
end

local function isText(object)
	return object
		and (
			object:IsA("TextLabel")
			or object:IsA("TextButton")
			or object:IsA("TextBox")
		)
end

local function isImage(object)
	return object
		and (
			object:IsA("ImageLabel")
			or object:IsA("ImageButton")
		)
end

local function allIncludingRoot(rootObject)
	local result = {}

	if not rootObject then
		return result
	end

	table.insert(result, rootObject)

	for _, descendant in ipairs(
		rootObject:GetDescendants()
	) do
		table.insert(result, descendant)
	end

	return result
end

local function nameScore(objectName, aliases)
	local actual = normalize(objectName)
	local actualSemantic = semantic(objectName)
	local best = 0

	for _, alias in ipairs(aliases) do
		local wanted = normalize(alias)
		local wantedSemantic = semantic(alias)

		if actual == wanted then
			best = math.max(best, 100)
		elseif actualSemantic == wantedSemantic
			and #wantedSemantic >= 4
		then
			best = math.max(best, 90)
		elseif #wanted >= 5
			and string.find(actual, wanted, 1, true)
		then
			best = math.max(best, 70)
		elseif #actual >= 5
			and string.find(wanted, actual, 1, true)
		then
			best = math.max(best, 60)
		end
	end

	return best
end

local function taggedCandidate(tagName, rootObject, predicate)
	if not tagName then
		return nil
	end

	for _, object in ipairs(
		CollectionService:GetTagged(tagName)
	) do
		if object.Parent
			and (
				not rootObject
				or object:IsDescendantOf(rootObject)
			)
			and (
				not predicate
				or predicate(object)
			)
		then
			return object
		end
	end

	return nil
end

local function findBest(
	rootObject,
	aliases,
	predicate,
	tagName
)
	if not rootObject then
		return nil
	end

	local tagged = taggedCandidate(
		tagName,
		rootObject,
		predicate
	)

	if tagged then
		return tagged
	end

	local bestObject
	local bestScore = -math.huge
	local bestDepth = math.huge

	for _, object in ipairs(
		allIncludingRoot(rootObject)
	) do
		if not predicate or predicate(object) then
			local score = nameScore(
				object.Name,
				aliases
			)

			if score > 0 then
				local depth = 0
				local current = object

				while current
					and current ~= rootObject
				do
					depth += 1
					current = current.Parent
				end

				-- Prefer the closest valid match if scores tie.
				if score > bestScore
					or (
						score == bestScore
						and depth < bestDepth
					)
				then
					bestObject = object
					bestScore = score
					bestDepth = depth
				end
			end
		end
	end

	return bestObject
end

local function findScreenGuiNamed(
	container,
	wantedName
)
	if not container then
		return nil
	end

	local direct =
		container:FindFirstChild(wantedName)

	if direct and direct:IsA("ScreenGui") then
		return direct
	end

	for _, descendant in ipairs(
		container:GetDescendants()
	) do
		if descendant:IsA("ScreenGui")
			and normalize(descendant.Name)
				== normalize(wantedName)
		then
			return descendant
		end
	end

	return nil
end

local function resolveCore(hud)
	if not hud then
		return {}
	end

	return {
		ObjectivePanel = findBest(
			hud,
			CORE_ALIASES.ObjectivePanel,
			isGui,
			TAGS.ObjectivePanel
		),
		PlayerStatus = findBest(
			hud,
			CORE_ALIASES.PlayerStatus,
			isGui,
			TAGS.PlayerStatus
		),
		MiniMap = findBest(
			hud,
			CORE_ALIASES.MiniMap,
			isGui,
			TAGS.MiniMap
		),
		MissionsPanel = findBest(
			hud,
			CORE_ALIASES.MissionsPanel,
			isGui,
			TAGS.MissionsPanel
		),
	}
end

local function coreScore(hud)
	if not hud or not hud:IsA("ScreenGui") then
		return 0
	end

	local core = resolveCore(hud)
	local score = 0

	if core.ObjectivePanel then score += 1 end
	if core.PlayerStatus then score += 1 end
	if core.MiniMap then score += 1 end

	return score
end

local function findHud(container)
	-- V15 intentionally resolves ONLY the authored ScreenGui named DungeonHUD.
	-- Never fall back to an arbitrary ScreenGui based on matching child names:
	-- that could incorrectly bind SettingsUI or another modal overlay.
	return findScreenGuiNamed(
		container,
		"DungeonHUD"
	)
end

local function configureHud(hud)
	if not hud then
		return
	end

	hud.Enabled = true
	hud.ResetOnSpawn = false

	hud:SetAttribute(
		"ResponsiveGenericOptOut",
		true
	)
	hud:SetAttribute(
		"ControllerVersion",
		VERSION
	)
	hud:SetAttribute(
		"ControllerCreatesVisuals",
		false
	)
end

local function ensureHud()
	local current = findHud(playerGui)

	if current then
		configureHud(current)

		player:SetAttribute(
			"DungeonArtHUDSource",
			"PlayerGui"
		)

		return current
	end

	local source = findHud(StarterGui)

	if not source then
		return nil
	end

	-- Recheck immediately before cloning to avoid duplicate races.
	current = findHud(playerGui)

	if current then
		configureHud(current)
		return current
	end

	local clone = source:Clone()
	clone.Name = "DungeonHUD"
	clone:SetAttribute(
		"ClonedByDungeonArtHUDController",
		true
	)
	configureHud(clone)
	clone.Parent = playerGui

	player:SetAttribute(
		"DungeonArtHUDSource",
		"StarterGuiClone"
	)

	return clone
end

---------------------------------------------------------------------
-- Generic child resolution
---------------------------------------------------------------------

local function text(rootObject, aliases)
	return findBest(
		rootObject,
		aliases,
		isText
	)
end

local function gui(rootObject, aliases)
	return findBest(
		rootObject,
		aliases,
		isGui
	)
end

local function image(rootObject, aliases)
	return findBest(
		rootObject,
		aliases,
		isImage
	)
end

local function setText(object, value)
	if isText(object) then
		object.Text = tostring(value or "")
	end
end

local function tween(
	object,
	duration,
	properties
)
	if not object
		or not object.Parent
	then
		return
	end

	TweenService:Create(
		object,
		TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		properties
	):Play()
end

local function resolveBar(
	rootObject,
	aliases
)
	local barRoot = gui(
		rootObject,
		aliases
	)

	if not barRoot then
		return nil
	end

	local fill = gui(
		barRoot,
		{
			"Fill", "ProgressFill", "BarFill",
			"ValueFill", "Foreground",
		}
	)

	local background = gui(
		barRoot,
		{
			"Background", "ProgressBackground",
			"BarBackground", "Track",
		}
	)

	local value = text(
		barRoot,
		{
			"Value", "ValueText", "Counter",
			"ProgressText", "Amount", "Text",
		}
	)

	local fullX

	if fill then
		if background
			and fill.Parent == background
		then
			fullX = UDim.new(1, 0)
		elseif background
			and fill.Parent == background.Parent
		then
			fullX = background.Size.X
		else
			fullX = fill.Size.X
		end
	end

	return {
		Root = barRoot,
		Fill = fill,
		Background = background,
		Value = value,
		FullX = fullX,
	}
end

local function setBar(
	bar,
	ratio,
	valueText
)
	if not bar then
		return
	end

	setText(bar.Value, valueText)

	if bar.Fill and bar.FullX then
		ratio = math.clamp(
			tonumber(ratio) or 0,
			0,
			1
		)

		local y = bar.Fill.Size.Y

		tween(
			bar.Fill,
			0.15,
			{
				Size = UDim2.new(
					bar.FullX.Scale * ratio,
					math.floor(
						bar.FullX.Offset
							* ratio
							+ 0.5
					),
					y.Scale,
					y.Offset
				),
			}
		)
	end
end

---------------------------------------------------------------------
-- Binding state
---------------------------------------------------------------------

local boundHud
local refs = {}


---------------------------------------------------------------------
-- Static front-facing 3D character portrait
---------------------------------------------------------------------

local PORTRAIT_VERSION =
	"StaticCharacterFrontViewportV2"

local portraitState = {
	Host = nil,
	Viewport = nil,
	WorldModel = nil,
	Camera = nil,
	Character = nil,
	BuildSerial = 0,
	Connections = {},
	PendingRebuild = false,
}

local function disconnectPortraitConnections()
	for _, connection in ipairs(
		portraitState.Connections
	) do
		connection:Disconnect()
	end

	table.clear(
		portraitState.Connections
	)
end

local function destroyPortraitViewport()
	if portraitState.Viewport
		and portraitState.Viewport.Parent
	then
		portraitState.Viewport:Destroy()
	end

	portraitState.Host = nil
	portraitState.Viewport = nil
	portraitState.WorldModel = nil
	portraitState.Camera = nil
	portraitState.Character = nil
end

local function setPortraitDiagnostics(
	ready,
	reason
)
	player:SetAttribute(
		"DungeonPortrait3DReady",
		ready == true
	)
	player:SetAttribute(
		"DungeonPortrait3DVersion",
		PORTRAIT_VERSION
	)
	player:SetAttribute(
		"DungeonPortrait3DMode",
		"StaticFrontFacingCloneNoAnimation"
	)
	player:SetAttribute(
		"DungeonPortrait3DLastStatus",
		tostring(reason or "Unknown")
	)
end

local function removeAnimationAndRuntimeObjects(
	characterClone
)
	for _, descendant in ipairs(
		characterClone:GetDescendants()
	) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("Animator")
			or descendant:IsA("AnimationController")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("Highlight")
		then
			descendant:Destroy()

		elseif descendant:IsA("Motor6D") then
			-- Remove any pose inherited from a running/jumping animation.
			descendant.Transform =
				CFrame.identity

		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.AssemblyLinearVelocity =
				Vector3.zero
			descendant.AssemblyAngularVelocity =
				Vector3.zero
		end
	end

	local humanoid =
		characterClone
			:FindFirstChildOfClass(
				"Humanoid"
			)

	if humanoid then
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayType =
			Enum.HumanoidHealthDisplayType
				.AlwaysOff
		humanoid.DisplayDistanceType =
			Enum.HumanoidDisplayDistanceType
				.None
	end
end

local function cloneCurrentCharacter(
	character
)
	if not character
		or not character.Parent
	then
		return nil
	end

	local previousArchivable =
		character.Archivable

	character.Archivable = true

	local ok, clone =
		pcall(
			character.Clone,
			character
		)

	character.Archivable =
		previousArchivable

	if not ok
		or not clone
	then
		return nil
	end

	clone.Name =
		"PortraitCharacter"

	removeAnimationAndRuntimeObjects(
		clone
	)

	return clone
end

local function framePortraitCamera(
	characterClone,
	camera
)
	local boxCFrame,
		boxSize =
			characterClone:GetBoundingBox()

	local fov = 28

	camera.FieldOfView = fov

	local halfHeight =
		math.max(
			0.5,
			boxSize.Y * 0.5
		)

	local verticalDistance =
		halfHeight
			/ math.tan(
				math.rad(fov * 0.5)
			)

	local distance =
		math.max(
			4,
			verticalDistance * 1.08,
			boxSize.X * 1.8,
			boxSize.Z * 2.2
		)

	local target =
		boxCFrame.Position
			+ Vector3.new(
				0,
				boxSize.Y * 0.035,
				0
			)

	local cameraPosition =
		target
			+ Vector3.new(
				0,
				boxSize.Y * 0.015,
				distance
			)

	camera.CFrame =
		CFrame.lookAt(
			cameraPosition,
			target
		)
end

local function createPortraitViewport(
	host
)
	local old =
		host:FindFirstChild(
			"DungeonCharacterViewport"
		)

	if old then
		old:Destroy()
	end

	local viewport =
		Instance.new("ViewportFrame")

	viewport.Name =
		"DungeonCharacterViewport"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Size =
		UDim2.fromScale(1, 1)
	viewport.Position =
		UDim2.fromScale(0, 0)
	viewport.AnchorPoint =
		Vector2.zero
	viewport.Active = false
	viewport.ClipsDescendants = true

	if host:IsA("GuiObject") then
		viewport.ZIndex =
			host.ZIndex
	end

	viewport.Ambient =
		Color3.fromRGB(
			175,
			175,
			175
		)

	viewport.LightColor =
		Color3.fromRGB(
			255,
			245,
			230
		)

	viewport.LightDirection =
		Vector3.new(
			-0.7,
			-1,
			-0.5
		)

	local corner =
		host:FindFirstChildWhichIsA(
			"UICorner"
		)

	if corner then
		corner:Clone().Parent =
			viewport
	end

	viewport.Parent = host

	local worldModel =
		Instance.new("WorldModel")
	worldModel.Name =
		"PortraitWorld"
	worldModel.Parent =
		viewport

	local camera =
		Instance.new("Camera")
	camera.Name =
		"PortraitCamera"
	camera.Parent =
		viewport

	viewport.CurrentCamera =
		camera

	return viewport,
		worldModel,
		camera
end

local function buildStaticPortrait(
	host,
	character
)
	if not host
		or not host.Parent
		or not host:IsA("GuiObject")
	then
		setPortraitDiagnostics(
			false,
			"PortraitHostMissing"
		)
		return false
	end

	local clone =
		cloneCurrentCharacter(
			character
		)

	if not clone then
		setPortraitDiagnostics(
			false,
			"CharacterCloneFailed"
		)
		return false
	end

	destroyPortraitViewport()

	local viewport,
		worldModel,
		camera =
			createPortraitViewport(
				host
			)

	portraitState.Host = host
	portraitState.Viewport =
		viewport
	portraitState.WorldModel =
		worldModel
	portraitState.Camera =
		camera
	portraitState.Character =
		character
	portraitState.BuildSerial += 1

	clone.Parent =
		worldModel

	-- Move the clone to an isolated local coordinate space and FORCE a
	-- deterministic front-facing orientation. The portrait no longer inherits
	-- the direction the live Character happened to be facing in Workspace.
	clone:PivotTo(
		CFrame.new(0, 0, 0)
	)

	-- Roblox characters normally face their local -Z direction. The portrait
	-- camera is placed on +Z looking toward the origin, so rotating the clone
	-- 180 degrees around Y makes the avatar face the camera/screen.
	clone:PivotTo(
		CFrame.Angles(
			0,
			math.rad(180),
			0
		)
	)

	framePortraitCamera(
		clone,
		camera
	)

	-- The authored ImageLabel remains as the layout/mask holder.
	if host:IsA("ImageLabel")
		or host:IsA("ImageButton")
	then
		host.ImageTransparency = 1
	end

	player:SetAttribute(
		"DungeonPortrait3DBuildSerial",
		portraitState.BuildSerial
	)

	setPortraitDiagnostics(
		true,
		"CharacterCloned"
	)

	return true
end

local function portraitHostFromStatus(
	status
)
	if not status then
		return nil
	end

	-- Prefer the authored AvatarImage because it already has the exact
	-- position/size chosen in Studio. Portrait itself is the fallback.
	return status.AvatarImage
		or status.Portrait
end

local function rebuildPortraitSoon()
	if portraitState.PendingRebuild then
		return
	end

	portraitState.PendingRebuild = true

	task.delay(
		0.12,
		function()
			portraitState.PendingRebuild =
				false

			local status =
				refs.Status

			local host =
				portraitHostFromStatus(
					status
				)

			local character =
				player.Character

			if host
				and character
				and character.Parent
			then
				buildStaticPortrait(
					host,
					character
				)
			end
		end
	)
end

local function bindPortraitCharacterSignals(
	character
)
	disconnectPortraitConnections()

	if not character then
		return
	end

	local function relevantChild(
		child
	)
		return child:IsA("Accessory")
			or child:IsA("Tool")
			or child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
			or child:IsA("BodyColors")
	end

	table.insert(
		portraitState.Connections,
		character.ChildAdded:Connect(
			function(child)
				if relevantChild(child) then
					rebuildPortraitSoon()
				end
			end
		)
	)

	table.insert(
		portraitState.Connections,
		character.ChildRemoved:Connect(
			function(child)
				if relevantChild(child) then
					rebuildPortraitSoon()
				end
			end
		)
	)
end

local function ensureStaticPortrait()
	local status =
		refs.Status

	local host =
		portraitHostFromStatus(
			status
		)

	local character =
		player.Character

	if not host
		or not character
		or not character.Parent
	then
		return
	end

	if portraitState.Host ~= host
		or portraitState.Character
			~= character
		or not portraitState.Viewport
		or not portraitState.Viewport.Parent
	then
		bindPortraitCharacterSignals(
			character
		)

		buildStaticPortrait(
			host,
			character
		)
	end
end

local bindSerial = 0
local lastBindSignature = ""
local dirty = true

local function instancePath(object)
	if not object then
		return "nil"
	end

	local ok, fullName =
		pcall(object.GetFullName, object)

	return ok and fullName or object.Name
end

local function reportBinding()
	local signature = table.concat({
		instancePath(boundHud),
		instancePath(refs.ObjectivePanel),
		instancePath(refs.PlayerStatus),
		instancePath(refs.MiniMap),
		instancePath(refs.MissionsPanel),
	}, " | ")

	if signature == lastBindSignature then
		return
	end

	lastBindSignature = signature

	player:SetAttribute(
		"DungeonArtHUDBindReport",
		signature
	)

	print(
		"[AuthoredHUD V15] Binding: "
			.. signature
	)
end

local function bindObjective(panel)
	local result = {
		Panel = panel,
	}

	if not panel then
		return result
	end

	result.Title = text(
		panel,
		{
			"Title", "ObjectiveTitle", "Titulo",
		}
	)

	result.Description = text(
		panel,
		{
			"Description",
			"ObjectiveDescription",
			"Descricao",
			"Detail",
		}
	)

	result.Counter = text(
		panel,
		{
			"Counter", "ProgressText",
			"ObjectiveCounter", "Count",
		}
	)

	result.ProgressBackground = gui(
		panel,
		{
			"ProgressBackground",
			"BarBackground",
			"Track",
		}
	)

	result.ProgressFill = gui(
		panel,
		{
			"ProgressFill",
			"BarFill",
			"Fill",
		}
	)

	result.CompletedIcon = gui(
		panel,
		{
			"CompletedIcon",
			"CompleteIcon",
			"CheckIcon",
			"Completed",
		}
	)

	if result.ProgressFill then
		if result.ProgressBackground
			and result.ProgressFill.Parent
				== result.ProgressBackground
		then
			result.FullX = UDim.new(1, 0)
		elseif result.ProgressBackground
			and result.ProgressFill.Parent
				== result.ProgressBackground.Parent
		then
			result.FullX =
				result.ProgressBackground.Size.X
		else
			result.FullX =
				result.ProgressFill.Size.X
		end
	end

	return result
end

local function bindStatus(panel)
	local result = {
		Panel = panel,
	}

	if not panel then
		return result
	end

	result.PlayerName = text(
		panel,
		{
			"PlayerName", "DisplayName",
			"NameLabel", "Username",
		}
	)

	local portrait = gui(
		panel,
		{
			"Portrait", "PlayerPortrait",
			"AvatarHolder", "AvatarContainer",
		}
	) or panel

	result.Portrait = portrait

	result.AvatarImage = image(
		portrait,
		{
			"AvatarImage", "Avatar",
			"Headshot", "PlayerImage",
		}
	)

	result.LevelText = text(
		portrait,
		{
			"LevelText", "Level",
			"Lvl", "PlayerLevel",
		}
	) or text(
		panel,
		{
			"LevelText", "Level",
			"Lvl", "PlayerLevel",
		}
	)

	result.HealthBar = resolveBar(
		panel,
		{
			"HealthBar", "HPBar",
			"Health", "Vida",
		}
	)

	result.StaminaBar = resolveBar(
		panel,
		{
			"StaminaBar", "EnergyBar",
			"Stamina", "Energia",
		}
	)

	result.XPBar = resolveBar(
		panel,
		{
			"XPBar", "ExperienceBar",
			"ExpBar", "XP", "Experience",
		}
	)

	return result
end

local function bindMinimap(panel)
	local result = {
		Panel = panel,
	}

	if not panel then
		return result
	end

	result.MapArea = gui(
		panel,
		{
			"MapArea", "MapContent",
			"ContentArea", "RadarArea",
		}
	) or panel

	result.IslandContainer = gui(
		result.MapArea,
		{
			"IslandContainer",
			"IslandsContainer",
			"Islands",
			"IslandLayer",
		}
	)

	result.MarkerContainer = gui(
		result.MapArea,
		{
			"MarkerContainer",
			"MarkersContainer",
			"Markers",
			"MarkerLayer",
		}
	)

	result.PlayerArrow = gui(
		result.MapArea,
		{
			"PlayerArrow", "PlayerMarker",
			"PlayerIcon", "Arrow",
		}
	)

	result.NorthLabel = gui(
		result.MapArea,
		{
			"NorthLabel", "North",
			"NorthIndicator",
		}
	)

	if result.IslandContainer then
		result.SmallIslandTemplate = gui(
			result.IslandContainer,
			{
				"SmallIslandTemplate",
				"SmallIsland",
				"IslandSmall",
			}
		)
		result.MediumIslandTemplate = gui(
			result.IslandContainer,
			{
				"MediumIslandTemplate",
				"MediumIsland",
				"IslandMedium",
			}
		)
		result.LargeIslandTemplate = gui(
			result.IslandContainer,
			{
				"LargeIslandTemplate",
				"LargeIsland",
				"IslandLarge",
			}
		)

		for _, template in ipairs({
			result.SmallIslandTemplate,
			result.MediumIslandTemplate,
			result.LargeIslandTemplate,
		}) do
			if template then
				template.Visible = false
			end
		end
	end

	if result.MarkerContainer then
		result.HostileMobTemplate = gui(
			result.MarkerContainer,
			{
				"HostileMobMarker",
				"HostileMarker",
				"EnemyMarker",
				"MobMarker",
			}
		)

		result.ObjectiveMarkerTemplate = gui(
			result.MarkerContainer,
			{
				"CurrentObjectiveMarker",
				"ObjectiveMarker",
				"CurrentObjective",
				"TargetMarker",
			}
		)

		for _, template in ipairs({
			result.HostileMobTemplate,
			result.ObjectiveMarkerTemplate,
		}) do
			if template then
				template.Visible = false
			end
		end
	end

	return result
end

local bindingConnections = {}
local visibilityGuard = false
local recoverySerial = 0
local objectivePresentation = {
	Panel = nil,
	RestingPosition = nil,
	WantsVisible = false,
	Serial = 0,
	Tweens = {},
	TransparencyBaselines = {},
	LastIdentity = nil,
	LastState = nil,
	LastCompleted = false,
}

local function cancelObjectiveTweens()
	for _, activeTween in ipairs(
		objectivePresentation.Tweens
	) do
		pcall(function()
			activeTween:Cancel()
		end)
	end

	table.clear(objectivePresentation.Tweens)
end

local function objectiveOffsetPosition(restingPosition, offsetX)
	return UDim2.new(
		restingPosition.X.Scale,
		restingPosition.X.Offset + offsetX,
		restingPosition.Y.Scale,
		restingPosition.Y.Offset
	)
end

local function objectiveTransparencyProperties(instance)
	local properties = {}

	if instance:IsA("GuiObject") then
		table.insert(properties, "BackgroundTransparency")
	end

	if instance:IsA("ImageLabel")
		or instance:IsA("ImageButton")
	then
		table.insert(properties, "ImageTransparency")
	end

	if instance:IsA("TextLabel")
		or instance:IsA("TextButton")
		or instance:IsA("TextBox")
	then
		table.insert(properties, "TextTransparency")
		table.insert(properties, "TextStrokeTransparency")
	end

	if instance:IsA("UIStroke") then
		table.insert(properties, "Transparency")
	end

	return properties
end

local function ensureObjectiveTransparencyBaselines(panel)
	local instances = { panel }

	for _, descendant in ipairs(panel:GetDescendants()) do
		table.insert(instances, descendant)
	end

	for _, instance in ipairs(instances) do
		local baselines =
			objectivePresentation.TransparencyBaselines[instance]

		if not baselines then
			baselines = {}
			objectivePresentation.TransparencyBaselines[instance] =
				baselines
		end

		for _, property in ipairs(
			objectiveTransparencyProperties(instance)
		) do
			if baselines[property] == nil then
				baselines[property] = instance[property]
			end
		end
	end
end

local function objectiveFadeGoals(panel, hidden)
	ensureObjectiveTransparencyBaselines(panel)

	local goalsByInstance = {}

	for instance, baselines in pairs(
		objectivePresentation.TransparencyBaselines
	) do
		if instance == panel or instance:IsDescendantOf(panel) then
			local goals = {}

			for property, baseline in pairs(baselines) do
				goals[property] = hidden and 1 or baseline
			end

			if next(goals) then
				goalsByInstance[instance] = goals
			end
		end
	end

	return goalsByInstance
end

local function setObjectiveFade(panel, hidden)
	for instance, goals in pairs(
		objectiveFadeGoals(panel, hidden)
	) do
		for property, value in pairs(goals) do
			instance[property] = value
		end
	end
end

local function tweenObjectiveFade(panel, tweenInfo, hidden)
	for instance, goals in pairs(
		objectiveFadeGoals(panel, hidden)
	) do
		local fadeTween = TweenService:Create(
			instance,
			tweenInfo,
			goals
		)
		table.insert(
			objectivePresentation.Tweens,
			fadeTween
		)
		fadeTween:Play()
	end
end

local function setObjectiveVisible(panel, visible)
	if not panel
		or not panel.Parent
		or not panel:IsA("GuiObject")
	then
		return
	end

	if panel.Visible == visible then
		return
	end

	visibilityGuard = true
	panel.Visible = visible
	visibilityGuard = false
end

local function resetObjectivePresentation(panel)
	objectivePresentation.Serial += 1
	cancelObjectiveTweens()

	objectivePresentation.Panel = panel
	objectivePresentation.RestingPosition =
		panel and panel.Position or nil
	objectivePresentation.TransparencyBaselines = {}
	objectivePresentation.WantsVisible = false
	objectivePresentation.LastIdentity = nil
	objectivePresentation.LastState = nil
	objectivePresentation.LastCompleted = false

	if panel and panel.Parent then
		ensureObjectiveTransparencyBaselines(panel)
		setObjectiveVisible(panel, false)
	end
end

local function hideObjectiveNotice(immediate)
	local panel = objectivePresentation.Panel
	local restingPosition =
		objectivePresentation.RestingPosition

	objectivePresentation.Serial += 1
	local serial = objectivePresentation.Serial
	cancelObjectiveTweens()

	if not panel or not panel.Parent or not restingPosition then
		objectivePresentation.WantsVisible = false
		return
	end

	if immediate or not panel.Visible then
		objectivePresentation.WantsVisible = false
		setObjectiveVisible(panel, false)
		panel.Position = restingPosition
		setObjectiveFade(panel, false)
		return
	end

	-- Keep the watchdog from hiding the panel before the exit animation ends.
	objectivePresentation.WantsVisible = true

	local hideTweenInfo = TweenInfo.new(
		OBJECTIVE_TRANSITION_SECONDS,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	local hideTween = TweenService:Create(
		panel,
		hideTweenInfo,
		{
			Position = objectiveOffsetPosition(
				restingPosition,
				OBJECTIVE_EXIT_OFFSET_X
			),
		}
	)
	table.insert(objectivePresentation.Tweens, hideTween)
	tweenObjectiveFade(panel, hideTweenInfo, true)

	hideTween.Completed:Once(function()
		if objectivePresentation.Serial ~= serial
			or objectivePresentation.Panel ~= panel
		then
			return
		end

		table.clear(objectivePresentation.Tweens)
		objectivePresentation.WantsVisible = false
		setObjectiveVisible(panel, false)
		panel.Position = restingPosition
		setObjectiveFade(panel, false)
	end)

	hideTween:Play()
end

local function showObjectiveNotice(duration)
	local panel = objectivePresentation.Panel
	local restingPosition =
		objectivePresentation.RestingPosition

	if not panel or not panel.Parent or not restingPosition then
		return
	end

	objectivePresentation.Serial += 1
	local serial = objectivePresentation.Serial
	objectivePresentation.WantsVisible = true
	cancelObjectiveTweens()

	panel.Position = objectiveOffsetPosition(
		restingPosition,
		OBJECTIVE_ENTER_OFFSET_X
	)
	setObjectiveFade(panel, true)
	setObjectiveVisible(panel, true)

	local showTweenInfo = TweenInfo.new(
		OBJECTIVE_TRANSITION_SECONDS,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local showTween = TweenService:Create(
		panel,
		showTweenInfo,
		{
			Position = restingPosition,
		}
	)
	table.insert(objectivePresentation.Tweens, showTween)
	tweenObjectiveFade(panel, showTweenInfo, false)

	showTween.Completed:Once(function()
		if objectivePresentation.Serial == serial
			and objectivePresentation.Panel == panel
		then
			table.clear(objectivePresentation.Tweens)
		end
	end)

	showTween:Play()

	task.delay(duration, function()
		if objectivePresentation.Serial ~= serial
			or objectivePresentation.Panel ~= panel
		then
			return
		end

		hideObjectiveNotice(false)
	end)
end

local function disconnectBindingConnections()
	for _, connection in ipairs(bindingConnections) do
		connection:Disconnect()
	end
	table.clear(bindingConnections)
end

local function recordRecovery(reason, target)
	recoverySerial += 1

	player:SetAttribute(
		"DungeonArtHUDRecoverySerial",
		recoverySerial
	)
	player:SetAttribute(
		"DungeonArtHUDLastRecoveryReason",
		tostring(reason or "Unknown")
	)
	player:SetAttribute(
		"DungeonArtHUDLastRecoveryTarget",
		target and instancePath(target) or "nil"
	)
	player:SetAttribute(
		"DungeonArtHUDLastRecoveryAt",
		workspace:GetServerTimeNow()
	)
end

local function setVisibleGuarded(object, visible, reason)
	if not object
		or not object.Parent
		or not object:IsA("GuiObject")
	then
		return
	end

	if object.Visible == visible then
		return
	end

	visibilityGuard = true
	object.Visible = visible
	visibilityGuard = false

	recordRecovery(reason, object)
end

local function setEnabledGuarded(screenGui, enabled, reason)
	if not screenGui
		or not screenGui.Parent
		or not screenGui:IsA("ScreenGui")
	then
		return
	end

	if screenGui.Enabled == enabled then
		return
	end

	visibilityGuard = true
	screenGui.Enabled = enabled
	visibilityGuard = false

	recordRecovery(reason, screenGui)
end

local function enforceCoreVisibility(reason)
	if boundHud and boundHud.Parent then
		setEnabledGuarded(
			boundHud,
			true,
			reason or "WatchdogScreenGuiEnabled"
		)
		boundHud.ResetOnSpawn = false
	end

	setVisibleGuarded(
		refs.ObjectivePanel,
		objectivePresentation.WantsVisible,
		reason or "WatchdogObjectiveVisibility"
	)
	setVisibleGuarded(
		refs.PlayerStatus,
		true,
		reason or "WatchdogPlayerStatusVisible"
	)
	setVisibleGuarded(
		refs.MiniMap,
		true,
		reason or "WatchdogMiniMapVisible"
	)

	-- Missions remain intentionally hidden in the simplified MVP.
	if refs.MissionsPanel
		and refs.MissionsPanel.Parent
		and refs.MissionsPanel.Visible
	then
		visibilityGuard = true
		refs.MissionsPanel.Visible = false
		visibilityGuard = false
	end
end

local function watchVisibilityProperties()
	disconnectBindingConnections()

	if boundHud and boundHud.Parent then
		table.insert(
			bindingConnections,
			boundHud:GetPropertyChangedSignal(
				"Enabled"
			):Connect(function()
				if visibilityGuard then
					return
				end

				if not boundHud.Enabled then
					setEnabledGuarded(
						boundHud,
						true,
						"ScreenGuiEnabledChanged"
					)
				end
			end)
		)

		table.insert(
			bindingConnections,
			boundHud.AncestryChanged:Connect(function()
				dirty = true
			end)
		)
	end

	for name, panel in pairs({
		PlayerStatus = refs.PlayerStatus,
		MiniMap = refs.MiniMap,
	}) do
		if panel and panel.Parent then
			table.insert(
				bindingConnections,
				panel:GetPropertyChangedSignal(
					"Visible"
				):Connect(function()
					if visibilityGuard then
						return
					end

					if not panel.Visible then
						setVisibleGuarded(
							panel,
							true,
							name .. "VisibleChanged"
						)
					end
				end)
			)

			table.insert(
				bindingConnections,
				panel.AncestryChanged:Connect(function()
					dirty = true
				end)
			)
		end
	end

	local objectivePanel = refs.ObjectivePanel
	if objectivePanel and objectivePanel.Parent then
		table.insert(
			bindingConnections,
			objectivePanel:GetPropertyChangedSignal(
				"Visible"
			):Connect(function()
				if visibilityGuard then
					return
				end

				local expected =
					objectivePresentation.WantsVisible
				if objectivePanel.Visible ~= expected then
					setVisibleGuarded(
						objectivePanel,
						expected,
						"ObjectivePanelVisibilityChanged"
					)
				end
			end)
		)

		table.insert(
			bindingConnections,
			objectivePanel.AncestryChanged:Connect(function()
				dirty = true
			end)
		)
	end
end

local function resolveAndBind()
	local hud = ensureHud()

	if not hud then
		player:SetAttribute(
			"DungeonArtHUDControllerReady",
			false
		)
		player:SetAttribute(
			"DungeonArtHUDWaitingForAuthoredHUD",
			true
		)
		player:SetAttribute(
			"DungeonArtHUDFailure",
			"WaitingForStarterGuiDungeonHUD"
		)
		return false
	end

	local core = resolveCore(hud)
	local objectivePanelChanged =
		core.ObjectivePanel ~= refs.ObjectivePanel

	local changed =
		hud ~= boundHud
		or objectivePanelChanged
		or core.PlayerStatus
			~= refs.PlayerStatus
		or core.MiniMap
			~= refs.MiniMap
		or core.MissionsPanel
			~= refs.MissionsPanel

	if changed then
		boundHud = hud
		bindSerial += 1

		refs.ObjectivePanel =
			core.ObjectivePanel
		refs.PlayerStatus =
			core.PlayerStatus
		refs.MiniMap =
			core.MiniMap
		refs.MissionsPanel =
			core.MissionsPanel

		if objectivePanelChanged then
			resetObjectivePresentation(
				refs.ObjectivePanel
			)
		end

		refs.Objective =
			bindObjective(
				refs.ObjectivePanel
			)
		refs.Status =
			bindStatus(
				refs.PlayerStatus
			)
		refs.Map =
			bindMinimap(
				refs.MiniMap
			)

		if refs.MissionsPanel then
			refs.MissionsPanel:SetAttribute(
				"RuntimeDisabledReason",
				"SimplifiedCombatMVP"
			)
		end

		watchVisibilityProperties()
		enforceCoreVisibility(
			"NewBinding"
		)

		setText(
			refs.Status.PlayerName,
			player.DisplayName
		)

		ensureStaticPortrait()

		reportBinding()
	end

	enforceCoreVisibility(
		"ResolveAndBindWatchdog"
	)

	local coreCount = 0
	if refs.ObjectivePanel then coreCount += 1 end
	if refs.PlayerStatus then coreCount += 1 end
	if refs.MiniMap then coreCount += 1 end

	player:SetAttribute(
		"DungeonArtHUDResolvedCoreCount",
		coreCount
	)
	player:SetAttribute(
		"DungeonArtHUDObjectiveResolved",
		refs.ObjectivePanel ~= nil
	)
	player:SetAttribute(
		"DungeonArtHUDPlayerStatusResolved",
		refs.PlayerStatus ~= nil
	)
	player:SetAttribute(
		"DungeonArtHUDMiniMapResolved",
		refs.MiniMap ~= nil
	)

	-- The controller remains alive even when one panel is temporarily absent.
	local ready = coreCount > 0

	player:SetAttribute(
		"DungeonArtHUDControllerReady",
		ready
	)
	player:SetAttribute(
		"DungeonUnifiedHUDReady",
		ready
	)
	player:SetAttribute(
		"DungeonArtHUDWaitingForAuthoredHUD",
		not ready
	)
	player:SetAttribute(
		"DungeonArtHUDFailure",
		ready and nil
			or "AuthoredCorePanelsNotResolvedYet"
	)
	player:SetAttribute(
		"DungeonArtHUDBindingVersion",
		VERSION
	)
	player:SetAttribute(
		"DungeonArtHUDBindSerial",
		bindSerial
	)

	if boundHud then
		boundHud:SetAttribute(
			"ControllerReady",
			ready
		)
	end

	return ready
end

---------------------------------------------------------------------
-- Objective renderer
---------------------------------------------------------------------

local function syncObjective()
	local objective = refs.Objective

	if not objective or not objective.Panel then
		return
	end

	local title =
		workspace:GetAttribute(
			"DungeonObjectiveTitle"
		)
		or "Objetivo"

	local description =
		workspace:GetAttribute(
			"DungeonObjectiveDescription"
		)
		or ""

	local progress = math.max(
		0,
		tonumber(
			workspace:GetAttribute(
				"DungeonObjectiveProgress"
			)
		) or 0
	)

	local target = math.max(
		1,
		tonumber(
			workspace:GetAttribute(
				"DungeonObjectiveTarget"
			)
		) or 1
	)

	local state = tostring(
		workspace:GetAttribute(
			"DungeonObjectiveState"
		)
		or "Inactive"
	)

	local objectiveIdentity = table.concat({
		tostring(
			workspace:GetAttribute(
				"DungeonObjectiveId"
			)
			or ""
		),
		tostring(
			workspace:GetAttribute(
				"DungeonObjectiveGlobalIslandIndex"
			)
			or workspace:GetAttribute(
				"DungeonCurrentObjectiveIsland"
			)
			or ""
		),
		tostring(math.floor(target)),
	}, "|")

	setText(objective.Title, title)
	setText(
		objective.Description,
		description
	)
	setText(
		objective.Counter,
		string.format(
			"%d / %d",
			math.floor(progress),
			math.floor(target)
		)
	)

	local ratio = math.clamp(
		progress / target,
		0,
		1
	)

	if objective.ProgressFill
		and objective.FullX
	then
		local y =
			objective.ProgressFill.Size.Y

		tween(
			objective.ProgressFill,
			0.15,
			{
				Size = UDim2.new(
					objective.FullX.Scale
						* ratio,
					math.floor(
						objective.FullX.Offset
							* ratio
							+ 0.5
					),
					y.Scale,
					y.Offset
				),
			}
		)
	end

	if objective.CompletedIcon then
		objective.CompletedIcon.Visible =
			state == "Completed"
			or ratio >= 1
	end

	local inactive = state == "Inactive"
	local completed =
		state == "Completed" or ratio >= 1
	local identityChanged =
		objectivePresentation.LastIdentity
			~= objectiveIdentity
	local becameActive =
		objectivePresentation.LastState == "Inactive"
		and not inactive
	local becameCompleted =
		completed
		and not objectivePresentation.LastCompleted

	if inactive then
		if objectivePresentation.WantsVisible then
			hideObjectiveNotice(true)
		end
	elseif becameCompleted then
		showObjectiveNotice(
			OBJECTIVE_COMPLETION_SECONDS
		)
	elseif identityChanged or becameActive then
		showObjectiveNotice(
			OBJECTIVE_NOTICE_SECONDS
		)
	end

	objectivePresentation.LastIdentity =
		objectiveIdentity
	objectivePresentation.LastState = state
	objectivePresentation.LastCompleted = completed
end

---------------------------------------------------------------------
-- Player status renderer
---------------------------------------------------------------------

local function syncStatus()
	local status = refs.Status

	if not status or not status.Panel then
		return
	end

	ensureStaticPortrait()

	setText(
		status.PlayerName,
		player.DisplayName
	)

	local level = math.max(
		1,
		math.floor(
			tonumber(
				player:GetAttribute(
					"PlayerLevel"
				)
			) or 1
		)
	)

	local xp = math.max(
		0,
		math.floor(
			tonumber(
				player:GetAttribute(
					"PlayerXP"
				)
			) or 0
		)
	)

	local xpTarget = math.max(
		0,
		math.floor(
			tonumber(
				player:GetAttribute(
					"PlayerXPToNextLevel"
				)
			) or 0
		)
	)

	setText(
		status.LevelText,
		tostring(level)
	)

	setBar(
		status.XPBar,
		xpTarget > 0
			and xp / xpTarget
			or 1,
		xpTarget > 0
			and string.format(
				"%d / %d XP",
				xp,
				xpTarget
			)
			or "MAX"
	)

	local character = player.Character
	local humanoid =
		character
		and character:FindFirstChildOfClass(
			"Humanoid"
		)

	if humanoid then
		local health = math.max(
			0,
			humanoid.Health
		)
		local maximum = math.max(
			1,
			humanoid.MaxHealth
		)

		setBar(
			status.HealthBar,
			health / maximum,
			string.format(
				"%d / %d",
				math.floor(health + 0.5),
				math.floor(maximum + 0.5)
			)
		)
	end

	if character then
		local stamina =
			tonumber(
				character:GetAttribute(
					"SprintStamina"
				)
			)

		local staminaMax =
			tonumber(
				character:GetAttribute(
					"SprintStaminaMax"
				)
			)

		if stamina ~= nil
			and staminaMax
			and staminaMax > 0
		then
			setBar(
				status.StaminaBar,
				stamina / staminaMax,
				string.format(
					"%.1f / %.1f",
					math.max(
						0,
						stamina
					),
					staminaMax
				)
			)
		end
	end
end

---------------------------------------------------------------------
-- Lightweight authored minimap
---------------------------------------------------------------------

local islandMarkers = {}
local hostileMarkers = {}

local function markerWorldPosition(markerFolder)
	if not markerFolder or not markerFolder.Parent then
		return nil
	end

	local island = markerFolder.Parent

	local floor =
		island:FindFirstChild(
			"IslandFloor",
			true
		)

	if floor and floor:IsA("BasePart") then
		return floor.Position, island
	end

	if island:IsA("Model") then
		return island:GetPivot().Position,
			island
	end

	return nil
end

local function chooseIslandTemplate(
	mapRefs,
	island
)
	if not mapRefs or not island then
		return nil
	end

	local sizeName = tostring(
		island:GetAttribute("SizeName")
			or island:GetAttribute(
				"IslandSize"
			)
			or ""
	)

	local normalized = normalize(sizeName)

	if string.find(
		normalized,
		"large",
		1,
		true
	) then
		return mapRefs.LargeIslandTemplate
	elseif string.find(
		normalized,
		"medium",
		1,
		true
	) then
		return mapRefs.MediumIslandTemplate
	end

	return mapRefs.SmallIslandTemplate
		or mapRefs.MediumIslandTemplate
		or mapRefs.LargeIslandTemplate
end

local function cloneTemplate(
	template,
	name,
	parent
)
	if not template
		or not parent
	then
		return nil
	end

	local clone = template:Clone()
	clone.Name = name
	clone.Visible = true
	clone.AnchorPoint =
		Vector2.new(0.5, 0.5)
	clone:SetAttribute(
		"RuntimeCloneOfAuthoredTemplate",
		true
	)
	clone.Parent = parent

	return clone
end

local function mapPosition(
	mapRefs,
	worldPosition,
	playerRoot
)
	if not mapRefs
		or not mapRefs.MapArea
		or not worldPosition
		or not playerRoot
	then
		return nil
	end

	local area = mapRefs.MapArea
	local size = area.AbsoluteSize

	if size.X <= 2 or size.Y <= 2 then
		return nil
	end

	local range = tonumber(
		mapRefs.Panel:GetAttribute(
			"MapRangeStuds"
		)
	) or 420

	local delta =
		worldPosition
		- playerRoot.Position

	local planar =
		Vector2.new(
			delta.X,
			-delta.Z
		)

	if planar.Magnitude > range then
		return nil
	end

	local radius =
		math.min(
			size.X,
			size.Y
		) * 0.43

	local offset =
		planar / range * radius

	return UDim2.fromOffset(
		math.floor(
			size.X * 0.5
				+ offset.X
				+ 0.5
		),
		math.floor(
			size.Y * 0.5
				- offset.Y
				+ 0.5
		)
	)
end

local function syncMinimap()
	local mapRefs = refs.Map

	if not mapRefs
		or not mapRefs.Panel
		or not mapRefs.MapArea
	then
		return
	end

	local character = player.Character
	local root =
		character
		and character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root then
		return
	end

	if mapRefs.PlayerArrow then
		mapRefs.PlayerArrow.Visible = true
		mapRefs.PlayerArrow.AnchorPoint =
			Vector2.new(0.5, 0.5)

		mapRefs.PlayerArrow.Position =
			UDim2.fromScale(0.5, 0.5)

		local look =
			root.CFrame.LookVector

		mapRefs.PlayerArrow.Rotation =
			math.deg(
				math.atan2(
					look.X,
					-look.Z
				)
			)
	end

	local seenIslands = {}

	if mapRefs.IslandContainer then
		for _, folder in ipairs(
			CollectionService:GetTagged(
				"DungeonGameplayMarkers"
			)
		) do
			if folder:IsA("Folder")
				and folder.Parent
			then
				local worldPosition,
					island =
						markerWorldPosition(
							folder
						)

				if worldPosition
					and island
				then
					local position =
						mapPosition(
							mapRefs,
							worldPosition,
							root
						)

					if position then
						seenIslands[folder] =
							true

						local marker =
							islandMarkers[folder]

						local template =
							chooseIslandTemplate(
								mapRefs,
								island
							)

						if template
							and (
								not marker
								or not marker.Parent
							)
						then
							marker =
								cloneTemplate(
									template,
									"Island_"
										.. island.Name,
									mapRefs
										.IslandContainer
								)
							islandMarkers[folder] =
								marker
						end

						if marker then
							marker.Position =
								position
							marker.Visible =
								true

							local levelText =
								text(
									marker,
									{
										"LevelText",
										"Level",
										"RecommendedLevel",
									}
								)

							setText(
								levelText,
								tostring(
									island:GetAttribute(
										"RecommendedLevel"
									)
										or island:GetAttribute(
											"IslandLevel"
										)
										or ""
								)
							)
						end
					end
				end
			end
		end
	end

	for source, marker in pairs(
		islandMarkers
	) do
		if not seenIslands[source]
			or not source.Parent
		then
			if marker and marker.Parent then
				marker:Destroy()
			end
			islandMarkers[source] = nil
		end
	end

	local seenMobs = {}

	if mapRefs.MarkerContainer
		and mapRefs.HostileMobTemplate
	then
		for _, target in ipairs(
			CollectionService:GetTagged(
				"CombatTarget"
			)
		) do
			if target:IsA("Model")
				and target.Parent
				and target:GetAttribute(
					"Peaceful"
				) ~= true
			then
				local targetRoot =
					target:FindFirstChild(
						"HumanoidRootPart",
						true
					)
						or target.PrimaryPart

				if targetRoot
					and targetRoot:IsA(
						"BasePart"
					)
				then
					local position =
						mapPosition(
							mapRefs,
							targetRoot.Position,
							root
						)

					if position then
						seenMobs[target] =
							true

						local marker =
							hostileMarkers[target]

						if not marker
							or not marker.Parent
						then
							marker =
								cloneTemplate(
									mapRefs
										.HostileMobTemplate,
									"HostileMob",
									mapRefs
										.MarkerContainer
								)

							hostileMarkers[target] =
								marker
						end

						if marker then
							marker.Position =
								position
							marker.Visible =
								true
						end
					end
				end
			end
		end
	end

	for source, marker in pairs(
		hostileMarkers
	) do
		if not seenMobs[source]
			or not source.Parent
		then
			if marker and marker.Parent then
				marker:Destroy()
			end
			hostileMarkers[source] = nil
		end
	end
end

---------------------------------------------------------------------
-- Persistent resolver / recovery loop
---------------------------------------------------------------------

dirty = true
local elapsed = 0
local mapElapsed = 0
local menuOpen = false

local function markDirty()
	dirty = true
end

local function forceRecover(reason)
	dirty = true

	task.defer(function()
		resolveAndBind()
		enforceCoreVisibility(
			reason or "ForceRecover"
		)
		syncObjective()
		syncStatus()
	end)
end

playerGui.DescendantAdded:Connect(
	markDirty
)
playerGui.DescendantRemoving:Connect(
	markDirty
)
StarterGui.DescendantAdded:Connect(
	markDirty
)
StarterGui.DescendantRemoving:Connect(
	markDirty
)

player.CharacterAdded:Connect(function(character)
	destroyPortraitViewport()
	bindPortraitCharacterSignals(
		character
	)

	forceRecover(
		"CharacterAdded"
	)

	task.delay(
		0.2,
		rebuildPortraitSoon
	)
end)

player.CharacterAppearanceLoaded:Connect(
	function(character)
		if character == player.Character then
			rebuildPortraitSoon()
		end
	end
)

GuiService.MenuOpened:Connect(function()
	menuOpen = true
	player:SetAttribute(
		"DungeonRobloxMenuOpen",
		true
	)
end)

GuiService.MenuClosed:Connect(function()
	menuOpen = false
	player:SetAttribute(
		"DungeonRobloxMenuOpen",
		false
	)

	-- The CoreGui menu/Settings overlay has just released the viewport.
	-- Re-resolve and restore the authored HUD immediately and once again on
	-- the next rendered frame to cover Roblox/Studio ordering races.
	forceRecover(
		"RobloxMenuClosed"
	)

	task.spawn(function()
		RunService.RenderStepped:Wait()
		forceRecover(
			"RobloxMenuClosedNextFrame"
		)
	end)
end)

-- If another system adds a duplicate DungeonHUD after character load,
-- preserve the currently bound one and remove only the duplicate.
playerGui.ChildAdded:Connect(function(child)
	if not child:IsA("ScreenGui")
		or normalize(child.Name)
			~= normalize("DungeonHUD")
	then
		return
	end

	task.defer(function()
		local current = boundHud

		if current
			and current.Parent == playerGui
			and child.Parent == playerGui
			and child ~= current
		then
			child:Destroy()
		end

		dirty = true
	end)
end)

RunService.Heartbeat:Connect(function(dt)
	elapsed += dt

	if dirty or elapsed >= 0.25 then
		elapsed = 0
		dirty = false

		resolveAndBind()

		-- Critical V15 behavior:
		-- visibility is enforced every watchdog pass, not only when the
		-- Instance references change.
		enforceCoreVisibility(
			menuOpen
				and "WatchdogWhileRobloxMenuOpen"
				or "Watchdog"
		)

		syncObjective()
		syncStatus()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	mapElapsed += dt

	if mapElapsed < 0.10 then
		return
	end

	mapElapsed = 0

	-- If the bound objects were destroyed, recovery occurs on next Heartbeat.
	if boundHud and not boundHud.Parent then
		dirty = true
		return
	end

	syncMinimap()
end)

-- Workspace objective changes also refresh immediately.
for _, attribute in ipairs({
	"DungeonObjectiveId",
	"DungeonObjectiveState",
	"DungeonObjectiveTitle",
	"DungeonObjectiveDescription",
	"DungeonObjectiveProgress",
	"DungeonObjectiveTarget",
	"DungeonObjectiveGlobalIslandIndex",
	"DungeonCurrentObjectiveIsland",
}) do
	workspace:GetAttributeChangedSignal(
		attribute
	):Connect(function()
		syncObjective()
	end)
end

-- Player progression changes refresh immediately.
for _, attribute in ipairs({
	"PlayerLevel",
	"PlayerXP",
	"PlayerXPToNextLevel",
}) do
	player:GetAttributeChangedSignal(
		attribute
	):Connect(function()
		syncStatus()
	end)
end

workspace:SetAttribute(
	"DungeonAuthoredHUDControllerVersion",
	VERSION
)

player:SetAttribute(
	"DungeonArtHUDMode",
	"ContextualObjectiveMenuSafeAuthoredOnly"
)
player:SetAttribute(
	"DungeonRobloxMenuOpen",
	GuiService.MenuIsOpen
)
player:SetAttribute(
	"DungeonArtHUDCreatesVisuals",
	false
)

-- Initial attempt. Failure here is harmless: the loop continues forever.
resolveAndBind()
syncObjective()
syncStatus()
ensureStaticPortrait()

print(
	"[AuthoredHUD V18] HUD contextual + retrato 3D frontal estatico ativo. "
		.. "DungeonHUD exato; sem timeout fatal; "
		.. "ObjectivePanel temporario e protegido."
)
