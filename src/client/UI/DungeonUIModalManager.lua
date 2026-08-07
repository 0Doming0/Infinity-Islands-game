local DungeonUIModalManager = {}

local OWNER_ATTRIBUTE = "SkyDungeonExclusivePanel"

function DungeonUIModalManager.GetOwner(playerGui)
	return tostring(playerGui:GetAttribute(OWNER_ATTRIBUTE) or "")
end

function DungeonUIModalManager.Acquire(playerGui, owner)
	owner = tostring(owner or "")
	if owner == "" then
		return false
	end
	playerGui:SetAttribute(OWNER_ATTRIBUTE, owner)
	return true
end

function DungeonUIModalManager.Release(playerGui, owner)
	if DungeonUIModalManager.GetOwner(playerGui) ~= tostring(owner or "") then
		return false
	end
	playerGui:SetAttribute(OWNER_ATTRIBUTE, nil)
	return true
end

function DungeonUIModalManager.IsOpen(playerGui, owner)
	return DungeonUIModalManager.GetOwner(playerGui) == tostring(owner or "")
end

return table.freeze(DungeonUIModalManager)
