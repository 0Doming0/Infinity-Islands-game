--[[
	VillagerUI.client.lua

	Interface de loja de aldeoes.
	- Mostra prompt "Pressione E" quando proximo de um aldeao
	- Abre painel de loja com itens, precos e estoque
	- Envia compras para o servidor via VillagerEvent
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local villagerEvent = ReplicatedStorage:WaitForChild("VillagerEvent")

-- ============================================================
-- UI: PROMPT DE INTERACAO
-- ============================================================

local promptGui = Instance.new("ScreenGui")
promptGui.Name = "VillagerPromptGui"
promptGui.ResetOnSpawn = false
promptGui.Parent = playerGui

local promptFrame = Instance.new("Frame")
promptFrame.Size = UDim2.fromOffset(260, 60)
promptFrame.Position = UDim2.new(0.5, -130, 0.75, -30)
promptFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 28)
promptFrame.BackgroundTransparency = 0.1
promptFrame.Visible = false
promptFrame.Parent = promptGui

local promptCorner = Instance.new("UICorner")
promptCorner.CornerRadius = UDim.new(0, 10)
promptCorner.Parent = promptFrame

local promptStroke = Instance.new("UIStroke")
promptStroke.Color = Color3.fromRGB(60, 200, 80)
promptStroke.Thickness = 2
promptStroke.Parent = promptFrame

local promptLabel = Instance.new("TextLabel")
promptLabel.Size = UDim2.fromScale(1, 1)
promptLabel.BackgroundTransparency = 1
promptLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
promptLabel.Text = "Pressione [E] para abrir a Loja"
promptLabel.TextScaled = true
promptLabel.Font = Enum.Font.GothamBold
promptLabel.Parent = promptFrame

local promptUICorner2 = Instance.new("UICorner")
promptUICorner2.CornerRadius = UDim.new(0, 10)
promptUICorner2.Parent = promptLabel

-- ============================================================
-- UI: PAINEL DA LOJA
-- ============================================================

local shopGui = Instance.new("ScreenGui")
shopGui.Name = "VillagerShopGui"
shopGui.ResetOnSpawn = false
shopGui.Parent = playerGui

-- Fundo escuro
local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.5
backdrop.Visible = false
backdrop.Parent = shopGui

-- Painel principal
local shopFrame = Instance.new("Frame")
shopFrame.Size = UDim2.fromOffset(480, 420)
shopFrame.Position = UDim2.new(0.5, -240, 0.5, -210)
shopFrame.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
shopFrame.BackgroundTransparency = 0.05
shopFrame.Visible = false
shopFrame.Parent = shopGui

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 14)
shopCorner.Parent = shopFrame

local shopStroke = Instance.new("UIStroke")
shopStroke.Color = Color3.fromRGB(60, 200, 80)
shopStroke.Thickness = 2
shopStroke.Parent = shopFrame

-- Titulo
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -30, 0, 50)
titleLabel.Position = UDim2.fromOffset(15, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
titleLabel.Text = "Loja do Aldeao"
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = shopFrame

-- Score atual
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Size = UDim2.fromOffset(160, 30)
scoreLabel.Position = UDim2.new(1, -175, 0, 22)
scoreLabel.BackgroundColor3 = Color3.fromRGB(30, 36, 42)
scoreLabel.BackgroundTransparency = 0.2
scoreLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
scoreLabel.Text = "Pontos: 0"
scoreLabel.TextScaled = true
scoreLabel.Font = Enum.Font.GothamBold
scoreLabel.Parent = shopFrame

local scoreCorner = Instance.new("UICorner")
scoreCorner.CornerRadius = UDim.new(0, 8)
scoreCorner.Parent = scoreLabel

-- Container de itens (scrolling)
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -30, 1, -110)
scrollFrame.Position = UDim2.fromOffset(15, 70)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 6
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = shopFrame

local itemList = Instance.new("UIListLayout")
itemList.Padding = UDim.new(0, 8)
itemList.Parent = scrollFrame

-- Botao Fechar
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(80, 36)
closeButton.Position = UDim2.new(0.5, -40, 1, -48)
closeButton.BackgroundColor3 = Color3.fromRGB(70, 40, 40)
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Text = "Fechar"
closeButton.TextScaled = true
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = shopFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

-- Mensagem de feedback
local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Size = UDim2.fromOffset(300, 40)
feedbackLabel.Position = UDim2.new(0.5, -150, 0.15, 0)
feedbackLabel.BackgroundColor3 = Color3.fromRGB(30, 36, 42)
feedbackLabel.BackgroundTransparency = 0.1
feedbackLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
feedbackLabel.Text = ""
feedbackLabel.TextScaled = true
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.Visible = false
feedbackLabel.ZIndex = 10
feedbackLabel.Parent = shopGui

local feedbackCorner = Instance.new("UICorner")
feedbackCorner.CornerRadius = UDim.new(0, 8)
feedbackCorner.Parent = feedbackLabel

-- ============================================================
-- LOGICA
-- ============================================================

local shopOpen = false
local currentRarityColor = Color3.fromRGB(60, 200, 80)

local function showFeedback(text, color)
	feedbackLabel.Text = text
	feedbackLabel.TextColor3 = color or Color3.fromRGB(100, 255, 100)
	feedbackLabel.Visible = true
	feedbackLabel.TextTransparency = 0

	TweenService:Create(feedbackLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()

	task.delay(2, function()
		local tween = TweenService:Create(feedbackLabel, TweenInfo.new(0.5), { TextTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			feedbackLabel.Visible = false
		end)
	end)
end

local function clearItems()
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function createItemRow(item, index)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 72)
	row.BackgroundColor3 = Color3.fromRGB(30, 36, 42)
	row.BackgroundTransparency = 0.15
	row.Parent = scrollFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = currentRarityColor:Lerp(Color3.fromRGB(50, 50, 50), 0.5)
	rowStroke.Thickness = 1
	rowStroke.Parent = row

	-- Label do item
	local itemLabel = Instance.new("TextLabel")
	itemLabel.Size = UDim2.new(0.55, 0, 1, 0)
	itemLabel.BackgroundTransparency = 1
	itemLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	itemLabel.Text = item.label
	itemLabel.TextScaled = true
	itemLabel.Font = Enum.Font.GothamBold
	itemLabel.TextXAlignment = Enum.TextXAlignment.Left
	itemLabel.Parent = row

	-- Preco
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Size = UDim2.fromOffset(70, 1)
	priceLabel.Position = UDim2.new(0.55, 0, 0, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
	priceLabel.Text = tostring(item.price)
	priceLabel.TextScaled = true
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.Parent = row

	-- Estoque
	local stockLabel = Instance.new("TextLabel")
	stockLabel.Size = UDim2.fromOffset(50, 1)
	stockLabel.Position = UDim2.new(0.72, 0, 0, 0)
	stockLabel.BackgroundTransparency = 1
	stockLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	stockLabel.Text = "x" .. tostring(item.stock)
	stockLabel.TextScaled = true
	stockLabel.Font = Enum.Font.Gotham
	stockLabel.Parent = row

	-- Botao Comprar
	local buyButton = Instance.new("TextButton")
	buyButton.Size = UDim2.fromOffset(70, 1)
	buyButton.Position = UDim2.new(0.85, 0, 0, 0)
	buyButton.BackgroundColor3 = currentRarityColor
	buyButton.BackgroundTransparency = 0.2
	buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyButton.Text = "Comprar"
	buyButton.TextScaled = true
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Parent = row

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 6)
	buyCorner.Parent = buyButton

	if item.stock <= 0 then
		buyButton.Text = "Esgotado"
		buyButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		buyButton.TextColor3 = Color3.fromRGB(120, 120, 120)
		buyButton.Active = false
		buyButton.AutoButtonColor = false
	end

	buyButton.MouseButton1Click:Connect(function()
		if item.stock <= 0 then return end
		villagerEvent:FireServer({ action = "buy", itemIndex = index })
	end)

	return row, stockLabel, buyButton
end

local function openShop(data)
	shopOpen = true
	currentRarityColor = data.rarityColor or Color3.fromRGB(60, 200, 80)

	-- Atualizar borda com cor da raridade
	shopStroke.Color = currentRarityColor
	titleLabel.Text = "Loja do Aldeao " .. (data.rarity or "")
	scoreLabel.Text = "Pontos: " .. tostring(data.score or 0)

	clearItems()

	for i, item in ipairs(data.inventory) do
		createItemRow(item, i)
	end

	backdrop.Visible = true
	shopFrame.Visible = true
end

local function closeShop()
	shopOpen = false
	backdrop.Visible = false
	shopFrame.Visible = false
	villagerEvent:FireServer({ action = "closeShop" })
end

-- ============================================================
-- EVENTOS
-- ============================================================

closeButton.MouseButton1Click:Connect(closeShop)
backdrop.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		closeShop()
	end
end)

-- Tecla E para abrir loja
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		if not shopOpen and promptFrame.Visible then
			villagerEvent:FireServer({ action = "openShop" })
		end
	end
	if input.KeyCode == Enum.KeyCode.Escape and shopOpen then
		closeShop()
	end
end)

-- Receber mensagens do servidor
villagerEvent.OnClientEvent:Connect(function(data)
	if not data or not data.action then return end

	if data.action == "showPrompt" then
		promptFrame.Visible = true
		promptStroke.Color = data.rarityColor or Color3.fromRGB(60, 200, 80)
		promptLabel.Text = "Pressione [E] - Loja " .. (data.rarity or "")

	elseif data.action == "hidePrompt" then
		promptFrame.Visible = false

	elseif data.action == "showShop" then
		openShop(data)

	elseif data.action == "purchaseSuccess" then
		scoreLabel.Text = "Pontos: " .. tostring(data.newScore or 0)
		showFeedback("Comprou: " .. (data.itemLabel or "Item"), Color3.fromRGB(100, 255, 100))

		-- Atualizar estoque do item comprado
		local rows = scrollFrame:GetChildren()
		local rowIndex = 0
		for _, child in scrollFrame:GetChildren() do
			if child:IsA("Frame") then
				rowIndex += 1
				if rowIndex == data.itemIndex then
					-- Atualizar texto de estoque e botao
					for _, gui in child:GetChildren() do
						if gui:IsA("TextLabel") and gui.Text:sub(1, 1) == "x" then
							gui.Text = "x" .. tostring(data.newStock)
						end
						if gui:IsA("TextButton") then
							if data.newStock <= 0 then
								gui.Text = "Esgotado"
								gui.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
								gui.TextColor3 = Color3.fromRGB(120, 120, 120)
								gui.Active = false
								gui.AutoButtonColor = false
							end
						end
					end
				end
			end
		end

	elseif data.action == "purchaseFailed" then
		showFeedback(data.reason or "Falha na compra", Color3.fromRGB(255, 80, 80))

	elseif data.action == "shopEmpty" then
		showFeedback("Todos os itens esgotaram!", Color3.fromRGB(255, 180, 60))
		task.wait(1.5)
		closeShop()
	end
end)