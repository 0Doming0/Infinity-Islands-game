-- Exibe nas costas a espada selecionada enquanto a Tool está no Backpack.

local Players = game:GetService("Players")

local DISPLAY_NAME = "EquippedSwordBackDisplay"
local DEFAULT_OFFSET = CFrame.new(0, 0.1, 0.72) * CFrame.Angles(math.rad(8), math.rad(180), math.rad(135))

local function isSword(instance)
	return instance
		and instance:IsA("Tool")
		and (instance:GetAttribute("IsSword") == true or instance:GetAttribute("WeaponType") == "Sword")
end

local function clearDisplay(character)
	local old = character and character:FindFirstChild(DISPLAY_NAME)
	if old then
		old:Destroy()
	end
	if character then
		for _, torsoName in ipairs({ "UpperTorso", "Torso" }) do
			local torso = character:FindFirstChild(torsoName)
			local motor = torso and torso:FindFirstChild("SwordBackMotor")
			if motor then
				motor:Destroy()
			end
		end
	end
end

local function findSelectedSword(player)
	local swordId = player:GetAttribute("EquippedSword")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	for _, child in ipairs(backpack:GetChildren()) do
		if isSword(child) and (not swordId or child:GetAttribute("SwordId") == swordId or child.Name == swordId) then
			return child
		end
	end
	return nil
end

local function removeRuntimeChildren(part)
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
			descendant:Destroy()
		end
	end
end

local function createDisplay(player)
	local character = player.Character
	if not character then
		return
	end
	clearDisplay(character)
	local tool = findSelectedSword(player)
	if not tool then
		return
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local sourceHandle = tool:FindFirstChild("Handle")
	if not torso or not torso:IsA("BasePart") or not sourceHandle or not sourceHandle:IsA("BasePart") then
		return
	end

	local display = Instance.new("Model")
	display.Name = DISPLAY_NAME
	display:SetAttribute("SwordId", tool:GetAttribute("SwordId") or tool.Name)
	display.Parent = character

	local clonedHandle
	local clones = {}
	for _, sourcePart in ipairs(tool:GetDescendants()) do
		if sourcePart:IsA("BasePart") then
			local clone = sourcePart:Clone()
			removeRuntimeChildren(clone)
			clone.Name = sourcePart.Name
			clone.Anchored = false
			clone.CanCollide = false
			clone.CanTouch = false
			clone.CanQuery = false
			clone.Massless = true
			clone.CastShadow = true
			clone.Parent = display
			clones[sourcePart] = clone
			if sourcePart == sourceHandle then
				clonedHandle = clone
			end
		end
	end
	if not clonedHandle then
		display:Destroy()
		return
	end

	local offset = tool:GetAttribute("BackDisplayCFrame")
	if typeof(offset) ~= "CFrame" then
		offset = DEFAULT_OFFSET
	end
	clonedHandle.CFrame = torso.CFrame * offset
	for sourcePart, clone in pairs(clones) do
		if clone ~= clonedHandle then
			clone.CFrame = clonedHandle.CFrame * sourceHandle.CFrame:ToObjectSpace(sourcePart.CFrame)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = clonedHandle
			weld.Part1 = clone
			weld.Parent = clone
		end
	end

	local backMotor = Instance.new("Motor6D")
	backMotor.Name = "SwordBackMotor"
	backMotor.Part0 = torso
	backMotor.Part1 = clonedHandle
	backMotor.C0 = offset
	backMotor.C1 = CFrame.identity
	backMotor.Parent = torso
	display.PrimaryPart = clonedHandle
end

local function scheduleRefresh(player)
	task.defer(function()
		if player.Parent == Players then
			createDisplay(player)
		end
	end)
end

local function watchContainer(player, container)
	container.ChildAdded:Connect(function(child)
		if isSword(child) then
			scheduleRefresh(player)
		end
	end)
	container.ChildRemoved:Connect(function(child)
		if isSword(child) then
			scheduleRefresh(player)
		end
	end)
end

local function setupPlayer(player)
	player:GetAttributeChangedSignal("EquippedSword"):Connect(function()
		scheduleRefresh(player)
	end)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchContainer(player, child)
			scheduleRefresh(player)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		watchContainer(player, character)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			watchContainer(player, backpack)
		end
		task.delay(0.6, scheduleRefresh, player)
	end)
	if player.Character then
		watchContainer(player, player.Character)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(player, backpack)
	end
	scheduleRefresh(player)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
