-- Efeitos de controle autoritativos aplicados aos jogadores. O token impede
-- que uma task antiga restaure o movimento durante um efeito mais recente.

local Players = game:GetService("Players")

local PlayerStatusService = {}
local states = setmetatable({}, { __mode = "k" })

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function restore(player, state)
	if states[player] ~= state then
		return
	end
	states[player] = nil
	local character = state.Character
	local humanoid = state.Humanoid
	if character and character.Parent then
		character:SetAttribute("StatusFrozen", nil)
		if player:GetAttribute("IsDowned") ~= true then
			character:SetAttribute("MovementLocked", nil)
		end
	end
	if
		humanoid
		and humanoid.Parent
		and humanoid.Health > 0
		and player:GetAttribute("IsDowned") ~= true
	then
		humanoid.WalkSpeed = state.WalkSpeed
		humanoid.JumpPower = state.JumpPower
		humanoid.JumpHeight = state.JumpHeight
		humanoid.AutoRotate = state.AutoRotate
	end
end

function PlayerStatusService.Clear(player)
	local state = states[player]
	if state then
		restore(player, state)
	end
end

function PlayerStatusService.ApplyFreeze(player, duration, immunitySeconds)
	if not player or player.Parent ~= Players or player:GetAttribute("IsDowned") == true then
		return false
	end
	local now = serverTime()
	if now < (tonumber(player:GetAttribute("IceFreezeImmunityUntil")) or 0) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end

	PlayerStatusService.Clear(player)
	local state = {
		Character = character,
		Humanoid = humanoid,
		WalkSpeed = math.max(0, humanoid.WalkSpeed),
		JumpPower = math.max(0, humanoid.JumpPower),
		JumpHeight = math.max(0, humanoid.JumpHeight),
		AutoRotate = humanoid.AutoRotate,
	}
	states[player] = state
	local freezeDuration = math.clamp(tonumber(duration) or 1.25, 0.15, 3)
	local immunity = math.max(freezeDuration, tonumber(immunitySeconds) or 4)
	player:SetAttribute("IceFrozenUntil", now + freezeDuration)
	player:SetAttribute("IceFreezeImmunityUntil", now + immunity)
	character:SetAttribute("StatusFrozen", true)
	character:SetAttribute("MovementLocked", true)
	character:SetAttribute("Sprinting", nil)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)

	task.delay(freezeDuration, function()
		if states[player] == state then
			restore(player, state)
			if player.Parent == Players then
				player:SetAttribute("IceFrozenUntil", nil)
			end
		end
	end)
	task.delay(immunity, function()
		if
			player.Parent == Players
			and (tonumber(player:GetAttribute("IceFreezeImmunityUntil")) or 0) <= serverTime()
		then
			player:SetAttribute("IceFreezeImmunityUntil", nil)
		end
	end)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

return table.freeze(PlayerStatusService)
