-- Experience Polish: a primeira acao precisa ser obvia.
-- Mostra um indicador local sobre o slime inicial mais proximo ate o jogador
-- acertar qualquer slime da primeira ilha. Nao cria tutorial modal e nao move
-- nem redimensiona controles do HUD.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local CombatConfig = require(
	ReplicatedStorage
		:WaitForChild("SwordCombat")
		:WaitForChild("CombatConfig")
)

local VERSION = "InitialIslandAttackGuideV1"
local TARGET_TAG = CombatConfig.TargetTag
local UPDATE_INTERVAL = 0.15

local learnedAttack = false
local elapsed = 0
local currentTarget
local highlight
local billboard
local label
local pulseTween

local function rootOf(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function alive(model)
	local humanoid = model and model:FindFirstChildWhichIsA("Humanoid", true)
	return humanoid ~= nil and humanoid.Health > 0
end

local function isInitialTarget(model)
	return model
		and model:IsA("Model")
		and model.Parent ~= nil
		and model:GetAttribute("IsInitialIslandMob") == true
		and model:GetAttribute("TutorialAttackGuideActive") ~= false
		and alive(model)
		and rootOf(model) ~= nil
end

local function localPlayerAlreadyHit(model)
	local userId = model:GetAttribute("LastDamagedByUserId")
		or model:GetAttribute("LastHitUserId")
	return typeof(userId) == "number" and userId == player.UserId
end

local function destroyGuide()
	currentTarget = nil
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	if billboard then
		billboard:Destroy()
		billboard = nil
		label = nil
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

local function ensureGuide(target)
	if currentTarget == target and highlight and highlight.Parent and billboard and billboard.Parent then
		return
	end

	destroyGuide()
	currentTarget = target
	local targetRoot = rootOf(target)
	if not targetRoot then
		return
	end

	highlight = Instance.new("Highlight")
	highlight.Name = "InitialAttackGuideHighlight"
	highlight.Adornee = target
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 218, 72)
	highlight.FillTransparency = 0.84
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0.02
	highlight.Parent = workspace.CurrentCamera or workspace

	billboard = Instance.new("BillboardGui")
	billboard.Name = "InitialAttackGuideBillboard"
	billboard.Adornee = targetRoot
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Size = UDim2.fromOffset(150, 46)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, math.max(3.3, target:GetExtentsSize().Y * 0.58 + 1.1), 0)
	billboard.Parent = targetRoot

	label = Instance.new("TextLabel")
	label.Name = "AttackText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "⚔  ATAQUE!"
	label.TextColor3 = Color3.fromRGB(255, 238, 91)
	label.TextStrokeColor3 = Color3.fromRGB(28, 13, 6)
	label.TextStrokeTransparency = 0.08
	label.TextScaled = true
	label.Parent = billboard

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 15
	constraint.MaxTextSize = 30
	constraint.Parent = label

	pulseTween = TweenService:Create(
		label,
		TweenInfo.new(0.48, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ TextTransparency = 0.22 }
	)
	pulseTween:Play()
end

local function nearestInitialTarget()
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local best
	local bestDistance = math.huge

	for _, tagged in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		local model = tagged:IsA("Model") and tagged or tagged:FindFirstAncestorOfClass("Model")
		if model and isInitialTarget(model) then
			if localPlayerAlreadyHit(model) then
				learnedAttack = true
				return nil
			end
			local targetRoot = rootOf(model)
			local distance = playerRoot and (targetRoot.Position - playerRoot.Position).Magnitude or 0
			if distance < bestDistance then
				best = model
				bestDistance = distance
			end
		end
	end
	return best
end

local function refresh()
	if learnedAttack then
		destroyGuide()
		return
	end

	local islandIndex = math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0)
	if islandIndex ~= 1 then
		destroyGuide()
		return
	end

	local target = nearestInitialTarget()
	if learnedAttack or not target then
		destroyGuide()
		return
	end
	ensureGuide(target)
end

player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(refresh)
player.CharacterAdded:Connect(function()
	task.delay(0.25, refresh)
end)
CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(function()
	task.defer(refresh)
end)
CollectionService:GetInstanceRemovedSignal(TARGET_TAG):Connect(function()
	task.defer(refresh)
end)

RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	refresh()
end)

player:SetAttribute("DungeonInitialAttackGuideVersion", VERSION)
task.defer(refresh)
