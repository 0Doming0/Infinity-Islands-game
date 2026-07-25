-- Numeros azuis de estamina que surgem nos pes do personagem e somem subindo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local rewardRemote = ReplicatedStorage:WaitForChild("StaminaReward")
local random = Random.new()

local function formatAmount(amount)
	if amount == math.floor(amount) then
		return string.format("+%d", amount)
	end
	return string.format("+%.1f", amount):gsub("%.", ",")
end

local function showReward(payload)
	if type(payload) ~= "table" then
		return
	end
	local amount = tonumber(payload.Amount)
	if not amount or amount <= 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "StaminaRewardPopup"
	local feetOffsetY = -(humanoid.HipHeight + (root.Size.Y * 0.5)) + 0.45
	attachment.Position = Vector3.new(
		random:NextNumber(-1.25, 1.25),
		feetOffsetY + random:NextNumber(0.1, 0.45),
		random:NextNumber(-0.2, 0.2)
	)
	attachment.Parent = root

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StaminaReward"
	billboard.Adornee = attachment
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Size = UDim2.fromOffset(90, 32)
	billboard.Parent = attachment

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = formatAmount(amount)
	label.TextColor3 = Color3.fromRGB(60, 178, 255)
	label.TextStrokeColor3 = Color3.fromRGB(7, 39, 73)
	label.TextStrokeTransparency = 0.12
	label.Font = Enum.Font.GothamBold
	label.TextScaled = false
	label.TextSize = 17
	label.Parent = billboard

	label.Rotation = random:NextNumber(-7, 7)
	label.Size = UDim2.fromScale(0.72, 0.72)

	TweenService:Create(
		label,
		TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, 1) }
	):Play()

	local riseTween = TweenService:Create(
		attachment,
		TweenInfo.new(1.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = attachment.Position + Vector3.new(0, 3.4, 0) }
	)
	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	riseTween:Play()
	fadeTween:Play()
	riseTween.Completed:Once(function()
		attachment:Destroy()
	end)
end

rewardRemote.OnClientEvent:Connect(showReward)
