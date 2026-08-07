-- Mobile Dungeon Mode — Task 11: Portrait Objective + Reward Flow.
--
-- Camada local de apresentacao.
-- Adapta o RewardIslandPanel existente para portrait e torna o fluxo:
--
--   OBJETIVO -> CORE + BONUS -> ROUND GARANTIDO -> AVANCAR
--
-- O servidor continua sendo a unica autoridade sobre:
-- - claim dos baus;
-- - auto-resolve;
-- - commit das moedas;
-- - commit do round;
-- - liberacao real da progressao.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "DungeonPortraitRewardFlowV1"
local ACTION_ATTACK = "SkyDungeonAttack"
local RENDER_STEP = "InfinityIslandsPortraitRewardFlow"

local COLORS = {
	Glass = Color3.fromRGB(13, 27, 42),
	GlassRaised = Color3.fromRGB(24, 49, 65),
	Text = Color3.fromRGB(239, 247, 252),
	Muted = Color3.fromRGB(147, 176, 199),
	Cyan = Color3.fromRGB(107, 225, 255),
	CyanSoft = Color3.fromRGB(181, 241, 255),
	Gold = Color3.fromRGB(232, 195, 104),
	GoldSoft = Color3.fromRGB(255, 225, 143),
	Green = Color3.fromRGB(100, 236, 162),
	Purple = Color3.fromRGB(198, 142, 255),
}

local active = false
local unifiedGui
local unifiedRoot
local rewardPanel
local flowStrip
local flowSteps = {}
local advanceToast

local lastRewardActive = false
local lastRewardRound = 1
local toastSerial = 0

local originals = setmetatable({}, { __mode = "k" })

local function saveProperty(object, property)
	if not object then
		return
	end
	originals[object] = originals[object] or {}
	if originals[object][property] == nil then
		originals[object][property] = object[property]
	end
end

local function setProperty(object, property, value)
	if not object then
		return
	end
	saveProperty(object, property)
	object[property] = value
end

local function restoreAll()
	for object, properties in pairs(originals) do
		if object and object.Parent then
			for property, value in pairs(properties) do
				pcall(function()
					object[property] = value
				end)
			end
		end
	end
	table.clear(originals)
end

local function viewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(390, 844)
end

local function textScale()
	return math.clamp(
		tonumber(player:GetAttribute("DungeonMobileTextUserScale")) or 1,
		0.90,
		1.25
	)
end

local function scaledText(base)
	return math.max(7, math.floor(base * textScale() + 0.5))
end

local function rewardIsActive()
	return workspace:GetAttribute("DungeonRewardIslandActive") == true
end

local function currentRewardRound()
	local round = tonumber(workspace:GetAttribute("DungeonRewardIslandRound"))
	if round then
		lastRewardRound = math.clamp(math.floor(round), 1, 3)
	end
	return lastRewardRound
end

local function getText(parent, name)
	local object = parent and parent:FindFirstChild(name)
	return object and object:IsA("TextLabel") and object or nil
end

local function isClaimed(card)
	local state = getText(card, "State")
	if not state then
		return false
	end
	local value = string.upper(state.Text)
	return value == "COLETADO"
		or value == "RECEBIDO"
		or string.find(value, "CLAIMED", 1, true) ~= nil
end

local function makeStep(parent, index, text)
	local frame = Instance.new("Frame")
	frame.Name = "Step" .. index
	frame.Size = UDim2.new(0.25, -4, 1, 0)
	frame.BackgroundColor3 = COLORS.GlassRaised
	frame.BackgroundTransparency = 0.10
	frame.BorderSizePixel = 0
	frame.ZIndex = parent.ZIndex + 1
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Cyan
	stroke.Transparency = 0.62
	stroke.Thickness = 1
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.Muted
	label.Font = Enum.Font.GothamBold
	label.TextSize = scaledText(8)
	label.TextWrapped = true
	label.ZIndex = frame.ZIndex + 1
	label.Parent = frame

	flowSteps[index] = {
		Frame = frame,
		Stroke = stroke,
		Label = label,
		BaseText = text,
	}
end

local function ensureFlowStrip(panel)
	if flowStrip and flowStrip.Parent == panel then
		return
	end

	flowStrip = panel:FindFirstChild("PortraitRewardFlow")
	if flowStrip and not flowStrip:IsA("Frame") then
		flowStrip:Destroy()
		flowStrip = nil
	end

	if not flowStrip then
		flowStrip = Instance.new("Frame")
		flowStrip.Name = "PortraitRewardFlow"
		flowStrip.Position = UDim2.fromOffset(14, 69)
		flowStrip.Size = UDim2.new(1, -28, 0, 34)
		flowStrip.BackgroundTransparency = 1
		flowStrip.ZIndex = 76
		flowStrip.Parent = panel

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 5)
		layout.Parent = flowStrip

		makeStep(flowStrip, 1, "✓ OBJETIVO")
		makeStep(flowStrip, 2, "CORE")
		makeStep(flowStrip, 3, "BONUS")
		makeStep(flowStrip, 4, "AVANÇAR")
	else
		table.clear(flowSteps)
		for index = 1, 4 do
			local frame = flowStrip:FindFirstChild("Step" .. index)
			local label = frame and frame:FindFirstChild("Label")
			local stroke = frame and frame:FindFirstChildOfClass("UIStroke")
			if frame and label and stroke then
				flowSteps[index] = {
					Frame = frame,
					Stroke = stroke,
					Label = label,
					BaseText = label.Text,
				}
			end
		end
	end
end

local function styleStep(index, state, text)
	local step = flowSteps[index]
	if not step then
		return
	end
	step.Label.TextSize = scaledText(8)

	if state == "Done" then
		step.Frame.BackgroundColor3 = Color3.fromRGB(29, 73, 63)
		step.Stroke.Color = COLORS.Green
		step.Stroke.Transparency = 0.10
		step.Stroke.Thickness = 1.4
		step.Label.TextColor3 = COLORS.Green
		step.Label.Text = "✓ " .. text
	elseif state == "Current" then
		step.Frame.BackgroundColor3 = Color3.fromRGB(72, 58, 27)
		step.Stroke.Color = COLORS.Gold
		step.Stroke.Transparency = 0.06
		step.Stroke.Thickness = 1.6
		step.Label.TextColor3 = COLORS.GoldSoft
		step.Label.Text = text
	else
		step.Frame.BackgroundColor3 = COLORS.GlassRaised
		step.Stroke.Color = COLORS.Cyan
		step.Stroke.Transparency = 0.70
		step.Stroke.Thickness = 1
		step.Label.TextColor3 = COLORS.Muted
		step.Label.Text = text
	end
end

local function ensureToast()
	if advanceToast and advanceToast.Parent then
		return
	end

	local parent = unifiedRoot
	if not parent then
		return
	end

	advanceToast = parent:FindFirstChild("PortraitRoundAdvanceToast")
	if advanceToast and not advanceToast:IsA("Frame") then
		advanceToast:Destroy()
		advanceToast = nil
	end

	if advanceToast then
		return
	end

	advanceToast = Instance.new("Frame")
	advanceToast.Name = "PortraitRoundAdvanceToast"
	advanceToast.AnchorPoint = Vector2.new(0.5, 0.5)
	advanceToast.Position = UDim2.fromScale(0.5, 0.48)
	advanceToast.Size = UDim2.new(1, -34, 0, 92)
	advanceToast.BackgroundColor3 = Color3.fromRGB(20, 54, 51)
	advanceToast.BackgroundTransparency = 0.04
	advanceToast.BorderSizePixel = 0
	advanceToast.Visible = false
	advanceToast.ZIndex = 104
	advanceToast.Parent = parent

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(270, 86)
	sizeConstraint.MaxSize = Vector2.new(430, 96)
	sizeConstraint.Parent = advanceToast

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = advanceToast

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Green
	stroke.Transparency = 0.10
	stroke.Thickness = 1.6
	stroke.Parent = advanceToast

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(10, 10)
	title.Size = UDim2.new(1, -20, 0, 31)
	title.BackgroundTransparency = 1
	title.Text = "✓ ROUND GARANTIDO"
	title.TextColor3 = COLORS.Green
	title.Font = Enum.Font.GothamBlack
	title.TextSize = scaledText(16)
	title.ZIndex = 105
	title.Parent = advanceToast

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(10, 44)
	detail.Size = UDim2.new(1, -20, 0, 29)
	detail.BackgroundTransparency = 1
	detail.Text = "Recompensas recebidas • siga para a saída."
	detail.TextColor3 = COLORS.Text
	detail.Font = Enum.Font.GothamBold
	detail.TextSize = scaledText(10)
	detail.TextWrapped = true
	detail.ZIndex = 105
	detail.Parent = advanceToast
end

local function showAdvanceToast(round)
	ensureToast()
	if not advanceToast then
		return
	end

	toastSerial += 1
	local serial = toastSerial

	local title = advanceToast:FindFirstChild("Title")
	local detail = advanceToast:FindFirstChild("Detail")
	if title then
		title.Text = string.format("✓ ROUND %d GARANTIDO", round)
		title.TextSize = scaledText(16)
	end
	if detail then
		detail.Text = round >= 3
			and "Recompensas recebidas • o Boss é o próximo destino."
			or "Recompensas recebidas • siga para a saída do round."
		detail.TextSize = scaledText(10)
	end

	advanceToast.Visible = true
	advanceToast.BackgroundTransparency = 0.04
	advanceToast.Position = UDim2.fromScale(0.5, 0.48)

	TweenService:Create(
		advanceToast,
		TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.44) }
	):Play()

	task.delay(2.7, function()
		if serial ~= toastSerial or not advanceToast or not advanceToast.Parent then
			return
		end

		local tween = TweenService:Create(
			advanceToast,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Once(function()
			if serial == toastSerial and advanceToast then
				advanceToast.Visible = false
			end
		end)
	end)
end

local function resolveHud()
	if unifiedGui and unifiedGui.Parent and unifiedRoot and unifiedRoot.Parent then
		return true
	end

	unifiedGui = playerGui:FindFirstChild("DungeonUnifiedHUD")
	if not unifiedGui or not unifiedGui:IsA("ScreenGui") then
		return false
	end

	unifiedRoot = unifiedGui:FindFirstChild("Root")
	return unifiedRoot ~= nil
end

local function resolveRewardPanel()
	if not resolveHud() then
		return nil
	end

	local current = unifiedRoot:FindFirstChild("RewardIslandPanel")
	if current and current:IsA("Frame") then
		if rewardPanel ~= current then
			rewardPanel = current
			flowStrip = nil
			table.clear(flowSteps)
			ensureFlowStrip(rewardPanel)
		end
		return rewardPanel
	end

	rewardPanel = nil
	flowStrip = nil
	table.clear(flowSteps)
	return nil
end

local function adaptChest(card, y, width)
	if not card or not card:IsA("Frame") then
		return
	end

	setProperty(card, "Position", UDim2.fromOffset(14, y))
	setProperty(card, "Size", UDim2.fromOffset(width, 96))

	local icon = card:FindFirstChildWhichIsA("TextLabel")
	local state = getText(card, "State")
	local detail = getText(card, "Detail")

	if icon then
		setProperty(icon, "Position", UDim2.fromOffset(8, 8))
		setProperty(icon, "Size", UDim2.fromOffset(48, 48))
	end

	if state then
		setProperty(state, "Position", UDim2.fromOffset(58, 32))
		setProperty(state, "TextSize", scaledText(10))
	end

	if detail then
		setProperty(detail, "Position", UDim2.fromOffset(12, 63))
		setProperty(detail, "Size", UDim2.new(1, -24, 0, 24))
		setProperty(detail, "TextSize", scaledText(8))
	end
end

local function adaptRewardPanel(panel)
	local view = viewport()
	local width = math.clamp(view.X - 24, 292, 420)
	local height = math.clamp(view.Y * 0.49, 398, 430)

	setProperty(panel, "AnchorPoint", Vector2.new(0.5, 0.5))
	setProperty(panel, "Position", UDim2.fromScale(0.5, 0.50))
	setProperty(panel, "Size", UDim2.fromOffset(width, height))

	local rewardTitle = panel:FindFirstChildWhichIsA("TextLabel")
	local rewardTimer
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("TextLabel") and child ~= rewardTitle then
			rewardTimer = child
			break
		end
	end

	if rewardTitle then
		setProperty(rewardTitle, "Position", UDim2.fromOffset(14, 9))
		setProperty(rewardTitle, "Size", UDim2.new(1, -28, 0, 28))
		setProperty(rewardTitle, "TextSize", scaledText(15))

		local round = currentRewardRound()
		rewardTitle.Text = string.format("RECOMPENSAS DO ROUND %d", round)
	end

	if rewardTimer then
		setProperty(rewardTimer, "Position", UDim2.fromOffset(14, 38))
		setProperty(rewardTimer, "Size", UDim2.new(1, -28, 0, 22))
		setProperty(rewardTimer, "TextSize", scaledText(9))

		-- O HUD original continua atualizando a contagem; apenas simplificamos
		-- a frase quando a string conhecida estiver presente.
		local seconds = string.match(rewardTimer.Text, "(%d+)s")
		if seconds then
			rewardTimer.Text = string.format(
				"Pegue os 2 baús • automático em %ss",
				seconds
			)
		elseif rewardTimer.Text ~= "" then
			rewardTimer.Text = "Finalizando recompensas..."
		end
	end

	ensureFlowStrip(panel)
	if flowStrip then
		flowStrip.Position = UDim2.fromOffset(14, 65)
		flowStrip.Size = UDim2.new(1, -28, 0, 34)
	end

	local innerWidth = width - 28
	local core = panel:FindFirstChild("CoreChest")
	local bonus = panel:FindFirstChild("BonusChest")
	adaptChest(core, 107, innerWidth)
	adaptChest(bonus, 209, innerWidth)

	local coins = panel:FindFirstChild("CoinsCommit")
	if coins and coins:IsA("Frame") then
		setProperty(coins, "Position", UDim2.fromOffset(14, 313))
		setProperty(coins, "Size", UDim2.fromOffset(innerWidth, math.max(58, height - 327)))

		local labels = {}
		for _, descendant in ipairs(coins:GetChildren()) do
			if descendant:IsA("TextLabel") then
				table.insert(labels, descendant)
			end
		end

		for _, label in ipairs(labels) do
			if label.Text == "MOEDAS DO ROUND"
				or label.Text == "RECOMPENSA DO ROUND"
				or label.Text == "GANHOS DESTA RUN"
			then
				label.Text = "GANHOS DESTA RUN"
				setProperty(label, "TextSize", scaledText(9))
			elseif string.find(label.Text, "Abra os dois", 1, true)
				or string.find(label.Text, "Pegue suas recompensas", 1, true)
				or label.Text == "Recebidos após os 2 baús."
			then
				label.Text = "Recebidos após os 2 baús."
				setProperty(label, "TextSize", scaledText(8))
			end
		end
	end

	local coreClaimed = isClaimed(core)
	local bonusClaimed = isClaimed(bonus)

	styleStep(1, "Done", "OBJETIVO")
	styleStep(2, coreClaimed and "Done" or "Current", "CORE")
	styleStep(3, bonusClaimed and "Done" or "Current", "BONUS")
	styleStep(
		4,
		(coreClaimed and bonusClaimed) and "Current" or "Future",
		"AVANÇAR"
	)

	player:SetAttribute("DungeonPortraitRewardCoreClaimed", coreClaimed)
	player:SetAttribute("DungeonPortraitRewardBonusClaimed", bonusClaimed)
	player:SetAttribute(
		"DungeonPortraitRewardReadyToAdvance",
		coreClaimed and bonusClaimed
	)
end

local function updateAttackButton(rewardActive)
	local button = ContextActionService:GetButton(ACTION_ATTACK)
	if not button then
		return
	end

	if rewardActive then
		-- Movimento permanece livre para chegar aos baús. Apenas o ataque
		-- desnecessario sai da tela durante esta janela sem combate.
		button.Visible = false
	end
end

local function update()
	if not active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	local panel = resolveRewardPanel()
	local rewardActive = rewardIsActive()

	if rewardActive then
		currentRewardRound()
		if panel then
			panel.Visible = true
			adaptRewardPanel(panel)
		end
		updateAttackButton(true)
	end

	if lastRewardActive and not rewardActive then
		showAdvanceToast(lastRewardRound)
	end

	lastRewardActive = rewardActive
	player:SetAttribute("DungeonPortraitRewardFlowActive", rewardActive)
	player:SetAttribute("DungeonPortraitRewardFlowRound", lastRewardRound)
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	active = true
	resolveHud()
	resolveRewardPanel()
	lastRewardActive = rewardIsActive()
	currentRewardRound()

	player:SetAttribute("DungeonPortraitRewardFlowReady", true)
	player:SetAttribute("DungeonPortraitRewardFlowActive", lastRewardActive)
	player:SetAttribute("DungeonPortraitRewardFlowVersion", VERSION)
	player:SetAttribute(
		"DungeonPortraitRewardFlowPolicy",
		"ObjectiveTwoChestsCommitAdvanceV1"
	)

	update()
end

local function deactivate()
	if not active then
		return
	end

	active = false
	restoreAll()

	if flowStrip and flowStrip.Parent then
		flowStrip:Destroy()
	end
	flowStrip = nil
	table.clear(flowSteps)

	if advanceToast and advanceToast.Parent then
		advanceToast:Destroy()
	end
	advanceToast = nil

	player:SetAttribute("DungeonPortraitRewardFlowActive", false)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

RunService:BindToRenderStep(
	RENDER_STEP,
	Enum.RenderPriority.Last.Value + 3,
	update
)

player:SetAttribute("DungeonPortraitRewardFlowControllerLoaded", true)
player:SetAttribute("DungeonPortraitRewardFlowVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal(
		"DungeonInputProfileReady"
	):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(function()
	deactivate()
	RunService:UnbindFromRenderStep(RENDER_STEP)
end)
