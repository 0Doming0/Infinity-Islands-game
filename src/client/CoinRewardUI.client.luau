-- Aviso discreto e acumulavel para cada recompensa de moeda recebida.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local coinRewardRemote = ReplicatedStorage:WaitForChild("CoinReward")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CURRENCY_SYMBOL = MVPConfig.Currency.Symbol

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
local MIN_FLYING_COINS = 4
local MAX_FLYING_COINS = 8
local COIN_FLIGHT_SECONDS = 0.62
local COIN_STAGGER_SECONDS = 0.055
local random = Random.new()

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
label.Text = "+0 " .. CURRENCY_SYMBOL
label.TextColor3 = Color3.fromRGB(255, 224, 112)
label.Font = Enum.Font.GothamBold
label.TextSize = 19
label.Parent = card

local accumulated = 0
local lastAwardAt = -math.huge
local animationToken = 0
local moveTween
local fadeTween
local targetPulseToken = 0
local targetPulseTween

local function cancelTweens()
	if moveTween then
		moveTween:Cancel()
	end
	if fadeTween then
		fadeTween:Cancel()
	end
end

local function findCoinCounter()
	local survivalGui = playerGui:FindFirstChild("SurvivalUI")
	local hud = survivalGui and survivalGui:FindFirstChild("HUD")
	local counter = hud and hud:FindFirstChild("Coins")
	if counter and counter:IsA("GuiObject") then
		return counter
	end
	return nil
end

local function counterCenter(counter)
	return counter.AbsolutePosition + counter.AbsoluteSize * 0.5
end

local function rewardStartPosition(worldPosition)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local fallback = Vector2.new(viewport.X * 0.5, viewport.Y * 0.52)
	if typeof(worldPosition) ~= "Vector3" or not camera then
		return fallback
	end

	-- WorldToScreenPoint includes Roblox's top-bar inset, matching this ScreenGui.
	local projected, onScreen = camera:WorldToScreenPoint(worldPosition)
	if projected.Z <= 0 then
		return fallback
	end
	local margin = 36
	local screenPosition = Vector2.new(projected.X, projected.Y)
	if not onScreen then
		screenPosition = Vector2.new(
			math.clamp(screenPosition.X, margin, viewport.X - margin),
			math.clamp(screenPosition.Y, margin, viewport.Y - margin)
		)
	end
	return screenPosition
end

local function createFlyingCoin(position)
	local coin = Instance.new("Frame")
	coin.Name = "FlyingCoin"
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Position = UDim2.fromOffset(position.X, position.Y)
	coin.Size = UDim2.fromOffset(24, 24)
	coin.BackgroundColor3 = Color3.fromRGB(255, 188, 38)
	coin.BorderSizePixel = 0
	coin.ZIndex = 10
	coin.Parent = gui

	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(1, 0)
	coinCorner.Parent = coin

	local coinStroke = Instance.new("UIStroke")
	coinStroke.Color = Color3.fromRGB(255, 239, 139)
	coinStroke.Thickness = 2
	coinStroke.Parent = coin

	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 246, 156)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 194, 42)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 116, 12)),
	})
	shine.Rotation = 35
	shine.Parent = coin

	local symbol = Instance.new("TextLabel")
	symbol.Size = UDim2.fromScale(1, 1)
	symbol.BackgroundTransparency = 1
	symbol.Text = CURRENCY_SYMBOL
	symbol.TextColor3 = Color3.fromRGB(112, 61, 8)
	symbol.Font = Enum.Font.GothamBold
	symbol.TextSize = 14
	symbol.ZIndex = 11
	symbol.Parent = coin

	return coin
end

local function pulseCounter(counter)
	targetPulseToken += 1
	local token = targetPulseToken
	local scale = counter:FindFirstChild("CoinArrivalScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "CoinArrivalScale"
		scale.Parent = counter
	end
	scale.Scale = 1.16
	if targetPulseTween then
		targetPulseTween:Cancel()
	end
	targetPulseTween = TweenService:Create(
		scale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	targetPulseTween:Play()
	task.delay(0.2, function()
		if token == targetPulseToken then
			scale.Scale = 1
		end
	end)
end

local function flyCoin(startPosition, counter, index, total)
	task.delay((index - 1) * COIN_STAGGER_SECONDS, function()
		if not counter.Parent then
			return
		end
		local coin = createFlyingCoin(startPosition)
		local angle = (index / total) * math.pi * 2 + random:NextNumber(-0.35, 0.35)
		local burstDistance = random:NextNumber(34, 62)
		local burst = Vector2.new(math.cos(angle), math.sin(angle)) * burstDistance
		local control = startPosition + burst + Vector2.new(0, -random:NextNumber(35, 75))
		local startedAt = os.clock()
		local connection

		connection = RunService.RenderStepped:Connect(function()
			if not coin.Parent or not counter.Parent then
				connection:Disconnect()
				coin:Destroy()
				return
			end
			local alpha = math.clamp((os.clock() - startedAt) / COIN_FLIGHT_SECONDS, 0, 1)
			local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local destination = counterCenter(counter)
			local inverse = 1 - eased
			local position = inverse * inverse * startPosition
				+ 2 * inverse * eased * control
				+ eased * eased * destination
			coin.Position = UDim2.fromOffset(position.X, position.Y)
			coin.Rotation = eased * 540 + index * 18
			local size = 24 * (1 - 0.38 * eased)
			coin.Size = UDim2.fromOffset(size, size)

			if alpha >= 1 then
				connection:Disconnect()
				coin:Destroy()
				pulseCounter(counter)
			end
		end)
	end)
end

local function playCoinFlight(amount, worldPosition)
	if amount <= 0 then
		return
	end
	local counter = findCoinCounter()
	if not counter then
		return
	end
	local startPosition = rewardStartPosition(worldPosition)
	local visualCount = math.clamp(math.ceil(math.sqrt(amount)) + 2, MIN_FLYING_COINS, MAX_FLYING_COINS)
	for index = 1, visualCount do
		flyCoin(startPosition, counter, index, visualCount)
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
	label.Text = string.format("+%d %s", accumulated, CURRENCY_SYMBOL)
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
	local amount = math.max(0, math.floor(tonumber(data.Amount) or 0))
	showAward(amount)
	playCoinFlight(amount, data.WorldPosition)
end)
