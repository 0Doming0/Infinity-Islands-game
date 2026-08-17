-- Protecao autoritativa enquanto uma escolha de melhoria esta aberta.
-- Cada sistema usa uma chave propria, para uma tela nao remover a protecao da
-- outra caso duas recompensas cheguem muito proximas.

local Players = game:GetService("Players")

local Service = {}

local FORCE_FIELD_NAME = "DungeonUpgradeChoiceProtection"
local sourcesByPlayer = setmetatable({}, { __mode = "k" })
local characterConnections = setmetatable({}, { __mode = "k" })
local timedTokens = setmetatable({}, { __mode = "k" })

local function sourceCount(player)
	local sources = sourcesByPlayer[player]
	local count = 0
	if sources then
		for _ in pairs(sources) do
			count += 1
		end
	end
	return count
end

local function ensureForceField(player, character)
	if not character or sourceCount(player) <= 0 then
		return
	end
	local field = character:FindFirstChild(FORCE_FIELD_NAME)
	if not field then
		field = Instance.new("ForceField")
		field.Name = FORCE_FIELD_NAME
		field.Visible = false
		field.Parent = character
	end
end

local function removeForceField(player)
	local character = player.Character
	local field = character and character:FindFirstChild(FORCE_FIELD_NAME)
	if field and field:IsA("ForceField") then
		field:Destroy()
	end
end

local function publish(player)
	local count = sourceCount(player)
	player:SetAttribute("DungeonUpgradeProtectionActive", count > 0)
	player:SetAttribute("DungeonUpgradeProtectionCount", count)
	if count <= 0 then
		player:SetAttribute("DungeonUpgradeProtectionReason", nil)
		removeForceField(player)
	else
		ensureForceField(player, player.Character)
	end
end

local function bindCharacter(player)
	if characterConnections[player] then
		return
	end
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		ensureForceField(player, character)
	end)
end

function Service.Begin(player, source)
	if not player or player.Parent ~= Players then
		return false
	end
	local key = tostring(source or "Upgrade")
	local sources = sourcesByPlayer[player] or {}
	sourcesByPlayer[player] = sources
	sources[key] = true
	player:SetAttribute("DungeonUpgradeProtectionReason", key)
	bindCharacter(player)
	publish(player)
	return true
end

function Service.End(player, source)
	local sources = sourcesByPlayer[player]
	if not sources then
		return false
	end
	sources[tostring(source or "Upgrade")] = nil
	if next(sources) == nil then
		sourcesByPlayer[player] = nil
	end
	publish(player)
	return true
end

function Service.BeginTimed(player, source, duration)
	local key = tostring(source or "Upgrade")
	if not Service.Begin(player, key) then
		return false
	end
	local tokens = timedTokens[player] or {}
	timedTokens[player] = tokens
	tokens[key] = (tokens[key] or 0) + 1
	local token = tokens[key]
	task.delay(math.max(0.1, tonumber(duration) or 0.1), function()
		if timedTokens[player] and timedTokens[player][key] == token then
			Service.End(player, key)
		end
	end)
	return true
end

function Service.Clear(player)
	sourcesByPlayer[player] = nil
	timedTokens[player] = nil
	publish(player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
end

Players.PlayerRemoving:Connect(Service.Clear)

return Service
