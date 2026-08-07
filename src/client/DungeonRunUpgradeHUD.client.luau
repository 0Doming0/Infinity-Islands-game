local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local unified = playerGui:WaitForChild("DungeonUnifiedHUD", 20)
if not unified then
	warn("[RunUpgradeHUD] DungeonUnifiedHUD não encontrado.")
	return
end
local root = unified:WaitForChild("Root")

local shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = shared:WaitForChild("Remotes")
local dungeonRemotes = remotes:WaitForChild("Dungeon")
local upgradeEvent = dungeonRemotes:WaitForChild("RunUpgradeState", 20)
if not upgradeEvent or not upgradeEvent:IsA("RemoteEvent") then
	warn("[RunUpgradeHUD] RunUpgradeState não encontrado.")
	return
end

local COLORS = {
	Backdrop = Color3.fromRGB(4, 10, 18),
	Panel = Color3.fromRGB(12, 28, 43),
	Card = Color3.fromRGB(22, 48, 64),
	Text = Color3.fromRGB(241, 248, 252),
	Muted = Color3.fromRGB(159, 188, 207),
	Cyan = Color3.fromRGB(104, 224, 255),
	Gold = Color3.fromRGB(239, 198, 98),
	Green = Color3.fromRGB(105, 237, 164),
}

local overlay = Instance.new("Frame")
overlay.Name = "RunUpgradeChoice"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = COLORS.Backdrop
overlay.BackgroundTransparency = 0.24
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.ZIndex = 110
overlay.Parent = root

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.fromOffset(790, 390)
panel.BackgroundColor3 = COLORS.Panel
panel.BackgroundTransparency = 0.025
panel.BorderSizePixel = 0
panel.ZIndex = 111
panel.Parent = overlay
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 20)
local panelScale = Instance.new("UIScale")
panelScale.Name = "ResponsiveScale"
panelScale.Scale = 1
panelScale.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Gold
panelStroke.Transparency = 0.16
panelStroke.Thickness = 1.6
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(24, 15)
title.Size = UDim2.new(1, -48, 0, 34)
title.BackgroundTransparency = 1
title.Text = "ESCOLHA 1 MELHORIA"
title.TextColor3 = COLORS.Gold
title.Font = Enum.Font.GothamBlack
title.TextSize = 21
title.ZIndex = 112
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(24, 48)
subtitle.Size = UDim2.new(1, -48, 0, 24)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Válida somente nesta expedição • escolha rápida, poder imediato"
subtitle.TextColor3 = COLORS.Muted
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 11
subtitle.ZIndex = 112
subtitle.Parent = panel

local timer = Instance.new("TextLabel")
timer.AnchorPoint = Vector2.new(0.5, 0)
timer.Position = UDim2.new(0.5, 0, 0, 77)
timer.Size = UDim2.fromOffset(320, 24)
timer.BackgroundTransparency = 1
timer.Text = ""
timer.TextColor3 = COLORS.Cyan
timer.Font = Enum.Font.GothamBold
timer.TextSize = 11
timer.ZIndex = 112
timer.Parent = panel

local cards = {}
for index = 1, 3 do
	local card = Instance.new("TextButton")
	card.Name = "Choice" .. index
	card.Position = UDim2.fromOffset(24 + (index - 1) * 250, 112)
	card.Size = UDim2.fromOffset(236, 234)
	card.BackgroundColor3 = COLORS.Card
	card.BackgroundTransparency = 0.03
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.ZIndex = 112
	card.Parent = panel
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	local stroke = Instance.new("UIStroke")
	stroke.Color = index == 2 and COLORS.Gold or COLORS.Cyan
	stroke.Transparency = 0.34
	stroke.Thickness = 1.2
	stroke.Parent = card

	local key = Instance.new("TextLabel")
	key.Position = UDim2.fromOffset(10, 8)
	key.Size = UDim2.fromOffset(31, 31)
	key.BackgroundColor3 = COLORS.Panel
	key.BackgroundTransparency = 0.05
	key.BorderSizePixel = 0
	key.Text = tostring(index)
	key.TextColor3 = COLORS.Gold
	key.Font = Enum.Font.GothamBlack
	key.TextSize = 13
	key.ZIndex = 113
	key.Parent = card
	Instance.new("UICorner", key).CornerRadius = UDim.new(0, 8)

	local glyph = Instance.new("TextLabel")
	glyph.AnchorPoint = Vector2.new(0.5, 0)
	glyph.Position = UDim2.new(0.5, 0, 0, 31)
	glyph.Size = UDim2.fromOffset(90, 68)
	glyph.BackgroundTransparency = 1
	glyph.Text = "✦"
	glyph.TextColor3 = COLORS.Cyan
	glyph.Font = Enum.Font.GothamBlack
	glyph.TextSize = 40
	glyph.ZIndex = 113
	glyph.Parent = card

	local cardTitle = Instance.new("TextLabel")
	cardTitle.Position = UDim2.fromOffset(12, 100)
	cardTitle.Size = UDim2.new(1, -24, 0, 34)
	cardTitle.BackgroundTransparency = 1
	cardTitle.Text = ""
	cardTitle.TextColor3 = COLORS.Text
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.TextSize = 15
	cardTitle.TextWrapped = true
	cardTitle.ZIndex = 113
	cardTitle.Parent = card

	local description = Instance.new("TextLabel")
	description.Position = UDim2.fromOffset(14, 138)
	description.Size = UDim2.new(1, -28, 0, 52)
	description.BackgroundTransparency = 1
	description.Text = ""
	description.TextColor3 = COLORS.Muted
	description.Font = Enum.Font.GothamMedium
	description.TextSize = 11
	description.TextWrapped = true
	description.ZIndex = 113
	description.Parent = card

	local stack = Instance.new("TextLabel")
	stack.AnchorPoint = Vector2.new(0.5, 1)
	stack.Position = UDim2.new(0.5, 0, 1, -12)
	stack.Size = UDim2.new(1, -24, 0, 25)
	stack.BackgroundTransparency = 1
	stack.Text = ""
	stack.TextColor3 = COLORS.Gold
	stack.Font = Enum.Font.GothamBold
	stack.TextSize = 10
	stack.ZIndex = 113
	stack.Parent = card

	cards[index] = {
		Button = card,
		Stroke = stroke,
		Glyph = glyph,
		Title = cardTitle,
		Description = description,
		Stack = stack,
		UpgradeId = nil,
	}
end

local toast = Instance.new("TextLabel")
toast.Name = "RunUpgradeToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 150)
toast.Size = UDim2.fromOffset(460, 52)
toast.BackgroundColor3 = COLORS.Panel
toast.BackgroundTransparency = 0.04
toast.BorderSizePixel = 0
toast.Text = ""
toast.TextColor3 = COLORS.Green
toast.Font = Enum.Font.GothamBlack
toast.TextSize = 13
toast.Visible = false
toast.ZIndex = 125
toast.Parent = root
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 13)
local toastScale = Instance.new("UIScale")
toastScale.Name = "ResponsiveScale"
toastScale.Scale = 1
toastScale.Parent = toast
local toastStroke = Instance.new("UIStroke")
toastStroke.Color = COLORS.Gold
toastStroke.Transparency = 0.2
toastStroke.Parent = toast

local currentRound
local autoPickAt = 0
local selecting = false
local toastSerial = 0
local lastTimerUpdate = 0

local viewportConnection
local function updateResponsive()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.clamp(
		math.min(
			1,
			(viewport.X - 18) / 790,
			(viewport.Y - 18) / 390
		),
		0.44,
		1
	)
	toastScale.Scale = math.clamp(
		math.min(1, (viewport.X - 18) / 460),
		0.62,
		1
	)
end

local function bindViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsive)
	end
	updateResponsive()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)
bindViewport()

local function choose(index)
	if not selecting or not currentRound then
		return
	end
	local card = cards[index]
	if not card or not card.UpgradeId then
		return
	end
	selecting = false
	upgradeEvent:FireServer({
		Action = "ChooseRunUpgrade",
		RoundIndex = currentRound,
		UpgradeId = card.UpgradeId,
	})
end

for index, card in ipairs(cards) do
	card.Button.Activated:Connect(function()
		choose(index)
	end)
end

local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not overlay.Visible then return end
	if input.KeyCode == Enum.KeyCode.One then
		choose(1)
	elseif input.KeyCode == Enum.KeyCode.Two then
		choose(2)
	elseif input.KeyCode == Enum.KeyCode.Three then
		choose(3)
	end
end)

local function showResolved(payload)
	overlay.Visible = false
	selecting = false
	local selectedId = tostring(payload.SelectedUpgradeId or "Melhoria")
	local selectedTitle = selectedId
	for _, card in ipairs(cards) do
		if card.UpgradeId == selectedId then
			selectedTitle = card.Title.Text
			break
		end
	end
	toastSerial += 1
	local serial = toastSerial
	toast.Text = payload.Automatic == true
		and ("AUTOESCOLHIDO • " .. string.upper(selectedTitle))
		or ("MELHORIA ATIVA • " .. string.upper(selectedTitle))
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.04
	toast.Visible = true
	task.delay(2.2, function()
		if serial ~= toastSerial then return end
		local tween = TweenService:Create(toast, TweenInfo.new(0.25), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Wait()
		if serial == toastSerial then
			toast.Visible = false
		end
	end)
end

local function showOffer(payload)
	currentRound = math.clamp(math.floor(tonumber(payload.RoundIndex) or 1), 1, 3)
	autoPickAt = tonumber(payload.AutoPickAt) or 0
	selecting = true
	title.Text = string.format("ESCOLHA 1 MELHORIA • ROUND %d", currentRound)
	for index, card in ipairs(cards) do
		local choice = payload.Choices and payload.Choices[index]
		card.Button.Visible = choice ~= nil
		card.UpgradeId = choice and choice.Id or nil
		if choice then
			card.Glyph.Text = tostring(choice.Glyph or "✦")
			card.Title.Text = string.upper(tostring(choice.Title or choice.Id))
			card.Description.Text = tostring(choice.Description or "")
			card.Stack.Text = string.format(
				"NÍVEL %d → %d",
				math.max(0, math.floor(tonumber(choice.CurrentStack) or 0)),
				math.max(1, math.floor(tonumber(choice.NextStack) or 1))
			)
		end
	end
	overlay.Visible = true
end

upgradeEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.Action == "RunUpgradeChoiceOffered" and payload.Resolved ~= true then
		showOffer(payload)
	elseif payload.Action == "RunUpgradeChoiceResolved" then
		showResolved(payload)
	end
end)

RunService.RenderStepped:Connect(function()
	if not overlay.Visible then return end
	local clock = os.clock()
	if clock - lastTimerUpdate < 0.10 then return end
	lastTimerUpdate = clock
	local remaining = math.max(0, math.ceil(autoPickAt - workspace:GetServerTimeNow()))
	timer.Text = remaining > 0
		and string.format("ESCOLHA AGORA • autoescolha em %ds", remaining)
		or "AUTOESCOLHA EM ANDAMENTO..."
end)

player:SetAttribute("DungeonRunUpgradeHUDReady", true)
player:SetAttribute("DungeonRunUpgradeHUDVersion", "RunUpgradeChoiceResponsiveV2")
workspace:SetAttribute("DungeonRunUpgradeHUDPerformancePolicy", "Visible10HzResponsiveV2")

