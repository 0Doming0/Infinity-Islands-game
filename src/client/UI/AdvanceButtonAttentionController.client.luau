--[[
	Infinity Islands - Advance Button Attention Controller V1

	Presentation-only controller for the existing AssistedIslandTransportHUD /
	AdvanceButton. It never sends transport requests and never creates a second
	advance flow.

	Rules:
	- Button is visible only while the server says the current island is
	  personally unlocked AND ManualIslandAdvance is Ready.
	- While visible it continuously pulses to demand immediate attention.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "AdvanceButtonAttentionControllerV1"
local PULSE_SCALE = 1.11
local PULSE_SECONDS = 0.46

local gui = playerGui:WaitForChild("AssistedIslandTransportHUD")
local button = gui:WaitForChild("AdvanceButton")

if not button:IsA("GuiButton") then
	warn("[AdvanceButtonAttentionController] AdvanceButton nao e GuiButton")
	return
end

local scale = button:FindFirstChild("AdvanceAttentionScale")
if not scale or not scale:IsA("UIScale") then
	if scale then
		scale:Destroy()
	end
	scale = Instance.new("UIScale")
	scale.Name = "AdvanceAttentionScale"
	scale.Scale = 1
	scale.Parent = button
end

local stroke = button:FindFirstChildWhichIsA("UIStroke")
local originalStrokeTransparency = stroke and stroke.Transparency or nil
local pulseTween
local strokeTween
local pulsing = false

local function eligible()
	if player:GetAttribute("DungeonPersonalAdvanceUnlocked") ~= true then
		return false
	end
	if player:GetAttribute("DungeonManualAdvanceReady") ~= true then
		return false
	end
	local state = tostring(player:GetAttribute("DungeonAssistedTransportState") or "")
	return state == "Ready"
end

local function stopPulse()
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	if strokeTween then
		strokeTween:Cancel()
		strokeTween = nil
	end
	pulsing = false
	scale.Scale = 1
	if stroke and originalStrokeTransparency ~= nil then
		stroke.Transparency = originalStrokeTransparency
	end
end

local function startPulse()
	if pulsing then
		return
	end
	pulsing = true

	-- Small entrance pop, followed by an infinite breathing pulse.
	scale.Scale = 0.88
	local entrance = TweenService:Create(
		scale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.03 }
	)
	entrance:Play()
	entrance.Completed:Once(function()
		if not pulsing or not eligible() then
			return
		end
		pulseTween = TweenService:Create(
			scale,
			TweenInfo.new(
				PULSE_SECONDS,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{ Scale = PULSE_SCALE }
		)
		pulseTween:Play()

		if stroke then
			strokeTween = TweenService:Create(
				stroke,
				TweenInfo.new(
					PULSE_SECONDS,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true
				),
				{ Transparency = 0.02 }
			)
			strokeTween:Play()
		end
	end)
end

local function refresh()
	local shouldShow = eligible()
	button.Visible = shouldShow

	if shouldShow then
		startPulse()
	else
		stopPulse()
	end

	player:SetAttribute("DungeonAdvanceButtonAttentionActive", shouldShow)
end

for _, attribute in ipairs({
	"DungeonPersonalAdvanceUnlocked",
	"DungeonManualAdvanceReady",
	"DungeonAssistedTransportState",
	"CurrentGlobalIslandIndex",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		task.defer(refresh)
	end)
end

-- The legacy transport controller also writes Button.Visible directly when it
-- receives ReadyToAdvance. Enforce the personal gate every frame so a late
-- shared-clear event can never flash the button before eligibility catches up.
RunService.RenderStepped:Connect(function()
	local shouldShow = eligible()
	if button.Visible ~= shouldShow then
		button.Visible = shouldShow
	end
	if shouldShow and not pulsing then
		startPulse()
	elseif not shouldShow and pulsing then
		stopPulse()
	end
end)

player:SetAttribute("DungeonAdvanceButtonAttentionVersion", VERSION)
player:SetAttribute("DungeonAdvanceButtonAttentionPolicy", "PersonalReadyOnly_Pulsing")
refresh()

script.Destroying:Connect(function()
	stopPulse()
end)
