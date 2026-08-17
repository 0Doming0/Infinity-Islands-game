-- Assistencia de combate mobile: tocar em atacar liga/desliga a aproximacao
-- automatica do inimigo valido mais proximo. O layout do botao continua sendo
-- 100% definido no Roblox Studio; este script nunca altera Position/Size.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CombatConfig = require(ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig"))

local VERSION = "MobileAttackAutoWalkV1"
local AUTO_RADIUS = 36
local MAX_VERTICAL = 10
local ATTACK_DISTANCE = 5.25
local MOVE_REFRESH = 0.14
local ATTACK_RETRY = math.clamp(tonumber(CombatConfig.InputBufferTime) and CombatConfig.InputBufferTime * 0.5 or 0.06, 0.04, 0.08)

local BUTTON_NAMES = {
	swordattackbutton = true,
	attackbutton = true,
	mobileattackbutton = true,
	attackimagebutton = true,
	attack = true,
}

local engaged = false
local serial = 0
local target
local lastMoveAt = 0
local boundButtons = setmetatable({}, { __mode = "k" })

local function isMobile()
	return player:GetAttribute("DungeonMobileMode") == true
end

local function rootOf(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function equippedSword()
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if CombatConfig.IsSword(child) then
			return child
		end
	end
	return nil
end

local function validTarget(model, character, characterRoot)
	if not model or not model:IsA("Model") or not model.Parent or model == character then
		return false
	end
	if model:GetAttribute("Peaceful") == true
		or model:GetAttribute("Invulnerable") == true
		or model:GetAttribute("NoSwordDamage") == true
		or model:GetAttribute("ObjectiveTargetCompleted") == true
	then
		return false
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = rootOf(model)
	if not humanoid or humanoid.Health <= 0 or not root then
		return false
	end

	local targetIsland = tonumber(model:GetAttribute("CombatIslandIndex") or model:GetAttribute("GlobalIslandIndex"))
	local currentIsland = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
	if targetIsland and currentIsland and math.floor(targetIsland) ~= math.floor(currentIsland) then
		return false
	end

	local offset = root.Position - characterRoot.Position
	local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
	return math.abs(offset.Y) <= MAX_VERTICAL and horizontal <= AUTO_RADIUS
end

local function nearestTarget()
	local character = player.Character
	local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not characterRoot or not characterRoot:IsA("BasePart") then
		return nil
	end

	local nearest
	local bestDistance = math.huge
	local seen = {}
	for _, tagged in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		local model = tagged:IsA("Model") and tagged or tagged:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			if validTarget(model, character, characterRoot) then
				local root = rootOf(model)
				local offset = root.Position - characterRoot.Position
				local distance = Vector2.new(offset.X, offset.Z).Magnitude
				if distance < bestDistance then
					nearest = model
					bestDistance = distance
				end
			end
		end
	end
	return nearest, bestDistance
end

local function stop(reason)
	serial += 1
	engaged = false
	target = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero)
		if character and character:FindFirstChild("HumanoidRootPart") then
			humanoid:MoveTo(character.HumanoidRootPart.Position)
		end
	end
	player:SetAttribute("DungeonMobileAttackHeld", false)
	player:SetAttribute("DungeonMobileAutoEngageTarget", nil)
	player:SetAttribute("DungeonMobileAutoEngageDistance", nil)
	player:SetAttribute("DungeonMobileAutoEngageState", reason or "Idle")
end

local function begin()
	if not isMobile() then
		return
	end
	if player:GetAttribute("IsDowned") == true
		or (player.Character and player.Character:GetAttribute("MovementLocked") == true)
	then
		return
	end
	if not equippedSword() then
		stop("NoSword")
		return
	end

	serial += 1
	local mySerial = serial
	engaged = true
	player:SetAttribute("DungeonMobileAttackHeld", true)
	player:SetAttribute("DungeonMobileAutoEngageState", "Searching")

	task.spawn(function()
		while engaged and serial == mySerial do
			if not isMobile() or player:GetAttribute("IsDowned") == true then
				stop("Unavailable")
				return
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local sword = equippedSword()
			if not character or not humanoid or humanoid.Health <= 0 or not root or not sword
				or character:GetAttribute("MovementLocked") == true
			then
				stop("CharacterUnavailable")
				return
			end

			if not target or not validTarget(target, character, root) then
				target = nearestTarget()
			end
			if not target then
				stop("NoNearbyTarget")
				return
			end

			local targetRoot = rootOf(target)
			if not targetRoot then
				target = nil
				task.wait(ATTACK_RETRY)
				continue
			end

			local offset = targetRoot.Position - root.Position
			local distance = Vector2.new(offset.X, offset.Z).Magnitude
			player:SetAttribute("DungeonMobileAutoEngageTarget", target.Name)
			player:SetAttribute("DungeonMobileAutoEngageDistance", distance)

			local flatTarget = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
			if distance > ATTACK_DISTANCE then
				player:SetAttribute("DungeonMobileAutoEngageState", "Approaching")
				if os.clock() - lastMoveAt >= MOVE_REFRESH then
					lastMoveAt = os.clock()
					humanoid:MoveTo(flatTarget)
				end
			else
				player:SetAttribute("DungeonMobileAutoEngageState", "Attacking")
				humanoid:Move(Vector3.zero)
				if (flatTarget - root.Position).Magnitude > 0.05 then
					root.CFrame = CFrame.lookAt(root.Position, flatTarget)
				end
				sword:Activate()
			end

			task.wait(ATTACK_RETRY)
		end
	end)
end

local function toggle()
	if not isMobile() then
		return
	end
	if engaged then
		stop("PlayerCancelled")
	else
		begin()
	end
end

local function isAttackButton(button)
	if not button or not button:IsA("GuiButton") then
		return false
	end
	if BUTTON_NAMES[string.lower(button.Name)] then
		return true
	end
	local parent = button.Parent
	return parent and BUTTON_NAMES[string.lower(parent.Name)] == true
end

local function bindButton(button)
	if not isAttackButton(button) or boundButtons[button] then
		return
	end
	boundButtons[button] = true
	button:SetAttribute("DungeonMobileAutoWalkBound", true)
	button.Activated:Connect(toggle)
end

local function scan()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		bindButton(descendant)
	end
end

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindButton, instance)
end)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	if not isMobile() then
		stop("MobileModeEnded")
	end
	task.defer(scan)
end)
player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") == true then
		stop("Downed")
	end
end)
player.CharacterAdded:Connect(function(character)
	stop("CharacterChanged")
	character:GetAttributeChangedSignal("MovementLocked"):Connect(function()
		if character:GetAttribute("MovementLocked") == true then
			stop("MovementLocked")
		end
	end)
end)

task.defer(scan)
player:SetAttribute("DungeonMobileAutoWalkReady", true)
player:SetAttribute("DungeonMobileAutoWalkVersion", VERSION)
player:SetAttribute("DungeonMobileHoldAttackPolicy", "TapToGuideNearestTarget_StudioButtonV3")
