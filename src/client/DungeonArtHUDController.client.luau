local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local VERSION = "AuthoredHUDV19SafeIntegration"

local aliases = {
	ObjectivePanel = {"ObjectivePanel", "Objective", "ObjectiveFrame", "ObjectiveContainer", "ObjectiveHolder"},
	PlayerStatus = {"PlayerStatus", "Status", "PlayerStatusFrame", "StatusPanel", "PlayerHUD", "PlayerInfo"},
	MiniMap = {"MiniMap", "Minimap", "Map", "MiniMapFrame", "MapPanel", "Radar"},
	MissionsPanel = {"MissionsPanel", "Missions", "MissionPanel", "QuestPanel", "QuestsPanel", "QuestListPanel"},
}

local tags = {
	ObjectivePanel = "DungeonHUD_Objective",
	PlayerStatus = "DungeonHUD_PlayerStatus",
	MiniMap = "DungeonHUD_Minimap",
	MissionsPanel = "DungeonHUD_Missions",
}

local hud
local refs = {}
local dirty = true
local elapsed = 0
local mapElapsed = 0
local menuOpen = false
local objectiveState = {panel = nil, position = nil, serial = 0, visible = false, identity = nil, state = nil, completed = false}
local islandMarkers = {}
local hostileMarkers = {}
local portrait = {host = nil, viewport = nil, character = nil, pending = false}
local connections = {}

local function normalize(value)
	return string.lower(string.gsub(tostring(value or ""), "[^%w]", ""))
end

local function isGui(object)
	return object and object:IsA("GuiObject")
end

local function isText(object)
	return object and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
end

local function isImage(object)
	return object and (object:IsA("ImageLabel") or object:IsA("ImageButton"))
end

local function allIncludingRoot(root)
	local result = {}
	if not root then return result end
	table.insert(result, root)
	for _, object in ipairs(root:GetDescendants()) do table.insert(result, object) end
	return result
end

local function score(name, wanted)
	local actual = normalize(name)
	local best = 0
	for _, alias in ipairs(wanted) do
		local value = normalize(alias)
		if actual == value then best = math.max(best, 100)
		elseif #value >= 5 and string.find(actual, value, 1, true) then best = math.max(best, 70)
		elseif #actual >= 5 and string.find(value, actual, 1, true) then best = math.max(best, 60) end
	end
	return best
end

local function findBest(root, wanted, predicate, tagName)
	if not root then return nil end
	if tagName then
		for _, object in ipairs(CollectionService:GetTagged(tagName)) do
			if object.Parent and object:IsDescendantOf(root) and (not predicate or predicate(object)) then return object end
		end
	end
	local bestObject
	local bestScore = 0
	local bestDepth = math.huge
	for _, object in ipairs(allIncludingRoot(root)) do
		if (not predicate or predicate(object)) then
			local objectScore = score(object.Name, wanted)
			local depth = 0
			local current = object
			while current and current ~= root do depth += 1; current = current.Parent end
			if objectScore > bestScore or (objectScore == bestScore and objectScore > 0 and depth < bestDepth) then
				bestObject, bestScore, bestDepth = object, objectScore, depth
			end
		end
	end
	return bestObject
end

local function findScreenGui(root, name)
	if not root then return nil end
	local direct = root:FindFirstChild(name)
	if direct and direct:IsA("ScreenGui") then return direct end
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("ScreenGui") and normalize(object.Name) == normalize(name) then return object end
	end
	return nil
end

local function ensureHud()
	local current = findScreenGui(playerGui, "DungeonHUD")
	if not current then
		local source = findScreenGui(StarterGui, "DungeonHUD")
		if source then
			current = source:Clone()
			current.Name = "DungeonHUD"
			current:SetAttribute("ClonedByDungeonArtHUDController", true)
			current.Parent = playerGui
		end
	end
	if current then
		current.Enabled = true
		current.ResetOnSpawn = false
		current:SetAttribute("ResponsiveGenericOptOut", true)
		current:SetAttribute("ControllerVersion", VERSION)
	end
	return current
end

local function text(root, wanted)
	return findBest(root, wanted, isText)
end

local function gui(root, wanted)
	return findBest(root, wanted, isGui)
end

local function setText(object, value)
	if isText(object) then object.Text = tostring(value or "") end
end

local function resolveBar(root, wanted)
	local bar = gui(root, wanted)
	if not bar then return nil end
	local fill = gui(bar, {"Fill", "ProgressFill", "BarFill", "ValueFill", "Foreground"})
	local background = gui(bar, {"Background", "ProgressBackground", "BarBackground", "Track"})
	local value = text(bar, {"Value", "ValueText", "Counter", "ProgressText", "Amount", "Text"})
	local fullX = fill and fill.Size.X or nil
	if fill and background and fill.Parent == background then fullX = UDim.new(1, 0) end
	return {Root = bar, Fill = fill, Background = background, Value = value, FullX = fullX}
end

local function setBar(bar, ratio, value)
	if not bar then return end
	setText(bar.Value, value)
	if bar.Fill and bar.FullX then
		ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
		local y = bar.Fill.Size.Y
		TweenService:Create(bar.Fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(bar.FullX.Scale * ratio, math.floor(bar.FullX.Offset * ratio + 0.5), y.Scale, y.Offset)}):Play()
	end
end

local function bindStatus(panel)
	if not panel then return nil end
	local portraitRoot = gui(panel, {"Portrait", "PlayerPortrait", "AvatarHolder", "AvatarContainer"}) or panel
	return {
		Panel = panel,
		PlayerName = text(panel, {"PlayerName", "DisplayName", "NameLabel", "Username"}),
		Portrait = portraitRoot,
		AvatarImage = findBest(portraitRoot, {"AvatarImage", "Avatar", "Headshot", "PlayerImage"}, isImage),
		LevelText = text(portraitRoot, {"LevelText", "Level", "Lvl", "PlayerLevel"}) or text(panel, {"LevelText", "Level", "Lvl", "PlayerLevel"}),
		HealthBar = resolveBar(panel, {"HealthBar", "HPBar", "Health", "Vida"}),
		StaminaBar = resolveBar(panel, {"StaminaBar", "EnergyBar", "Stamina", "Energia"}),
		XPBar = resolveBar(panel, {"XPBar", "ExperienceBar", "ExpBar", "XP", "Experience"}),
	}
end

local function bindMinimap(panel)
	if not panel then return nil end
	local area = gui(panel, {"MapArea", "MapContent", "ContentArea", "RadarArea"}) or panel
	local islands = gui(area, {"IslandContainer", "IslandsContainer", "Islands", "IslandLayer"})
	local markers = gui(area, {"MarkerContainer", "MarkersContainer", "Markers", "MarkerLayer"})
	local result = {Panel = panel, MapArea = area, IslandContainer = islands, MarkerContainer = markers, PlayerArrow = gui(area, {"PlayerArrow", "PlayerMarker", "PlayerIcon", "Arrow"})}
	if islands then
		result.SmallIslandTemplate = gui(islands, {"SmallIslandTemplate", "SmallIsland", "IslandSmall"})
		result.MediumIslandTemplate = gui(islands, {"MediumIslandTemplate", "MediumIsland", "IslandMedium"})
		result.LargeIslandTemplate = gui(islands, {"LargeIslandTemplate", "LargeIsland", "IslandLarge"})
	end
	if markers then result.HostileMobTemplate = gui(markers, {"HostileMobMarker", "HostileMarker", "EnemyMarker", "MobMarker"}) end
	for _, template in ipairs({result.SmallIslandTemplate, result.MediumIslandTemplate, result.LargeIslandTemplate, result.HostileMobTemplate}) do if template then template.Visible = false end end
	return result
end

local function resolve()
	local candidate = ensureHud()
	if candidate ~= hud then
		hud = candidate
		refs.ObjectivePanel = findBest(hud, aliases.ObjectivePanel, isGui, tags.ObjectivePanel)
		refs.PlayerStatus = findBest(hud, aliases.PlayerStatus, isGui, tags.PlayerStatus)
		refs.MiniMap = findBest(hud, aliases.MiniMap, isGui, tags.MiniMap)
		refs.MissionsPanel = findBest(hud, aliases.MissionsPanel, isGui, tags.MissionsPanel)
		refs.Status = bindStatus(refs.PlayerStatus)
		refs.Map = bindMinimap(refs.MiniMap)
		objectiveState.panel = refs.ObjectivePanel
		objectiveState.position = refs.ObjectivePanel and refs.ObjectivePanel.Position or nil
		if refs.ObjectivePanel then refs.ObjectivePanel.Visible = false end
		if refs.MissionsPanel then refs.MissionsPanel:SetAttribute("RuntimeDisabledReason", "SimplifiedCombatMVP") end
		player:SetAttribute("DungeonHUDPanelsBound", refs.PlayerStatus ~= nil or refs.MiniMap ~= nil)
		player:SetAttribute("DungeonArtHUDBindReport", string.format("%s | PlayerStatus=%s | MiniMap=%s", hud and hud:GetFullName() or "nil", tostring(refs.PlayerStatus ~= nil), tostring(refs.MiniMap ~= nil)))
		print("[DungeonArtHUDController] DungeonHUD bound: PlayerStatus=" .. tostring(refs.PlayerStatus ~= nil) .. " MiniMap=" .. tostring(refs.MiniMap ~= nil))
	end
	if not hud then
		player:SetAttribute("DungeonHUDPanelsBound", false)
		return false
	end
	return true
end

local function makePortrait(host, character)
	if not host or not host.Parent or not character or not character.Parent then return end
	if portrait.host == host and portrait.character == character and portrait.viewport and portrait.viewport.Parent then return end
	if portrait.viewport then portrait.viewport:Destroy() end
	local clone
	local oldArchivable = character.Archivable
	character.Archivable = true
	local ok = pcall(function() clone = character:Clone() end)
	character.Archivable = oldArchivable
	if not ok or not clone then return end
	for _, object in ipairs(clone:GetDescendants()) do
		if object:IsA("BaseScript") or object:IsA("Animator") or object:IsA("AnimationController") or object:IsA("BillboardGui") or object:IsA("SurfaceGui") or object:IsA("Highlight") then object:Destroy()
		elseif object:IsA("Motor6D") then object.Transform = CFrame.identity
		elseif object:IsA("BasePart") then object.Anchored = true; object.CanCollide = false; object.CanTouch = false; object.CanQuery = false end
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "DungeonCharacterViewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = true
	viewport.Parent = host
	local world = Instance.new("WorldModel")
	world.Name = "PortraitWorld"
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.Name = "PortraitCamera"
	camera.FieldOfView = 28
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	clone.Parent = world
	clone:PivotTo(CFrame.Angles(0, math.rad(180), 0))
	local box, size = clone:GetBoundingBox()
	local distance = math.max(4, size.Y * 0.5 / math.tan(math.rad(14)) * 1.08, size.X * 1.8, size.Z * 2.2)
	local target = box.Position + Vector3.new(0, size.Y * 0.035, 0)
	camera.CFrame = CFrame.lookAt(target + Vector3.new(0, size.Y * 0.015, distance), target)
	if host:IsA("ImageLabel") or host:IsA("ImageButton") then host.ImageTransparency = 1 end
	portrait.host, portrait.viewport, portrait.character = host, viewport, character
	player:SetAttribute("DungeonPortrait3DReady", true)
end

local function syncStatus()
	local status = refs.Status
	if not status or not status.Panel then return end
	local level = math.max(1, math.floor(tonumber(player:GetAttribute("PlayerLevel")) or tonumber(player:GetAttribute("Level")) or 1))
	local xp = math.max(0, math.floor(tonumber(player:GetAttribute("PlayerXP")) or tonumber(player:GetAttribute("XP")) or 0))
	local xpTarget = math.max(0, math.floor(tonumber(player:GetAttribute("PlayerXPToNextLevel")) or tonumber(player:GetAttribute("XPToNextLevel")) or 0))
	setText(status.PlayerName, player.DisplayName)
	setText(status.LevelText, tostring(level))
	setBar(status.XPBar, xpTarget > 0 and xp / xpTarget or 1, xpTarget > 0 and string.format("%d / %d XP", xp, xpTarget) or "MAX")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then setBar(status.HealthBar, humanoid.Health / math.max(1, humanoid.MaxHealth), string.format("%d / %d", math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth + 0.5))) end
	if character then
		local stamina = tonumber(character:GetAttribute("SprintStamina"))
		local maximum = tonumber(character:GetAttribute("SprintStaminaMax"))
		if stamina and maximum and maximum > 0 then setBar(status.StaminaBar, stamina / maximum, string.format("%.1f / %.1f", math.max(0, stamina), maximum)) end
	end
	local host = status.AvatarImage or status.Portrait
	if host then makePortrait(host, character) end
end

local function syncObjective()
	local panel = refs.ObjectivePanel
	if not panel then return end
	local title = workspace:GetAttribute("DungeonObjectiveTitle") or "Objetivo"
	local description = workspace:GetAttribute("DungeonObjectiveDescription") or ""
	local progress = math.max(0, tonumber(workspace:GetAttribute("DungeonObjectiveProgress")) or 0)
	local target = math.max(1, tonumber(workspace:GetAttribute("DungeonObjectiveTarget")) or 1)
	local state = tostring(workspace:GetAttribute("DungeonObjectiveState") or "Inactive")
	setText(text(panel, {"Title", "ObjectiveTitle", "Titulo"}), title)
	setText(text(panel, {"Description", "ObjectiveDescription", "Descricao", "Detail"}), description)
	setText(text(panel, {"Counter", "ProgressText", "ObjectiveCounter", "Count"}), string.format("%d / %d", math.floor(progress), math.floor(target)))
	local fill = gui(panel, {"ProgressFill", "BarFill", "Fill"})
	local background = gui(panel, {"ProgressBackground", "BarBackground", "Track"})
	if fill then
		local full = background and background.Size.X or fill.Size.X
		local y = fill.Size.Y
		fill.Size = UDim2.new(full.Scale * math.clamp(progress / target, 0, 1), math.floor(full.Offset * math.clamp(progress / target, 0, 1) + 0.5), y.Scale, y.Offset)
	end
	local completed = state == "Completed" or progress >= target
	local identity = tostring(workspace:GetAttribute("DungeonObjectiveId") or "") .. "|" .. tostring(target)
	if state == "Inactive" then panel.Visible = false
	elseif identity ~= objectiveState.identity or state ~= objectiveState.state then
		objectiveState.identity, objectiveState.state = identity, state
		panel.Visible = true
		local resting = objectiveState.position or panel.Position
		panel.Position = UDim2.new(resting.X.Scale, resting.X.Offset - 48, resting.Y.Scale, resting.Y.Offset)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = resting}):Play()
		task.delay(completed and 2.75 or 6, function() if panel.Parent and objectiveState.identity == identity then panel.Visible = false end end)
	end
end

local function markerPosition(folder)
	local island = folder and folder.Parent
	if not island then return nil end
	local floor = island:FindFirstChild("IslandFloor", true)
	if floor and floor:IsA("BasePart") then return floor.Position, island end
	if island:IsA("Model") then return island:GetPivot().Position, island end
end

local function mapPosition(map, worldPosition, root)
	if not map or not map.MapArea or not worldPosition or not root then return nil end
	local size = map.MapArea.AbsoluteSize
	if size.X <= 2 or size.Y <= 2 then return nil end
	local range = tonumber(map.Panel:GetAttribute("MapRangeStuds")) or 420
	local delta = worldPosition - root.Position
	local planar = Vector2.new(delta.X, -delta.Z)
	if planar.Magnitude > range then return nil end
	local radius = math.min(size.X, size.Y) * 0.43
	local offset = planar / range * radius
	return UDim2.fromOffset(math.floor(size.X * 0.5 + offset.X + 0.5), math.floor(size.Y * 0.5 - offset.Y + 0.5))
end

local function cloneMarker(template, name, parent)
	if not template or not parent then return nil end
	local marker = template:Clone()
	marker.Name = name
	marker.Visible = true
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker:SetAttribute("RuntimeCloneOfAuthoredTemplate", true)
	marker.Parent = parent
	return marker
end

local function syncMinimap()
	local map = refs.Map
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not map or not root then return end
	if map.PlayerArrow then map.PlayerArrow.Visible = true; map.PlayerArrow.AnchorPoint = Vector2.new(0.5, 0.5); map.PlayerArrow.Position = UDim2.fromScale(0.5, 0.5); local look = root.CFrame.LookVector; map.PlayerArrow.Rotation = math.deg(math.atan2(look.X, -look.Z)) end
	local seen = {}
	if map.IslandContainer then
		for _, folder in ipairs(CollectionService:GetTagged("DungeonGameplayMarkers")) do
			local position, island = markerPosition(folder)
			local screenPosition = mapPosition(map, position, root)
			if screenPosition and island then
				seen[folder] = true
				local marker = islandMarkers[folder]
				if not marker or not marker.Parent then marker = cloneMarker(map.SmallIslandTemplate or map.MediumIslandTemplate or map.LargeIslandTemplate, "Island_" .. island.Name, map.IslandContainer); islandMarkers[folder] = marker end
				if marker then marker.Position = screenPosition; marker.Visible = true; setText(text(marker, {"LevelText", "Level", "RecommendedLevel"}), island:GetAttribute("RecommendedLevel") or island:GetAttribute("IslandLevel") or "") end
			end
		end
	end
	for source, marker in pairs(islandMarkers) do if not seen[source] or not source.Parent then if marker.Parent then marker:Destroy() end; islandMarkers[source] = nil end end
	local seenMobs = {}
	if map.MarkerContainer and map.HostileMobTemplate then
		for _, target in ipairs(CollectionService:GetTagged("CombatTarget")) do
			if target:IsA("Model") and target.Parent and target:GetAttribute("Peaceful") ~= true then
				local targetRoot = target:FindFirstChild("HumanoidRootPart", true) or target.PrimaryPart
				local screenPosition = targetRoot and mapPosition(map, targetRoot.Position, root)
				if screenPosition then
					seenMobs[target] = true
					local marker = hostileMarkers[target]
					if not marker or not marker.Parent then marker = cloneMarker(map.HostileMobTemplate, "HostileMob", map.MarkerContainer); hostileMarkers[target] = marker end
					if marker then marker.Position = screenPosition; marker.Visible = true end
				end
			end
		end
	end
	for source, marker in pairs(hostileMarkers) do if not seenMobs[source] or not source.Parent then if marker.Parent then marker:Destroy() end; hostileMarkers[source] = nil end end
end

local function recover()
	dirty = true
	resolve()
	if hud then hud.Enabled = true end
	if refs.PlayerStatus then refs.PlayerStatus.Visible = true end
	if refs.MiniMap then refs.MiniMap.Visible = true end
	syncStatus()
	syncObjective()
end

playerGui.DescendantAdded:Connect(function() dirty = true end)
playerGui.DescendantRemoving:Connect(function() dirty = true end)
StarterGui.DescendantAdded:Connect(function() dirty = true end)
StarterGui.DescendantRemoving:Connect(function() dirty = true end)
player.CharacterAdded:Connect(function(character)
	portrait.host, portrait.viewport, portrait.character = nil, nil, nil
	character:WaitForChild("Humanoid", 5)
	recover()
end)
GuiService.MenuOpened:Connect(function() menuOpen = true end)
GuiService.MenuClosed:Connect(function() menuOpen = false; recover() end)
for _, attribute in ipairs({"PlayerLevel", "PlayerXP", "PlayerXPToNextLevel"}) do player:GetAttributeChangedSignal(attribute):Connect(function() dirty = true end) end
for _, attribute in ipairs({"DungeonObjectiveId", "DungeonObjectiveState", "DungeonObjectiveTitle", "DungeonObjectiveDescription", "DungeonObjectiveProgress", "DungeonObjectiveTarget", "DungeonObjectiveGlobalIslandIndex", "DungeonCurrentObjectiveIsland"}) do workspace:GetAttributeChangedSignal(attribute):Connect(syncObjective) end

RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if dirty or elapsed >= 0.25 then
		elapsed = 0
		dirty = false
		resolve()
		if hud then hud.Enabled = true end
		if refs.PlayerStatus then refs.PlayerStatus.Visible = true end
		if refs.MiniMap then refs.MiniMap.Visible = true end
		syncStatus()
		syncObjective()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	mapElapsed += dt
	if mapElapsed >= 0.1 then mapElapsed = 0; syncMinimap() end
end)

player:SetAttribute("DungeonArtHUDMode", "SafeAuthoredHUDWithStatusObjectiveMinimap")
player:SetAttribute("DungeonArtHUDCreatesVisuals", false)
resolve()
syncStatus()
syncObjective()
print("[DungeonArtHUDController] HUD autoral integrado sem alterar o movimento do personagem")