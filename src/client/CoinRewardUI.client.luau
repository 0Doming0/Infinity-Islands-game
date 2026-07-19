-- Aviso discreto e acumulavel para cada recompensa de moeda recebida.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local coinRewardRemote = ReplicatedStorage:WaitForChild("CoinReward")

local gui = Instance.new("ScreenGui")
gui.Name = "CoinRewardUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 24
gui.Parent = playerGui

local VISIBLE_POSITION = UDim2.new(1, -16, 0, 96)
local HIDDEN_POSITION = UDim2.new(1, 24, 0, 96)
local STACK_WINDOW_SECONDS = 0.8
local VISIBLE_SECONDS = 1.15

local card = Instance.new("CanvasGroup")
card.Name = "RewardCard"
card.AnchorPoint = Vector2.new(1, 0)
card.Position = HIDDEN_POSITION
card.Size = UDim2.fromOffset(150, 42)
card.BackgroundColor3 = Color3.fromRGB(31, 27, 18)
card.BackgroundTransparency = 0.18
card.BorderSizePixel = 0
card.GroupTransparency = 1
card.Visible = false
card.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = card

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 205, 72)
stroke.Thickness = 1
stroke.Transparency = 0.45
stroke.Parent = card

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = "+0 🪙"
label.TextColor3 = Color3.fromRGB(255, 224, 112)
label.Font = Enum.Font.GothamBold
label.TextSize = 19
label.Parent = card

local accumulated = 0
local lastAwardAt = -math.huge
local animationToken = 0
local moveTween
local fadeTween

local function cancelTweens()
	if moveTween then
		moveTween:Cancel()
	end
	if fadeTween then
		fadeTween:Cancel()
	end
end

local function showAward(amount)
	if amount <= 0 then
		return
	end
	local now = os.clock()
	if card.Visible and now - lastAwardAt <= STACK_WINDOW_SECONDS then
		accumulated += amount
	else
		accumulated = amount
	end
	lastAwardAt = now
	animationToken += 1
	local token = animationToken

	cancelTweens()
	label.Text = string.format("+%d 🪙", accumulated)
	card.Visible = true
	card.Position = card.GroupTransparency < 1 and card.Position or HIDDEN_POSITION

	moveTween = TweenService:Create(
		card,
		TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = VISIBLE_POSITION }
	)
	fadeTween = TweenService:Create(card, TweenInfo.new(0.16), { GroupTransparency = 0 })
	moveTween:Play()
	fadeTween:Play()

	task.delay(VISIBLE_SECONDS, function()
		if token ~= animationToken then
			return
		end
		moveTween = TweenService:Create(
			card,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = HIDDEN_POSITION }
		)
		fadeTween = TweenService:Create(card, TweenInfo.new(0.22), { GroupTransparency = 1 })
		moveTween:Play()
		fadeTween:Play()
		fadeTween.Completed:Once(function()
			if token == animationToken then
				card.Visible = false
				accumulated = 0
			end
		end)
	end)
end

coinRewardRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	showAward(math.max(0, math.floor(tonumber(data.Amount) or 0)))
end)
