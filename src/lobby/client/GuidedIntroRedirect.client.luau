-- Task 20 — transition screen while a new player is redirected to GuidedIntro.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "GuidedIntroRedirectUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 300
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(7, 17, 28)
backdrop.BackgroundTransparency = 0.04
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1
backdrop.Parent = gui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.new(1, -36, 0, 170)
card.BackgroundColor3 = Color3.fromRGB(17, 38, 55)
card.BorderSizePixel = 0
card.ZIndex = 2
card.Parent = backdrop

local size = Instance.new("UISizeConstraint")
size.MinSize = Vector2.new(280, 160)
size.MaxSize = Vector2.new(440, 180)
size.Parent = card

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 18)
corner.Parent = card

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(109, 224, 255)
stroke.Transparency = 0.18
stroke.Thickness = 1.5
stroke.Parent = card

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(18, 20)
title.Size = UDim2.new(1, -36, 0, 34)
title.BackgroundTransparency = 1
title.Text = "SEU PRIMEIRO VOO"
title.TextColor3 = Color3.fromRGB(116, 229, 255)
title.Font = Enum.Font.GothamBlack
title.TextSize = 20
title.TextWrapped = true
title.ZIndex = 3
title.Parent = card

local body = Instance.new("TextLabel")
body.Position = UDim2.fromOffset(18, 62)
body.Size = UDim2.new(1, -36, 0, 63)
body.BackgroundTransparency = 1
body.Text = "Antes de conhecer o Lobby, voce fara uma introducao rapida ao combate e as recompensas."
body.TextColor3 = Color3.fromRGB(239, 247, 252)
body.Font = Enum.Font.GothamBold
body.TextSize = 12
body.TextWrapped = true
body.ZIndex = 3
body.Parent = card

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -14)
status.Size = UDim2.new(1, -36, 0, 22)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(164, 190, 209)
status.Font = Enum.Font.GothamMedium
status.TextSize = 10
status.ZIndex = 3
status.Parent = card

local function refresh()
	local redirecting = player:GetAttribute("GuidedIntroRedirecting") == true
	local completed = player:GetAttribute("GuidedIntroCompleted") == true
	gui.Enabled = redirecting and not completed

	local errorText = player:GetAttribute("GuidedIntroRedirectError")
	status.Text = type(errorText) == "string" and errorText ~= ""
		and "Tentando novamente..."
		or "Preparando a introducao..."
end

for _, name in ipairs({
	"GuidedIntroRedirecting",
	"GuidedIntroCompleted",
	"GuidedIntroRedirectError",
}) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end

refresh()
