-- Task 20 — GuidedIntro presentation.
--
-- This UI is presentation-only. It never grants completion.
-- The server persists GuidedIntroCompleted only after the first Reward Island
-- has actually been committed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "GuidedIntroPresentationV1"
local MOVEMENT_GOAL = 8
local UPDATE_INTERVAL = 0.12

local gui
local instruction
local detail
local progress
local startPosition
local baselineAccepted = 0
local baselineHitSerial = 0
local elapsed = 0
local stage = "Move"

local function active()
	return player:GetAttribute("GuidedIntroActive") == true
end

local function root()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function counter(name)
	return math.max(0, tonumber(player:GetAttribute(name)) or 0)
end

local function mobile()
	return player:GetAttribute("DungeonMobileMode") == true
end

local function createGui()
	if gui and gui.Parent then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "DungeonGuidedIntroUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 92
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -118)
	card.Size = UDim2.new(1, -28, 0, 118)
	card.BackgroundColor3 = Color3.fromRGB(10, 27, 42)
	card.BackgroundTransparency = 0.04
	card.BorderSizePixel = 0
	card.ZIndex = 93
	card.Parent = gui

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(285, 108)
	constraint.MaxSize = Vector2.new(470, 124)
	constraint.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 15)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(104, 224, 255)
	stroke.Transparency = 0.22
	stroke.Thickness = 1.3
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 20)
	title.BackgroundTransparency = 1
	title.Text = "PRIMEIRO VOO"
	title.TextColor3 = Color3.fromRGB(109, 227, 255)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 12
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 94
	title.Parent = card

	instruction = Instance.new("TextLabel")
	instruction.Position = UDim2.fromOffset(14, 34)
	instruction.Size = UDim2.new(1, -28, 0, 37)
	instruction.BackgroundTransparency = 1
	instruction.TextColor3 = Color3.fromRGB(244, 249, 252)
	instruction.Font = Enum.Font.GothamBold
	instruction.TextSize = 12
	instruction.TextWrapped = true
	instruction.TextXAlignment = Enum.TextXAlignment.Left
	instruction.TextYAlignment = Enum.TextYAlignment.Top
	instruction.ZIndex = 94
	instruction.Parent = card

	detail = Instance.new("TextLabel")
	detail.Position = UDim2.fromOffset(14, 74)
	detail.Size = UDim2.new(1, -28, 0, 20)
	detail.BackgroundTransparency = 1
	detail.TextColor3 = Color3.fromRGB(159, 187, 208)
	detail.Font = Enum.Font.GothamMedium
	detail.TextSize = 9
	detail.TextWrapped = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.ZIndex = 94
	detail.Parent = card

	progress = Instance.new("TextLabel")
	progress.AnchorPoint = Vector2.new(1, 1)
	progress.Position = UDim2.new(1, -13, 1, -8)
	progress.Size = UDim2.fromOffset(52, 17)
	progress.BackgroundTransparency = 1
	progress.TextColor3 = Color3.fromRGB(105, 231, 164)
	progress.Font = Enum.Font.GothamBlack
	progress.TextSize = 9
	progress.TextXAlignment = Enum.TextXAlignment.Right
	progress.ZIndex = 94
	progress.Parent = card
end

local function setStage(nextStage)
	if stage ~= nextStage then
		stage = nextStage
		player:SetAttribute("GuidedIntroPresentationStage", stage)
	end
end

local function updateCopy()
	if stage == "Move" then
		instruction.Text = mobile()
			and "Use o analogico para se mover pela ilha."
			or "Use WASD para se mover pela ilha."
		detail.Text = "Explore. A rota principal leva voce ao primeiro objetivo."
		progress.Text = "1 / 4"
	elseif stage == "Attack" then
		instruction.Text = mobile()
			and "Aproxime-se de um slime e segure ATACAR."
			or "Aproxime-se de um slime e ataque com sua espada."
		detail.Text = "O auxilio de mira ajuda quando o inimigo esta proximo e a sua frente."
		progress.Text = "2 / 4"
	elseif stage == "Objective" then
		instruction.Text = "Complete o objetivo mostrado no topo."
		detail.Text = "Ao concluir, o caminho para a recompensa sera liberado."
		progress.Text = "3 / 4"
	elseif stage == "Reward" then
		instruction.Text = "Abra os dois baus: CORE e BONUS."
		detail.Text = "A introducao so termina quando as recompensas forem confirmadas."
		progress.Text = "4 / 4"
	else
		instruction.Text = "Introducao concluida!"
		detail.Text = "Agora o Lobby e seu hub. A Phase01 continua sendo a primeira fase real."
		progress.Text = "OK"
	end
end

local function resetForIntro()
	local currentRoot = root()
	startPosition = currentRoot and currentRoot.Position or nil
	baselineAccepted = counter("SwordServerAcceptedRequests")
	baselineHitSerial = counter("SwordHitSerial")
	stage = "Move"
	player:SetAttribute("GuidedIntroPresentationStage", stage)
	updateCopy()
end

local function update()
	if not active() then
		gui.Enabled = false
		return
	end

	gui.Enabled = true

	if player:GetAttribute("GuidedIntroCompletionSaved") == true
		or workspace:GetAttribute("DungeonGuidedIntroCompleting") == true
	then
		setStage("Complete")
		updateCopy()
		return
	end

	if workspace:GetAttribute("DungeonRewardIslandActive") == true
		or workspace:GetAttribute("DungeonRoundRewardPending") == true
	then
		setStage("Reward")
		updateCopy()
		return
	end

	if stage == "Move" then
		local currentRoot = root()
		if currentRoot and not startPosition then
			startPosition = currentRoot.Position
		elseif currentRoot and startPosition then
			local difference = currentRoot.Position - startPosition
			local flat = Vector3.new(difference.X, 0, difference.Z)
			if flat.Magnitude >= MOVEMENT_GOAL then
				setStage("Attack")
			end
		end
	end

	if stage == "Attack"
		and (
			counter("SwordServerAcceptedRequests") > baselineAccepted
			or counter("SwordHitSerial") > baselineHitSerial
		)
	then
		setStage("Objective")
	end

	updateCopy()
end

createGui()
player:SetAttribute("GuidedIntroPresentationReady", true)
player:SetAttribute("GuidedIntroPresentationVersion", VERSION)

player:GetAttributeChangedSignal("GuidedIntroActive"):Connect(function()
	if active() then
		resetForIntro()
	end
	update()
end)

player.CharacterAdded:Connect(function()
	if active() then
		task.defer(resetForIntro)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed >= UPDATE_INTERVAL then
		elapsed = 0
		update()
	end
end)

if active() then
	resetForIntro()
end
update()
