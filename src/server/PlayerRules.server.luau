-- Regras principais do jogador.
-- A regeneracao passiva padrao do Roblox permanece habilitada.

local Players = game:GetService("Players")

local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local RunLevelService = require(script.Parent.BlockParkour:WaitForChild("RunLevelService"))
local DownedService = require(script.Parent.MVPSystems:WaitForChild("DownedService"))
local GameplayAnalytics = require(script.Parent:WaitForChild("GameplayAnalyticsService"))

ScoreService.Start()
DownedService.Start()

local function detectDeathCause(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and water:GetAttribute("SurfaceY")
	if root and typeof(surfaceY) == "number" and root.Position.Y <= surfaceY + 1 then
		local waterBottom = water.Position.Y - water.Size.Y / 2
		if root.Position.Y < waterBottom - 10 then
			return "Void"
		end
		return "RisingWater"
	end
	if root and root.AssemblyLinearVelocity.Y < -35 then
		return "Fall"
	end
	return "Unknown"
end

local function bindCharacter(player, character)
	player:SetAttribute("ShopOpen", false)

	-- Regeneracao automatica volta a ser parte da experiencia normal.
	-- Nao destruimos mais o script "Health" inserido pelo Roblox no personagem.
	character:SetAttribute("PassiveHealingDisabled", false)
	player:SetAttribute("DungeonPassiveHealingEnabled", true)

	ScoreService.ResetRun(player)
	RunLevelService.Reset(player, character)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	-- O estado inconsciente usa ragdoll antes da morte real. As juntas precisam
	-- sobreviver caso o tempo de resgate termine e a vida finalmente chegue a zero.
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	local processed = false
	humanoid.Died:Connect(function()
		if processed then
			return
		end
		processed = true
		local cause = detectDeathCause(character)
		GameplayAnalytics.RecordDeath(player, character, cause)
		ScoreService.HandleDeath(player, cause)
		RunLevelService.Reset(player, nil)
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

Players.PlayerRemoving:Connect(RunLevelService.Remove)
