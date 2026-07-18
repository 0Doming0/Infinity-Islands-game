-- Regras cooperativas: sem regeneracao passiva e penalidade unica em qualquer morte.

local Players = game:GetService("Players")

local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
ScoreService.Start()

local function removeHealthRegeneration(instance)
	if instance.Name == "Health" and instance:IsA("BaseScript") then
		instance:Destroy()
	end
end

local function detectDeathCause(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and water:GetAttribute("SurfaceY")
	if root and typeof(surfaceY) == "number" and root.Position.Y <= surfaceY + 1 then
		return "Water"
	end
	return "CombatOrFall"
end

local function bindCharacter(player, character)
	player:SetAttribute("ShopOpen", false)
	for _, child in ipairs(character:GetChildren()) do
		removeHealthRegeneration(child)
	end
	character.ChildAdded:Connect(removeHealthRegeneration)
	character:SetAttribute("PassiveHealingDisabled", true)
	ScoreService.ResetRun(player)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	local processed = false
	humanoid.Died:Connect(function()
		if processed then
			return
		end
		processed = true
		ScoreService.HandleDeath(player, detectDeathCause(character))
	end)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then
		bindCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
