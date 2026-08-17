local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local islandObjectiveEvent = RemoteRegistry.Get("Dungeon", "IslandObjectiveState", "RemoteEvent")
local islandObjectiveRequest = RemoteRegistry.Get("Dungeon", "IslandObjectiveStateRequest", "RemoteFunction")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local VERSION = "AuthoredHUDV21AuthoritativeVariantObjectives"

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
local islandStatus = {panel = nil, title = nil, cachedKey = nil, cachedIsland = nil, serverState = nil, requestInFlight = false}

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

-- Objetivo permanente da arena atual. Nao usa fundo para manter a leitura do
-- combate limpa em PC e celular.
local function ensureIslandStatus()
	if not hud then return nil end
	local panel = islandStatus.panel
	if panel and panel.Parent == hud then return panel end
	panel = hud:FindFirstChild("RuntimeIslandStatus")
	if not panel or not panel:IsA("Frame") then
		panel = Instance.new("Frame")
		panel.Name = "RuntimeIslandStatus"
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.fromScale(0.5, 0.125)
		panel.Size = UDim2.fromScale(0.84, 0)
		panel.AutomaticSize = Enum.AutomaticSize.Y
		panel.BackgroundTransparency = 1
		panel.BorderSizePixel = 0
		panel.ZIndex = 24
		panel.Parent = hud
	end
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.125)
	panel.Size = UDim2.fromScale(0.84, 0)
	panel.BackgroundTransparency = 1
	panel.AutomaticSize = Enum.AutomaticSize.Y
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("UIStroke") then child.Enabled = false end
	end
	local padding = panel:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 2)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = panel
	local layout = panel:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel
	local title = panel:FindFirstChild("Title")
	if not title or not title:IsA("TextLabel") then
		title = Instance.new("TextLabel")
		title.Name = "Title"
	end
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextWrapped = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0.35
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 25
	title.Parent = panel
	local titleConstraint = title:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 14
	titleConstraint.MaxTextSize = 26
	titleConstraint.Parent = title
	local oldDetail = panel:FindFirstChild("Detail")
	if oldDetail and oldDetail:IsA("TextLabel") then oldDetail:Destroy() end
	islandStatus.panel, islandStatus.title = panel, title
	return panel
end

local function currentIslandModel()
	local key = player:GetAttribute("CurrentIslandKey")
	if key == islandStatus.cachedKey and islandStatus.cachedIsland and islandStatus.cachedIsland.Parent then
		return islandStatus.cachedIsland
	end
	islandStatus.cachedKey = key
	islandStatus.cachedIsland = nil
	if typeof(key) == "string" and key ~= "" then
		local named = workspace:FindFirstChild(key, true)
		if named and named:IsA("Model") then
			islandStatus.cachedIsland = named
		else
			local currentIndex = math.max(0, math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0))
			for _, candidate in ipairs(workspace:GetDescendants()) do
				if candidate:IsA("Model") and (
					candidate:GetAttribute("IslandKey") == key
					or (currentIndex > 0 and tonumber(candidate:GetAttribute("GlobalIslandIndex")) == currentIndex)
				) then
					islandStatus.cachedIsland = candidate
					break
				end
			end
		end
	end
	return islandStatus.cachedIsland
end

-- Cores de leitura extraidas da parte interna/principal das variantes em
-- BlockParkour/SlimeVariants. A cor e aplicada apenas ao nome do inimigo.
local variantInfo = {
	Green = {Names = {"slime verde", "slimes verdes"}, Color = "#59AB54"},
	Blue = {Names = {"slime azul", "slimes azuis"}, Color = "#3766FF"},
	Red = {Names = {"slime vermelho", "slimes vermelhos"}, Color = "#AA1D1D"},
	Fire = {Names = {"slime de fogo", "slimes de fogo"}, Color = "#FF701F"},
	Ice = {Names = {"slime de gelo", "slimes de gelo"}, Color = "#64EFFF"},
	Lightning = {Names = {"slime do raio", "slimes do raio"}, Color = "#F8F8FF"},
	Golden = {Names = {"slime dourado", "slimes dourados"}, Color = "#E8B130"},
	White = {Names = {"slime branco", "slimes brancos"}, Color = "#FFFFFF"},
}

local function orderedObjectiveVariants(island)
	local order = {}
	local seen = {}

	local function addVariants(serialized)
		for _, variant in ipairs(string.split(tostring(serialized or ""), ",")) do
			if variant ~= "" and not seen[variant] then
				seen[variant] = true
				table.insert(order, variant)
			end
		end
	end

	-- O atributo e a fonte principal, pois acompanha a contagem restante. O
	-- resumo do roster e uma reserva para o breve instante de replicacao em que
	-- a ilha ja apareceu no cliente, mas seus atributos ainda nao chegaram.
	addVariants(island:GetAttribute("MobObjectiveVariantOrder"))
	if #order == 0 then
		addVariants(island:GetAttribute("MobRosterSummary"))
	end

	return order
end

local function rosterVariantCounts(island)
	local counts = {}
	for _, variant in ipairs(string.split(tostring(island:GetAttribute("MobRosterSummary") or ""), ",")) do
		if variant ~= "" then
			counts[variant] = (counts[variant] or 0) + 1
		end
	end
	return counts
end

local function appendObjectiveLine(lines, variant, initial, remaining)
	if initial <= 0 then return end
	local info = variantInfo[variant] or {Names = {"slime", "slimes"}, Color = "#FFFFFF"}
	-- Enquanto a tarefa esta ativa, a quantidade e a que ainda falta. Quando a
	-- variante termina, mostramos a meta original riscada para confirmar a tarefa.
	local displayCount = remaining > 0 and remaining or initial
	local mobName = displayCount == 1 and info.Names[1] or info.Names[2]
	table.insert(lines, {
		DisplayCount = displayCount,
		MobName = mobName,
		Color = info.Color,
		Completed = remaining <= 0,
	})
end

local function setObjectiveLines(panel, lines)
	local seen = {}
	for index, line in ipairs(lines) do
		local name = "ObjectiveLine_" .. tostring(index)
		seen[name] = true
		local label = panel:FindFirstChild(name)
		if not label or not label:IsA("TextLabel") then
			label = Instance.new("TextLabel")
			label.Name = name
			label.Size = UDim2.new(1, 0, 0, 24)
			label.AutomaticSize = Enum.AutomaticSize.None
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamMedium
			label.TextScaled = true
			label.TextWrapped = true
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			label.TextStrokeTransparency = 0.4
			label.RichText = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.ZIndex = 25
			local constraint = Instance.new("UITextSizeConstraint")
			constraint.MinTextSize = 12
			constraint.MaxTextSize = 22
			constraint.Parent = label
			label.Parent = panel
		end
		label.LayoutOrder = index + 1
		if typeof(line) == "table" then
			label.RichText = true
			label.TextTransparency = line.Completed and 0.35 or 0
			local format = line.Completed
				and "<s>• %d <font color=\"%s\">%s</font></s>"
				or "• %d <font color=\"%s\">%s</font>"
			label.Text = string.format(
				format,
				line.DisplayCount,
				line.Color,
				line.MobName
			)
		else
			label.RichText = false
			label.TextTransparency = 0
			label.Text = tostring(line)
		end
	end
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("TextLabel") and string.sub(child.Name, 1, 14) == "ObjectiveLine_" and not seen[child.Name] then
			child:Destroy()
		end
	end
end

local function syncIslandStatus()
	local panel = ensureIslandStatus()
	if not panel then return end
	local lines = {}
	local currentIndex = math.max(0, math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0))
	local authoritativeState = islandStatus.serverState

	-- Fonte principal: vem do servidor e nao depende de a ilha estar carregada
	-- no Workspace local. E a unica fonte usada quando o estado estiver pronto.
	if authoritativeState and authoritativeState.IslandIndex == currentIndex then
		if authoritativeState.Cleared == true then
			setObjectiveLines(panel, lines)
			panel.Visible = false
			return
		end
		if authoritativeState.Ready == true then
			setText(islandStatus.title, "ELIMINE MAIS:")
			for _, entry in ipairs(authoritativeState.Variants or {}) do
				local variant = tostring(entry.Variant or "Green")
				local initial = math.max(0, math.floor(tonumber(entry.Initial) or 0))
				local remaining = math.max(0, math.floor(tonumber(entry.Remaining) or initial))
				appendObjectiveLine(lines, variant, initial, remaining)
			end
			if #lines > 0 then
				setObjectiveLines(panel, lines)
				panel.Visible = true
				return
			end
		end
	end

	-- Reserva para uma versao antiga do servidor ou durante a primeira resposta
	-- remota. A UI nunca usa uma contagem total generica como objetivo final.
	local island = currentIslandModel()
	-- Entre uma ilha e outra, CurrentIslandKey pode chegar antes do Model ser
	-- replicado no cliente. Nessa pequena janela, nao ha atributos para ler.
	if not island then
		setObjectiveLines(panel, lines)
		panel.Visible = false
		return
	end
	if island:GetAttribute("Cleared") == true then
		setObjectiveLines(panel, lines)
		panel.Visible = false
		return
	end

	setText(islandStatus.title, "ELIMINE MAIS:")
	local rosterCounts = rosterVariantCounts(island)
	for _, variant in ipairs(orderedObjectiveVariants(island)) do
		local initial = math.max(0, math.floor(tonumber(island:GetAttribute("MobObjectiveInitial_" .. variant)) or rosterCounts[variant] or 0))
		local remainingAttribute = island:GetAttribute("MobObjectiveRemaining_" .. variant)
		local remaining = remainingAttribute == nil
			and initial
			or math.max(0, math.floor(tonumber(remainingAttribute) or 0))

		appendObjectiveLine(lines, variant, initial, remaining)
	end
	if #lines == 0 then
		-- Nunca mostramos uma contagem total generica: ela esconderia as variantes
		-- que o jogador realmente precisa derrotar. Esta mensagem dura somente ate
		-- o roster/atributos da ilha chegarem ao cliente.
		table.insert(lines, "• Preparando objetivos...")
	end
	setObjectiveLines(panel, lines)
	panel.Visible = true
end

local function acceptIslandObjectiveState(state)
	if type(state) ~= "table" then return end
	local islandIndex = math.max(0, math.floor(tonumber(state.IslandIndex) or 0))
	if islandIndex <= 0 then return end
	state.IslandIndex = islandIndex
	state.Variants = type(state.Variants) == "table" and state.Variants or {}
	islandStatus.serverState = state
	dirty = true
end

local function requestIslandObjectiveState()
	if islandStatus.requestInFlight then return end
	local islandIndex = math.max(0, math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0))
	if islandIndex <= 0 then
		islandStatus.serverState = nil
		return
	end

	islandStatus.requestInFlight = true
	task.spawn(function()
		local ok, state = pcall(function()
			return islandObjectiveRequest:InvokeServer()
		end)
		islandStatus.requestInFlight = false
		if ok then
			acceptIslandObjectiveState(state)
		else
			warn("[DungeonArtHUDController] Nao foi possivel obter o objetivo da ilha")
		end
	end)
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
	local visibleIslandsByGlobalIndex = {}
	if map.IslandContainer then
		for _, folder in ipairs(CollectionService:GetTagged("DungeonGameplayMarkers")) do
			local position, island = markerPosition(folder)
			local screenPosition = mapPosition(map, position, root)
			if screenPosition and island then
				seen[folder] = true
				local marker = islandMarkers[folder]
				if not marker or not marker.Parent then marker = cloneMarker(map.SmallIslandTemplate or map.MediumIslandTemplate or map.LargeIslandTemplate, "Island_" .. island.Name, map.IslandContainer); islandMarkers[folder] = marker end
				if marker then marker.Position = screenPosition; marker.Visible = true; setText(text(marker, {"LevelText", "Level", "RecommendedLevel"}), island:GetAttribute("RecommendedLevel") or island:GetAttribute("IslandLevel") or "") end
				local globalIslandIndex = tonumber(island:GetAttribute("GlobalIslandIndex") or island:GetAttribute("ProgressionIslandIndex") or folder:GetAttribute("GlobalIslandIndex"))
				if globalIslandIndex then
					visibleIslandsByGlobalIndex[math.floor(globalIslandIndex)] = {Source = folder, Marker = marker, Position = screenPosition}
				end
			end
		end
	end
	for source, marker in pairs(islandMarkers) do if not seen[source] or not source.Parent then if marker.Parent then marker:Destroy() end; islandMarkers[source] = nil end end

	-- O mapa representa uma ilha, nao cada slime. Mesmo que haja dez mobs vivos,
	-- ela recebe somente um HostileMobMarker logo acima do icone da ilha.
	local activeMobIslands = {}
	if map.MarkerContainer and map.HostileMobTemplate then
		for _, target in ipairs(CollectionService:GetTagged("CombatTarget")) do
			if target:IsA("Model") and target.Parent and target:GetAttribute("Peaceful") ~= true then
				local globalIslandIndex = tonumber(target:GetAttribute("GlobalIslandIndex") or target:GetAttribute("RouteIslandIndex"))
				local islandInfo = globalIslandIndex and visibleIslandsByGlobalIndex[math.floor(globalIslandIndex)]
				if islandInfo then
					activeMobIslands[islandInfo.Source] = islandInfo
				end
			end
		end

		for source, islandInfo in pairs(activeMobIslands) do
			local marker = hostileMarkers[source]
			if not marker or not marker.Parent then
				marker = cloneMarker(map.HostileMobTemplate, "HostileMob_" .. source.Name, map.MarkerContainer)
				hostileMarkers[source] = marker
			end
			if marker then
				marker.AnchorPoint = Vector2.new(0.5, 1)
				marker.Position = UDim2.new(islandInfo.Position.X.Scale, islandInfo.Position.X.Offset, islandInfo.Position.Y.Scale, islandInfo.Position.Y.Offset - 10)
				marker.ZIndex = math.max(marker.ZIndex, (islandInfo.Marker and islandInfo.Marker.ZIndex or 1) + 1)
				marker.Visible = true
			end
		end
	end
	for source, marker in pairs(hostileMarkers) do if not activeMobIslands[source] or not source.Parent then if marker.Parent then marker:Destroy() end; hostileMarkers[source] = nil end end
end

local function recover()
	dirty = true
	resolve()
	if hud then hud.Enabled = true end
	if refs.PlayerStatus then refs.PlayerStatus.Visible = true end
	if refs.MiniMap then refs.MiniMap.Visible = true end
	syncStatus()
	syncObjective()
	syncIslandStatus()
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
for _, attribute in ipairs({"PlayerLevel", "PlayerXP", "PlayerXPToNextLevel", "CurrentIslandKey", "CurrentIslandDisplayLabel", "CurrentCycleIndex"}) do player:GetAttributeChangedSignal(attribute):Connect(function() dirty = true end) end
player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
	islandStatus.serverState = nil
	dirty = true
	requestIslandObjectiveState()
end)
islandObjectiveEvent.OnClientEvent:Connect(acceptIslandObjectiveState)
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
		syncIslandStatus()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	mapElapsed += dt
	if mapElapsed >= 0.1 then mapElapsed = 0; syncMinimap() end
end)

player:SetAttribute("DungeonArtHUDMode", "SafeAuthoredHUDWithTransparentIslandObjectiveList")
player:SetAttribute("DungeonArtHUDCreatesVisuals", false)
resolve()
syncStatus()
syncObjective()
syncIslandStatus()
task.defer(requestIslandObjectiveState)
print("[DungeonArtHUDController] HUD autoral integrado sem alterar o movimento do personagem")
