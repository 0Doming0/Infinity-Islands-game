local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local TEXT = MVPConfig.SafeZones or {}
local gui = Instance.new("ScreenGui")
gui.Name = "SanctuaryStatusUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 35
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "SafeAreaBanner"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, -90)
panel.Size = UDim2.new(0.78, 0, 0, 72)
panel.BackgroundColor3 = Color3.fromRGB(17, 45, 46)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(260, 66)
sizeConstraint.MaxSize = Vector2.new(560, 76)
sizeConstraint.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(118, 235, 210)
stroke.Transparency = 0.25
stroke.Thickness = 1.5
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(14, 8)
title.Size = UDim2.new(1, -28, 0, 27)
title.BackgroundTransparency = 1
title.Text = tostring(TEXT.TitleText or "SANTUÁRIO — ÁREA SEGURA")
title.TextColor3 = Color3.fromRGB(195, 255, 238)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(14, 35)
subtitle.Size = UDim2.new(1, -28, 0, 25)
subtitle.BackgroundTransparency = 1
subtitle.Text = tostring(TEXT.SubtitleText or "Descanse e prepare-se antes de continuar a exploração.")
subtitle.TextColor3 = Color3.fromRGB(151, 211, 202)
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 13
subtitle.TextWrapped = true
subtitle.Parent = panel

local shown = false
local tween

local function setShown(value)
	if shown == value then
		return
	end
	shown = value
	if tween then
		tween:Cancel()
	end
	if value then
		panel.Visible = true
		panel.Position = UDim2.new(0.5, 0, 0, -90)
		tween = TweenService:Create(
			panel,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 18) }
		)
		tween:Play()
	else
		tween = TweenService:Create(
			panel,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -90) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			if not shown then
				panel.Visible = false
			end
		end)
	end
end

local function refresh()
	setShown(
		player:GetAttribute("InSafeZone") == true
			and player:GetAttribute("SafeZoneType") == "Sanctuary"
	)
end

player:GetAttributeChangedSignal("InSafeZone"):Connect(refresh)
player:GetAttributeChangedSignal("SafeZoneType"):Connect(refresh)
refresh()
