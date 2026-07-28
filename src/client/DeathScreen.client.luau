-- Tela de morte responsiva. A compra é solicitada ao servidor e validada por
-- ProcessReceipt; o cliente nunca concede moedas.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local deathEvent = ReplicatedStorage:WaitForChild("DeathReviveEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "DeathScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- A transicao fica em uma ScreenGui separada para sobreviver ao CharacterAdded.
-- Ela cobre a tela de morte antes que o personagem antigo seja removido.
local transitionGui = Instance.new("ScreenGui")
transitionGui.Name = "RespawnTransition"
transitionGui.ResetOnSpawn = false
transitionGui.IgnoreGuiInset = true
transitionGui.DisplayOrder = 10000
transitionGui.Enabled = false
transitionGui.Parent = player.PlayerGui

local topCurtain = Instance.new("Frame")
topCurtain.Name = "TopCurtain"
topCurtain.Size = UDim2.fromScale(1, 0.505)
topCurtain.Position = UDim2.fromScale(0, 0)
topCurtain.BackgroundColor3 = Color3.new(0, 0, 0)
topCurtain.BorderSizePixel = 0
topCurtain.ZIndex = 1
topCurtain.Parent = transitionGui

local bottomCurtain = Instance.new("Frame")
bottomCurtain.Name = "BottomCurtain"
bottomCurtain.Size = UDim2.fromScale(1, 0.505)
bottomCurtain.Position = UDim2.fromScale(0, 0.495)
bottomCurtain.BackgroundColor3 = Color3.new(0, 0, 0)
bottomCurtain.BorderSizePixel = 0
bottomCurtain.ZIndex = 1
bottomCurtain.Parent = transitionGui

local loadingGroup = Instance.new("CanvasGroup")
loadingGroup.Name = "Loading"
loadingGroup.AnchorPoint = Vector2.new(0.5, 0.5)
loadingGroup.Position = UDim2.fromScale(0.5, 0.5)
loadingGroup.Size = UDim2.fromOffset(280, 70)
loadingGroup.BackgroundTransparency = 1
loadingGroup.ZIndex = 2
loadingGroup.Parent = transitionGui

local loadingMark = Instance.new("Frame")
loadingMark.AnchorPoint = Vector2.new(0.5, 0.5)
loadingMark.Position = UDim2.fromScale(0.5, 0.23)
loadingMark.Size = UDim2.fromOffset(14, 14)
loadingMark.Rotation = 45
loadingMark.BackgroundColor3 = Color3.fromRGB(232, 185, 72)
loadingMark.BorderSizePixel = 0
loadingMark.ZIndex = 2
loadingMark.Parent = loadingGroup

local loadingText = Instance.new("TextLabel")
loadingText.Position = UDim2.fromScale(0, 0.45)
loadingText.Size = UDim2.fromScale(1, 0.55)
loadingText.BackgroundTransparency = 1
loadingText.Text = "PREPARANDO O MUNDO"
loadingText.TextColor3 = Color3.fromRGB(235, 235, 235)
loadingText.Font = Enum.Font.GothamMedium
loadingText.TextSize = 15
loadingText.ZIndex = 2
loadingText.Parent = loadingGroup

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
shade.BackgroundTransparency = 0.18
shade.BorderSizePixel = 0
shade.Parent = gui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(430, 300)
card.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
card.BorderSizePixel = 0
card.Parent = shade
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)

local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(300, 260)
constraint.MaxSize = Vector2.new(430, 300)
constraint.Parent = card

local cardScale = Instance.new("UIScale")
cardScale.Parent = card
local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	cardScale.Scale = math.clamp(math.min((viewport.X - 24) / 430, (viewport.Y - 24) / 300), 0.68, 1)
end
updateScale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(20, 20)
title.Size = UDim2.new(1, -40, 0, 44)
title.BackgroundTransparency = 1
title.Text = "VOCÊ MORREU"
title.TextColor3 = Color3.fromRGB(255, 104, 104)
title.Font = Enum.Font.GothamBold
title.TextSize = 28
title.Parent = card

local result = Instance.new("TextLabel")
result.Position = UDim2.fromOffset(24, 75)
result.Size = UDim2.new(1, -48, 0, 68)
result.BackgroundTransparency = 1
result.Text = ""
result.TextColor3 = Color3.fromRGB(225, 229, 239)
result.Font = Enum.Font.GothamMedium
result.TextSize = 18
result.TextWrapped = true
result.Parent = card

local robuxButton = Instance.new("TextButton")
robuxButton.Position = UDim2.fromOffset(24, 158)
robuxButton.Size = UDim2.new(1, -48, 0, 55)
robuxButton.BackgroundColor3 = Color3.fromRGB(52, 166, 94)
robuxButton.Text = "RENASCER SEM PERDER MOEDAS"
robuxButton.TextColor3 = Color3.new(1, 1, 1)
robuxButton.Font = Enum.Font.GothamBold
robuxButton.TextSize = 16
robuxButton.Parent = card
Instance.new("UICorner", robuxButton).CornerRadius = UDim.new(0, 12)

local freeButton = Instance.new("TextButton")
freeButton.Position = UDim2.fromOffset(24, 226)
freeButton.Size = UDim2.new(1, -48, 0, 48)
freeButton.BackgroundColor3 = Color3.fromRGB(61, 68, 84)
freeButton.Text = "AGUARDE..."
freeButton.TextColor3 = Color3.fromRGB(225, 229, 239)
freeButton.Font = Enum.Font.GothamBold
freeButton.TextSize = 15
freeButton.Parent = card
Instance.new("UICorner", freeButton).CornerRadius = UDim.new(0, 11)

local current
local transitionSequence
local transitionToken = 0
local openingTransition = false
local TRANSITION_SERVER_TIMEOUT_SECONDS = 30
local STREAMING_TIMEOUT_SECONDS = 20
local showRespawnFailure
local openRespawnTransition

local function showRespawnTransition(sequence)
	-- A primeira entrada pertence exclusivamente a StartScreen. Ausencia de
	-- Character antes de INICIAR nao significa morte.
	if player:GetAttribute("InitialGameStarted") ~= true then
		return
	end
	transitionToken += 1
	local numericSequence = tonumber(sequence)
	if numericSequence then
		transitionSequence = math.max(transitionSequence or 0, numericSequence)
	end
	openingTransition = false
	topCurtain.Position = UDim2.fromScale(0, 0)
	bottomCurtain.Position = UDim2.fromScale(0, 0.495)
	loadingGroup.GroupTransparency = 0
	loadingMark.Rotation = 45
	loadingText.Text = "PREPARANDO O MUNDO"
	transitionGui.Enabled = true
	gui.Enabled = false
	local token = transitionToken
	task.delay(TRANSITION_SERVER_TIMEOUT_SECONDS, function()
		if token ~= transitionToken or not transitionGui.Enabled then
			return
		end
		if player:GetAttribute("RespawnState") == "Ready" then
			openRespawnTransition(tonumber(player:GetAttribute("RespawnSequence")) or 0)
			return
		end
		showRespawnFailure("O renascimento demorou demais. Tente novamente.")
	end)
end

local function cancelRespawnTransition()
	transitionToken += 1
	openingTransition = false
	transitionSequence = nil
	transitionGui.Enabled = false
	if current then
		gui.Enabled = true
	end
end

showRespawnFailure = function(message)
	transitionToken += 1
	openingTransition = false
	transitionGui.Enabled = false
	gui.Enabled = true
	current = current or {
		Serial = tonumber(player:GetAttribute("DeathScreenSerial")) or 0,
		ProductId = 0,
		FreeAt = 0,
	}
	current.Retry = true
	result.Text = tostring(message or "Não foi possível posicionar seu personagem.")
	freeButton.Active = true
	freeButton.AutoButtonColor = true
	freeButton.Text = "TENTAR RENASCER NOVAMENTE"
	robuxButton.Active = false
	robuxButton.AutoButtonColor = false
	robuxButton.Text = "AGUARDE O RENASCIMENTO"
end

local function hasLoadedFloor(character, rootPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local hit = workspace:Raycast(rootPart.Position + Vector3.new(0, 2, 0), Vector3.new(0, -20, 0), params)
	return hit ~= nil and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
end

openRespawnTransition = function(sequence)
	if openingTransition or not transitionGui.Enabled then
		return
	end
	if transitionSequence and sequence and sequence < transitionSequence then
		return
	end
	if sequence and (not transitionSequence or sequence > transitionSequence) then
		transitionSequence = sequence
	end
	openingTransition = true
	local token = transitionToken
	task.spawn(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or not rootPart then
			openingTransition = false
			return
		end

		loadingText.Text = "CARREGANDO A ÁREA"
		pcall(function()
			player:RequestStreamAroundAsync(rootPart.Position, 5)
		end)

		local stableFrames = 0
		local waitingSince = os.clock()
		local streamingDeadline = waitingSince + STREAMING_TIMEOUT_SECONDS
		local nextStreamingRequest = os.clock() + 4
		repeat
			RunService.Heartbeat:Wait()
			if token ~= transitionToken or player.Character ~= character or humanoid.Health <= 0 then
				openingTransition = false
				return
			end
			if hasLoadedFloor(character, rootPart) and not rootPart.Anchored then
				stableFrames += 1
			else
				stableFrames = 0
			end
			if os.clock() >= nextStreamingRequest then
				nextStreamingRequest = os.clock() + 4
				loadingText.Text = os.clock() - waitingSince >= 8 and "FINALIZANDO A ÁREA" or "CARREGANDO A ÁREA"
				task.spawn(function()
					pcall(function()
						player:RequestStreamAroundAsync(rootPart.Position, 4)
					end)
				end)
			end
		until stableFrames >= 2 or os.clock() >= streamingDeadline

		if token ~= transitionToken then
			openingTransition = false
			return
		end
		loadingText.Text = "PRONTO"
		task.wait(0.12)
		TweenService:Create(
			loadingGroup,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 1 }
		):Play()
		local info = TweenInfo.new(0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		local topTween = TweenService:Create(topCurtain, info, { Position = UDim2.fromScale(0, -0.505) })
		local bottomTween = TweenService:Create(bottomCurtain, info, { Position = UDim2.fromScale(0, 1) })
		topTween:Play()
		bottomTween:Play()
		topTween.Completed:Wait()
		if token == transitionToken then
			transitionGui.Enabled = false
			transitionSequence = nil
			openingTransition = false
			current = nil
		end
	end)
end

robuxButton.Activated:Connect(function()
	if not current or current.ProductId <= 0 then
		return
	end
	robuxButton.Active = false
	current.PurchasePending = true
	robuxButton.Text = "ABRINDO COMPRA..."
	deathEvent:FireServer({ Action = "Purchase", Serial = current.Serial })
end)

freeButton.Activated:Connect(function()
	if current and current.Retry then
		current.Retry = false
		freeButton.Active = false
		showRespawnTransition(player:GetAttribute("RespawnSequence"))
		deathEvent:FireServer({ Action = "RetryRespawn", Serial = current.Serial })
	elseif current and os.clock() >= current.FreeAt then
		freeButton.Active = false
		showRespawnTransition(nil)
		deathEvent:FireServer({ Action = "FreeRespawn", Serial = current.Serial })
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	if transitionGui.Enabled then
		loadingMark.Rotation = (loadingMark.Rotation + 135 * deltaTime) % 360
	end
	if not current or not gui.Enabled then
		return
	end
	if current.Retry then
		freeButton.Active = true
		freeButton.AutoButtonColor = true
		freeButton.Text = "TENTAR RENASCER NOVAMENTE"
		return
	end
	local remaining = math.max(0, math.ceil(current.FreeAt - os.clock()))
	freeButton.Active = remaining <= 0
	freeButton.AutoButtonColor = remaining <= 0
	freeButton.Text = remaining <= 0 and "RENASCER" or string.format("RENASCER EM %ds", remaining)
end)

deathEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "Show" then
		cancelRespawnTransition()
		current = {
			Serial = data.Serial,
			ProductId = tonumber(data.ProductId) or 0,
			FreeAt = os.clock() + (tonumber(data.FreeRespawnDelaySeconds) or 4),
			Retry = false,
			PurchasePending = false,
		}
		local cause = data.Cause == "Water" and "A água alcançou você." or "Sua tentativa terminou."
		result.Text = string.format(
			"%s\nPontuação: %d  •  Moedas perdidas: %d",
			cause,
			tonumber(data.RunScore) or 0,
			tonumber(data.LostCoins) or 0
		)
		robuxButton.Active = current.ProductId > 0
		robuxButton.AutoButtonColor = current.ProductId > 0
		robuxButton.Text = current.ProductId > 0 and "RENASCER SEM PERDER MOEDAS" or "CONFIGURE O PRODUTO ROBUX"
		gui.Enabled = true
	elseif data.Action == "Granted" then
		if current then
			current.PurchasePending = false
		end
		showRespawnTransition(data.RespawnSequence)
		result.Text =
			string.format("Renascimento confirmado!\n%d moedas devolvidas.", tonumber(data.CoinsRefunded) or 0)
		robuxButton.Text = "CONFIRMADO"
	elseif data.Action == "PreparingRespawn" then
		showRespawnTransition(data.RespawnSequence)
	elseif data.Action == "RespawnReady" then
		local sequence = tonumber(data.RespawnSequence) or 0
		transitionSequence = math.max(transitionSequence or 0, sequence)
		openRespawnTransition(sequence)
	elseif data.Action == "Error" then
		if current then
			current.PurchasePending = false
		end
		if player:GetAttribute("RespawnState") == "Failed" then
			showRespawnFailure(data.Message)
		else
			cancelRespawnTransition()
			result.Text = tostring(data.Message or "Não foi possível abrir a compra.")
			robuxButton.Active = current ~= nil and current.ProductId > 0
			robuxButton.AutoButtonColor = robuxButton.Active
			robuxButton.Text = robuxButton.Active
				and "RENASCER SEM PERDER MOEDAS"
				or "CONFIGURE O PRODUTO ROBUX"
		end
	end
end)

player.CharacterAdded:Connect(function(character)
	local sequence = tonumber(player:GetAttribute("RespawnSequence")) or 0
	local isRespawning = player:GetAttribute("InitialGameStarted") == true
		and sequence > 0
		and player:GetAttribute("PlayerLifecycleState") ~= "Playing"
	if isRespawning and not transitionGui.Enabled then
		showRespawnTransition(player:GetAttribute("RespawnSequence"))
	end
	if
		isRespawning
		and
		(tonumber(player:GetAttribute("RespawnReadySequence")) or -1) >= sequence
		and character:GetAttribute("RespawnReady") == true
	then
		openRespawnTransition(sequence)
	end
end)

player:GetAttributeChangedSignal("RespawnReadySequence"):Connect(function()
	if not transitionGui.Enabled then
		return
	end
	local sequence = tonumber(player:GetAttribute("RespawnReadySequence")) or -1
	if sequence > 0 and (not transitionSequence or sequence >= transitionSequence) then
		openRespawnTransition(sequence)
	end
end)

player:GetAttributeChangedSignal("RespawnState"):Connect(function()
	local state = player:GetAttribute("RespawnState")
	if state == "Ready" and transitionGui.Enabled then
		openRespawnTransition(tonumber(player:GetAttribute("RespawnSequence")) or 0)
	elseif state == "Failed" and player:GetAttribute("InitialGameStarted") == true then
		showRespawnFailure("Não foi possível encontrar uma área segura.")
	end
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, purchasedProductId, purchased)
	if
		userId ~= player.UserId
		or not current
		or purchasedProductId ~= current.ProductId
		or not current.PurchasePending
	then
		return
	end
	current.PurchasePending = false
	if not purchased then
		robuxButton.Active = true
		robuxButton.AutoButtonColor = true
		robuxButton.Text = "RENASCER SEM PERDER MOEDAS"
		result.Text = "Compra cancelada. Você ainda pode escolher como renascer."
	end
end)

if
	player:GetAttribute("InitialGameStarted") == true
	and (tonumber(player:GetAttribute("RespawnSequence")) or 0) > 0
	and player:GetAttribute("RespawnState") ~= "Ready"
then
	showRespawnTransition(player:GetAttribute("RespawnSequence"))
end
