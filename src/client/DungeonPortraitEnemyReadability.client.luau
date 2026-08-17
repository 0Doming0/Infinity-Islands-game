-- Mobile enemy overhead simplificado.
-- EnemyCombatFeedback continua sendo a autoridade do Billboard com nome + vida.
-- Este controller apenas garante que os antigos badges de funcao/perigo
-- (RANGED, MORTEIRO, GUARDA, etc.) nao sejam exibidos.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local VERSION = "EnemyOverheadNameHealthOnlyV2"
local elapsed = 0
local UPDATE_INTERVAL = 0.35

local function cleanModel(model)
	if not model or not model:IsA("Model") then
		return
	end

	local billboard = model:FindFirstChild("EnemyStatusBillboard")
	if billboard and billboard:IsA("BillboardGui") then
		local roleBadge = billboard:FindFirstChild("PortraitRoleBadge")
		if roleBadge then
			roleBadge:Destroy()
		end

		-- Mantemos explicitamente somente os elementos criados pelo
		-- EnemyCombatFeedback: EnemyName, HealthTrack e HealthText.
		for _, child in ipairs(billboard:GetChildren()) do
			if child:IsA("TextLabel")
				and child.Name ~= "EnemyName"
				and child.Name ~= "HealthText"
			then
				if child.Name == "PortraitRoleBadge" or child:GetAttribute("EnemyRoleBadge") == true then
					child:Destroy()
				end
			end
		end
	end
end

local function cleanAll()
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end
	for _, tagged in ipairs(CollectionService:GetTagged("CombatTarget")) do
		local model = tagged:IsA("Model") and tagged or tagged:FindFirstAncestorOfClass("Model")
		cleanModel(model)
	end
end

CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(function(instance)
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end
	task.spawn(function()
		-- EnemyCombatFeedback pode criar o Billboard alguns frames depois da tag.
		for _ = 1, 12 do
			if not instance.Parent then
				return
			end
			local model = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChild("EnemyStatusBillboard") then
				cleanModel(model)
				return
			end
			task.wait(0.05)
		end
	end)
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	task.defer(cleanAll)
end)

RunService.Heartbeat:Connect(function(dt)
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end
	elapsed += dt
	if elapsed >= UPDATE_INTERVAL then
		elapsed = 0
		cleanAll()
	end
end)

player:SetAttribute("DungeonPortraitEnemyReadabilityControllerLoaded", true)
player:SetAttribute("DungeonPortraitEnemyReadabilityReady", true)
player:SetAttribute("DungeonPortraitEnemyReadabilityVersion", VERSION)
player:SetAttribute("DungeonPortraitEnemyReadabilityPolicy", "NameAndHealthOnly")
task.defer(cleanAll)
