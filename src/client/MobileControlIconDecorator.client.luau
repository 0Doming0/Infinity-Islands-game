-- MobileControlIconDecorator
--
-- Decoracao visual provisoria dos controles mobile autorados no Studio.
-- Nao cria botoes, nao move controles e nao participa da logica de input.
-- Apenas adiciona um ImageLabel filho em JumpButton/AttackButton/SprintButton.
--
-- Para substituir depois: troque o ImageContent/Image do filho
-- "ProvisionalControlIcon" no Studio/codigo e remova o sprite crop se usar
-- uma imagem individual.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "MobileControlIconDecoratorV1_Provisional"
local ICON_NAME = "ProvisionalControlIcon"
local TOUCH_SHEET_URI = "rbxasset://textures/ui/Input/TouchControlsSheetV2.png"

-- Sprites provisórios do pacote interno de touch do Roblox.
-- Jump usa o sprite de pulo; Sprint usa o anel de movimento; Attack usa uma
-- segunda variacao do sprite touch apenas para diferenciar visualmente ate que
-- os assets finais sejam enviados.
local ICONS = {
	Jump = {
		Offset = Vector2.new(1, 146),
		Size = Vector2.new(144, 144),
	},
	Attack = {
		Offset = Vector2.new(146, 146),
		Size = Vector2.new(144, 144),
	},
	Sprint = {
		Offset = Vector2.new(1, 1),
		Size = Vector2.new(144, 144),
	},
}

local ATTACK_NAMES = {
	attackbutton = true,
	swordattackbutton = true,
	mobileattackbutton = true,
	attackimagebutton = true,
	attack = true,
}

local SPRINT_NAMES = {
	sprintbutton = true,
	runbutton = true,
	mobilesprintbutton = true,
}

local decorated = setmetatable({}, { __mode = "k" })

local function isMobile()
	return player:GetAttribute("DungeonMobileMode") == true
		or UserInputService.TouchEnabled == true
end

local function isInsideTouchGui(instance)
	local current = instance
	while current and current ~= playerGui do
		if current.Name == "TouchGui" then
			return true
		end
		current = current.Parent
	end
	return false
end

local function controlKind(instance)
	if not instance or not instance:IsA("GuiButton") then
		return nil
	end

	local current = instance
	for _ = 1, 5 do
		if not current or current == playerGui then
			break
		end
		local name = string.lower(current.Name)
		if name == "jumpbutton" and not isInsideTouchGui(instance) then
			return "Jump"
		end
		if ATTACK_NAMES[name] then
			return "Attack"
		end
		if SPRINT_NAMES[name] then
			return "Sprint"
		end
		current = current.Parent
	end
	return nil
end

local function setImageContent(icon)
	-- ImageContent e a propriedade nova; Image fica como fallback de
	-- compatibilidade para Studio/runtime que ainda serialize ContentId.
	local ok = pcall(function()
		icon.ImageContent = Content.fromUri(TOUCH_SHEET_URI)
	end)
	if not ok then
		icon.Image = TOUCH_SHEET_URI
	end
end

local function decorate(button)
	local kind = controlKind(button)
	if not kind or decorated[button] then
		return
	end
	decorated[button] = true

	local config = ICONS[kind]
	local icon = button:FindFirstChild(ICON_NAME)
	if icon and not icon:IsA("ImageLabel") then
		icon:Destroy()
		icon = nil
	end
	if not icon then
		icon = Instance.new("ImageLabel")
		icon.Name = ICON_NAME
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.60, 0.60)
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Active = false
		icon.Selectable = false
		icon.Parent = button
	end

	setImageContent(icon)
	icon.ImageRectOffset = config.Offset
	icon.ImageRectSize = config.Size
	icon.ImageColor3 = Color3.new(1, 1, 1)
	icon.ImageTransparency = 0
	icon.ZIndex = button.ZIndex + 2

	button:SetAttribute("DungeonProvisionalControlIcon", kind)
	button:SetAttribute("DungeonProvisionalControlIconVersion", VERSION)
	button:SetAttribute("DungeonProvisionalIconReplaceLater", true)
	icon:SetAttribute("DungeonControlIconKind", kind)
	icon:SetAttribute("DungeonProvisional", true)
	icon:SetAttribute("DungeonImageContentUri", TOUCH_SHEET_URI)
end

local function scan()
	if not isMobile() then
		return
	end
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			decorate(descendant)
		end
	end
end

playerGui.DescendantAdded:Connect(function(instance)
	if isMobile() and instance:IsA("GuiButton") then
		task.defer(decorate, instance)
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	if isMobile() then
		task.defer(scan)
	end
end)

if isMobile() then
	task.defer(scan)
end

player:SetAttribute("DungeonMobileControlIconDecoratorVersion", VERSION)
player:SetAttribute("DungeonMobileControlIconsProvisional", true)
player:SetAttribute("DungeonMobileControlIconSource", "RobloxTouchControlsSheetV2")
