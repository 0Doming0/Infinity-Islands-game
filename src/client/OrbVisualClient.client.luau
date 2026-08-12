local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))

local function removeDuplicateVisuals(character)
	local equippedOrb =
		OrbConfig.NormalizeOrb(player:GetAttribute("EquippedOrb") or character:GetAttribute("EquippedOrb"))
	local orbDefinition = OrbConfig.GetOrb(equippedOrb)
	local expectedName = orbDefinition and (orbDefinition.AssetName or (equippedOrb .. "Orb")) or nil
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrbVisual") == true and (not expectedName or child.Name ~= expectedName) then
			child:Destroy()
		end
	end
end

local function observeCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:GetAttribute("OrbVisual") == true then
			task.defer(removeDuplicateVisuals, character)
		end
	end)
	removeDuplicateVisuals(character)
end

player:GetAttributeChangedSignal("EquippedOrb"):Connect(function()
	if player.Character then
		removeDuplicateVisuals(player.Character)
	end
end)

player.CharacterAdded:Connect(observeCharacter)
if player.Character then
	observeCharacter(player.Character)
end
