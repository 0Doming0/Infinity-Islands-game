local GroundSlam = require(script.Parent.Abilities.GroundSlam)

local AbilityRegistry = {}
local DEFINITIONS = {
	GroundSlam = GroundSlam,
}

local function configuredNames(model)
	local names = {}
	local folder = model:FindFirstChild("Abilities")
	if folder and folder:IsA("Folder") then
		for _, child in ipairs(folder:GetChildren()) do
			if
				(child:IsA("BoolValue") and child.Value)
				or child:IsA("Folder")
				or child:IsA("Configuration")
				or child:IsA("StringValue")
			then
				table.insert(names, child:IsA("StringValue") and child.Value or child.Name)
			end
		end
	end
	local encoded = model:GetAttribute("Abilities")
	if typeof(encoded) == "string" then
		for name in string.gmatch(encoded, "[^,%s]+") do
			table.insert(names, name)
		end
	end
	if model:GetAttribute("HasGroundSlam") == true then
		table.insert(names, "GroundSlam")
	end
	return names
end

function AbilityRegistry.Validate(model)
	local unknown = {}
	for _, name in ipairs(configuredNames(model)) do
		if not DEFINITIONS[name] then
			table.insert(unknown, name)
		end
	end
	return #unknown == 0, unknown
end

function AbilityRegistry.TryUse(state, config, targetHumanoid, targetRoot, distance, now)
	state.AbilityCooldowns = state.AbilityCooldowns or {}
	for _, name in ipairs(configuredNames(state.Model)) do
		local ability = DEFINITIONS[name]
		if ability and now >= (state.AbilityCooldowns[name] or 0) then
			local context = {
				Model = state.Model,
				Humanoid = state.Humanoid,
				Root = state.Root,
				Config = config,
				TargetHumanoid = targetHumanoid,
				TargetRoot = targetRoot,
				Distance = distance,
			}
			if not ability.CanUse or ability.CanUse(context) then
				local duration = ability.Use(context) or 0
				state.State = "Ability"
				state.ActionLockedUntil = now + duration
				local cooldown = math.max(
					0.25,
					tonumber(state.Model:GetAttribute(name .. "Cooldown")) or 8
				)
				state.AbilityCooldowns[name] = now + cooldown
				state.NextAttackAt = math.max(state.NextAttackAt or 0, now + duration)
				return true
			end
		end
	end
	return false
end

return table.freeze(AbilityRegistry)
