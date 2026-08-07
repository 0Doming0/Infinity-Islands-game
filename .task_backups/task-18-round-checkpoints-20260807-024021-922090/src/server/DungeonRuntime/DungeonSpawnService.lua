local Players = game:GetService("Players")

local DungeonSpawnService = {}

local started = false
local options = {}
local checkpointContext
local boundPlayers = setmetatable({}, { __mode = "k" })
local characterTokens = setmetatable({}, { __mode = "k" })
local connections = {}

local DEFAULT_PROTECTION_SECONDS = 4
local ROOT_OFFSET = CFrame.new(0, 3, 0)

local function markerCFrame(context)
	if type(context) ~= "table" then
		return nil
	end
	local marker = context.SafeSpawn
	if typeof(marker) == "Instance" and marker:IsA("BasePart") and marker.Parent then
		return marker.CFrame
	end
	if typeof(marker) == "CFrame" then
		return marker
	end
	return nil
end

local function eligibleForManagedSpawn(player)
	if not player
		or player.Parent ~= Players
		or player:GetAttribute("DungeonSessionId") == nil
	then
		return false
	end
	-- O retorno gratuito na Reward Island recria o personagem enquanto o
	-- registro de vida ainda esta como Eliminated/Spectating. Esse estado
	-- especial precisa passar pelo posicionador para publicar RespawnState=Ready
	-- sem aguardar o timeout do DungeonPartyLifeService.
	if player:GetAttribute("DungeonRewardRespawning") == true then
		return true
	end
	return player:GetAttribute("DungeonEliminated") ~= true
		and player:GetAttribute("DungeonSpectating") ~= true
end

local function ensureProtection(character, name, duration)
	local existing = character:FindFirstChild(name)
	if existing and existing:IsA("ForceField") then
		return existing
	end
	local forceField = Instance.new("ForceField")
	forceField.Name = name
	forceField.Visible = false
	forceField.Parent = character
	if duration then
		task.delay(duration, function()
			if forceField.Parent then
				forceField:Destroy()
			end
		end)
	end
	return forceField
end

local function holdCharacter(player, character)
	if not eligibleForManagedSpawn(player) then
		return nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or player.Character ~= character then
		return nil
	end
	local token = (characterTokens[player] or 0) + 1
	characterTokens[player] = token
	character:SetAttribute("DungeonSpawnManaged", true)
	character:SetAttribute("MovementLocked", true)
	player:SetAttribute("RespawnState", "Positioning")
	player:SetAttribute("PlayerLifecycleState", "InitialSpawning")
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid:UnequipTools()
	humanoid:Move(Vector3.zero)
	ensureProtection(character, "DungeonSpawnLoadingProtection")
	return humanoid, root, token
end

local function restoreMovement(character, humanoid, root)
	character:SetAttribute("MovementLocked", nil)
	root.Anchored = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	if humanoid.WalkSpeed <= 0 then
		humanoid.WalkSpeed = 16
	end
	if humanoid.UseJumpPower then
		if humanoid.JumpPower <= 0 then
			humanoid.JumpPower = 50
		end
	elseif humanoid.JumpHeight <= 0 then
		humanoid.JumpHeight = 7.2
	end
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end)
end

local function positionCharacter(player, character, context, reason)
	if not eligibleForManagedSpawn(player) or player.Character ~= character then
		return false, "PlayerNotEligible"
	end
	local spawnCFrame = markerCFrame(context)
	if not spawnCFrame then
		return false, "SafeSpawnUnavailable"
	end
	local humanoid, root, token = holdCharacter(player, character)
	if not humanoid or not root then
		return false, "CharacterIncomplete"
	end
	task.wait()
	if characterTokens[player] ~= token
		or player.Character ~= character
		or not eligibleForManagedSpawn(player)
	then
		return false, "SpawnSuperseded"
	end
	character:PivotTo(spawnCFrame * ROOT_OFFSET)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	restoreMovement(character, humanoid, root)
	local loadingProtection = character:FindFirstChild("DungeonSpawnLoadingProtection")
	if loadingProtection then
		loadingProtection:Destroy()
	end
	ensureProtection(
		character,
		"DungeonSpawnProtection",
		math.max(1, tonumber(options.ProtectionSeconds) or DEFAULT_PROTECTION_SECONDS)
	)
	player:SetAttribute("DungeonCheckpointIslandIndex", context.GlobalIslandIndex)
	player:SetAttribute("DungeonCheckpointRoundIndex", context.RoundIndex)
	player:SetAttribute("DungeonCheckpointNodeKey", context.Key)
	player:SetAttribute("DungeonLastSpawnReason", tostring(reason or "DungeonSpawn"))
	player:SetAttribute("DungeonLastSpawnAt", workspace:GetServerTimeNow())
	player:SetAttribute("InitialSpawnPositioned", true)
	player:SetAttribute("InitialStartState", "Playing")
	player:SetAttribute("RespawnState", "Ready")
	player:SetAttribute("PlayerLifecycleState", "Playing")
	return true
end

local function onCharacterAdded(player, character)
	if not eligibleForManagedSpawn(player) then
		return
	end
	local _, _, token = holdCharacter(player, character)
	if not token then
		return
	end
	if checkpointContext then
		task.spawn(positionCharacter, player, character, checkpointContext, "CharacterAdded")
	end
end

function DungeonSpawnService.Start(startOptions)
	if started then
		return
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	workspace:SetAttribute("DungeonSpawnServiceReady", true)
	workspace:SetAttribute("DungeonSpawnAuthority", "DungeonSpawnService")
	connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
		local connection = boundPlayers[player]
		if connection then
			connection:Disconnect()
		end
		boundPlayers[player] = nil
		characterTokens[player] = nil
	end)
end

function DungeonSpawnService.BindPlayer(player)
	if not started or not player or player.Parent ~= Players then
		return false
	end
	if boundPlayers[player] then
		return true
	end
	boundPlayers[player] = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	return true
end

function DungeonSpawnService.SetCheckpoint(context, reason, repositionPlayers)
	if not started or not markerCFrame(context) then
		return false, "InvalidCheckpoint"
	end
	checkpointContext = context
	workspace:SetAttribute("DungeonCheckpointIslandIndex", context.GlobalIslandIndex)
	workspace:SetAttribute("DungeonCheckpointRoundIndex", context.RoundIndex)
	workspace:SetAttribute("DungeonCheckpointNodeKey", context.Key)
	workspace:SetAttribute("DungeonCheckpointReason", tostring(reason or "CheckpointUpdated"))
	workspace:SetAttribute("DungeonCheckpointUpdatedAt", workspace:GetServerTimeNow())
	if repositionPlayers == true then
		for _, player in ipairs(Players:GetPlayers()) do
			if eligibleForManagedSpawn(player) and player.Character then
				task.spawn(positionCharacter, player, player.Character, context, reason or "Checkpoint")
			end
		end
	end
	return true
end

function DungeonSpawnService.PositionPlayer(player, reason)
	if not checkpointContext or not player or not player.Character then
		return false, "CheckpointOrCharacterUnavailable"
	end
	return positionCharacter(player, player.Character, checkpointContext, reason)
end

function DungeonSpawnService.GetCheckpoint()
	return checkpointContext
end

function DungeonSpawnService.GetSnapshot()
	return {
		Ready = started,
		GlobalIslandIndex = checkpointContext and checkpointContext.GlobalIslandIndex,
		RoundIndex = checkpointContext and checkpointContext.RoundIndex,
		NodeKey = checkpointContext and checkpointContext.Key,
	}
end

return DungeonSpawnService
