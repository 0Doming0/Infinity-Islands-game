-- MobileControlIconDecorator
--
-- Decoracao visual provisoria dos controles autorados no Studio.
-- Nao cria botoes, nao move controles e nao participa da logica de input.
-- Apenas adiciona um ImageLabel filho em JumpButton/AttackButton/SprintButton.
--
-- IMPORTANTE:
-- O caminho tradicional Image e preenchido SEMPRE. ImageContent e preenchido
-- adicionalmente quando suportado pelo runtime. Isso segue a mesma fonte usada
-- pelo proprio controle touch do Roblox e evita depender da deteccao de mobile
-- do Studio para a decoracao aparecer.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "MobileControlIconDecoratorV2_AlwaysRender"
local ICON_NAME = "ProvisionalControlIcon"
local TOUCH_SHEET_URI = "rbxasset://textures/ui/Input/TouchControlsSheetV2.png"

-- Recortes comprovadamente existentes no sheet interno do Roblox.
-- Attack continua sendo placeholder: usamos o segundo sprite de acao do sheet
-- e um pequeno simbolo de espada sobre ele para diferencia-lo visualmente.
local ICONS = {
	Jump = {
		Offset = Vector2.new(1, 146),
		Size = Vector2.new(144, 144),
		Tint = Color3.new(1, 1, 1),
		Glyph = "",
	},
	Attack = {
		Offset = Vector2.new(146, 146),
		Size = Vector2.new(144, 144),
		Tint = Color3.fromRGB(255, 230, 205),
		Glyph = "⚔",
	},
	Sprint = {
		Offset = Vector2.new(1, 1),
		Size = Vector2.new(144, 144),
		Tint = Color3.fromRGB(220, 245, 255),
		Glyph = "»",
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
local decoratedCount = {
	Jump = 0,
	Attack = 0,
	Sprint = 0,
}

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
	for _ = 1, 6 do
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

local function publishCounts()
	player:SetAttribute("DungeonProvisionalJumpIconCount", decoratedCount.Jump)
	player:SetAttribute("DungeonProvisionalAttackIconCount", decoratedCount.Attack)
	player:SetAttribute("DungeonProvisionalSprintIconCount", decoratedCount.Sprint)
	player:SetAttribute(
		"DungeonProvisionalControlIconCount",
		decoratedCount.Jump + decoratedCount.Attack + decoratedCount.Sprint
	)
end

local function applyImageSource(icon)
	-- Image e o caminho mais compativel e e usado diretamente pelos CoreScripts.
	icon.Image = TOUCH_SHEET_URI

	-- ImageContent fica preenchido tambem quando a versao do Studio/runtime
	-- oferece o novo Content datatype. Falhar aqui nao impede a imagem de render.
	pcall(function()
		icon.ImageContent = Content.fromUri(TOUCH_SHEET_URI)
	end)
end

local function ensureGlyph(icon, kind)
	local glyph = icon:FindFirstChild("ProvisionalGlyph")
	if glyph and not glyph:IsA("TextLabel") then
		glyph:Destroy()
		glyph = nil
	end
	if not glyph then
		glyph = Instance.new("TextLabel")
		glyph.Name = "ProvisionalGlyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(0.72, 0.72)
		glyph.BackgroundTransparency = 1
		glyph.Font = Enum.Font.GothamBlack
		glyph.TextScaled = true
		glyph.TextColor3 = Color3.new(1, 1, 1)
		glyph.TextStrokeColor3 = Color3.fromRGB(20, 26, 34)
		glyph.TextStrokeTransparency = 0.18
		glyph.ZIndex = icon.ZIndex + 1
		glyph.Parent = icon
	end
	glyph.Text = ICONS[kind].Glyph
	glyph.Visible = ICONS[kind].Glyph ~= ""
end

local function decorate(button)
	local kind = controlKind(button)
	if not kind then
		return
	end

	local firstDecoration = decorated[button] ~= true
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
		icon.Size = UDim2.fromScale(0.68, 0.68)
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Active = false
		icon.Selectable = false
		icon.Visible = true
		icon.Parent = button
	end

	icon.Visible = true
	icon.Size = UDim2.fromScale(0.68, 0.68)
	icon.ZIndex = math.max(button.ZIndex + 10, 20)
	applyImageSource(icon)
	icon.ImageRectOffset = config.Offset
	icon.ImageRectSize = config.Size
	icon.ImageColor3 = config.Tint
	icon.ImageTransparency = 0
	ensureGlyph(icon, kind)

	button:SetAttribute("DungeonProvisionalControlIcon", kind)
	button:SetAttribute("DungeonProvisionalControlIconVersion", VERSION)
	button:SetAttribute("DungeonProvisionalIconReplaceLater", true)
	icon:SetAttribute("DungeonControlIconKind", kind)
	icon:SetAttribute("DungeonProvisional", true)
	icon:SetAttribute("DungeonImageContentUri", TOUCH_SHEET_URI)
	icon:SetAttribute("DungeonImageFallbackAssigned", icon.Image == TOUCH_SHEET_URI)

	if firstDecoration then
		decoratedCount[kind] += 1
		publishCounts()
	end
end

local function inspect(instance)
	if instance:IsA("GuiButton") then
		decorate(instance)
	end
end

local function scan()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		inspect(descendant)
	end
	publishCounts()
end

-- Nao condicionamos mais a TouchEnabled/DungeonMobileMode. Em Device Emulator
-- esses sinais podem nao refletir o hardware real no instante em que o script
-- inicia. Se o controle autorado existe, ele recebe o placeholder visual.
playerGui.DescendantAdded:Connect(function(instance)
	if instance:IsA("GuiButton") then
		task.defer(decorate, instance)
	end
end)

-- Alguns HUDs sao clonados/reconstruidos depois do primeiro frame.
task.defer(scan)
task.delay(1, scan)
task.delay(3, scan)

player:SetAttribute("DungeonMobileControlIconDecoratorVersion", VERSION)
player:SetAttribute("DungeonMobileControlIconsProvisional", true)
player:SetAttribute("DungeonMobileControlIconSource", "RobloxTouchControlsSheetV2")
player:SetAttribute("DungeonMobileControlIconRequiresMobileDetection", false)
publishCounts()
