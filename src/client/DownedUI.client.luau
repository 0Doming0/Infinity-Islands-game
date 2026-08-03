-- Aviso local de incapacitação e marcadores sociais para aliados caídos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("DownedEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "DownedUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 85
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.new(0.5, 0, 1, -54)
card.Size = UDim2.fromOffset(360, 74)
card.BackgroundColor3 = Color3.fromRGB(36, 17, 20)
card.BackgroundTransparency = 0.08
card.BorderSizePixel = 0
card.Visible = false
card.Parent = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 97, 91)
stroke.Transparency = 0.25
stroke.Thickness = 1.5
stroke.Parent = card

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(14, 8)
title.Size = UDim2.new(1, -28, 0, 27)
title.BackgroundTransparency = 1
title.Text = "VOCÊ ESTÁ CAÍDO"
title.TextColor3 = Color3.fromRGB(255, 119, 111)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = card

local detail = Instance.new("TextLabel")
detail.Position = UDim2.fromOffset(14, 36)
detail.Size = UDim2.new(1, -28, 0, 25)
detail.BackgroundTransparency = 1
detail.Text = "Um jogador pode segurar E para reviver você."
detail.TextColor3 = Color3.fromRGB(239, 225, 226)
detail.Font = Enum.Font.GothamMedium
detail.TextSize = 12
detail.Parent = card

local markers = {}

local function clearRagdollVisual(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	if not character or targetPlayer:GetAttribute("IsDowned") == true then
		return
	end
	local folder = character:FindFirstChild("DownedRagdoll")
	if folder then
		folder:Destroy()
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			descendant.Enabled = true
			descendant.Transform = CFrame.identity
		elseif (descendant:IsA("Constraint") or descendant:IsA("Attachment"))
			and string.sub(descendant.Name, 1, #"DownedRagdoll_") == "DownedRagdoll_"
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
end

local function removeMarker(player)
	local marker = markers[player]
	if marker then
		marker:Destroy()
		markers[player] = nil
	end
end

local function ensureMarker(player)
	if player == localPlayer or player:GetAttribute("IsDowned") ~= true then
		removeMarker(player)
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		removeMarker(player)
		return
	end
	local marker = markers[player]
	if marker and marker.Adornee ~= root then
		removeMarker(player)
		marker = nil
	end
	if not marker then
		marker = Instance.new("BillboardGui")
		marker.Name = "DownedAllyMarker"
		marker.Adornee = root
		marker.Size = UDim2.fromOffset(150, 42)
		marker.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
		marker.AlwaysOnTop = true
		marker.LightInfluence = 0
		marker.Parent = gui
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(54, 20, 24)
		label.BackgroundTransparency = 0.12
		label.TextColor3 = Color3.fromRGB(255, 130, 120)
		label.TextStrokeTransparency = 0.65
		label.Font = Enum.Font.GothamBold
		label.TextSize = 11
		label.TextWrapped = true
		label.Parent = marker
		Instance.new("UICorner", label).CornerRadius = UDim.new(0, 9)
		markers[player] = marker
	end
	local sameParty = localPlayer:GetAttribute("PartyId") ~= nil
		and localPlayer:GetAttribute("PartyId") == player:GetAttribute("PartyId")
	marker.MaxDistance = sameParty and 10000 or 55
	local remaining = math.max(0, math.ceil(
		(tonumber(player:GetAttribute("DownedExpiresAt")) or workspace:GetServerTimeNow())
			- workspace:GetServerTimeNow()
	))
	marker.Label.Text = string.format("ALIADO CAÍDO\n%s · %ds", player.DisplayName, remaining)
end

local function watchPlayer(player)
	player:GetAttributeChangedSignal("IsDowned"):Connect(function()
		ensureMarker(player)
	end)
	player:GetAttributeChangedSignal("PartyId"):Connect(function()
		ensureMarker(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(ensureMarker, player)
	end)
	ensureMarker(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(removeMarker)

RunService.RenderStepped:Connect(function()
	local downed = localPlayer:GetAttribute("IsDowned") == true
	card.Visible = downed
	if downed then
		local remaining = math.max(0, math.ceil(
			(tonumber(localPlayer:GetAttribute("DownedExpiresAt")) or workspace:GetServerTimeNow())
				- workspace:GetServerTimeNow()
		))
		detail.Text = string.format(
			"Aguarde ajuda: outro jogador deve segurar E.  Morte em %ds.",
			remaining
		)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer and player:GetAttribute("IsDowned") == true then
			ensureMarker(player)
		end
	end
end)

event.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.UserId then
		local targetPlayer = Players:GetPlayerByUserId(data.UserId)
		if targetPlayer then
			if data.Action == "Revived" then
				removeMarker(targetPlayer)
				clearRagdollVisual(targetPlayer)
				-- Replicacao de constraints e Motor6D pode chegar em frames diferentes.
				-- Repetir a limpeza visual torna o levantamento consistente inclusive
				-- para observadores com ping alto.
				task.delay(0.12, clearRagdollVisual, targetPlayer)
				task.delay(0.35, clearRagdollVisual, targetPlayer)
			else
				ensureMarker(targetPlayer)
			end
		end
	end
end)
