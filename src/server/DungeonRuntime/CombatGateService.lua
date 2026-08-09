--[[
	Infinity Islands - Free Route Gate Compatibility V2

	MVP rule:
	RecommendedLevel is informational only.
	There are no physical progression barriers.

	This module keeps the old API so callers do not break, but Apply()
	always leaves exits traversable and removes stale CombatGateBarrier parts.
]]

local CollectionService = game:GetService("CollectionService")

local CombatGateService = {}

local GATE_PREFIX = "CombatGateBarrier"

local function resolveIsland(context)
	return context and context.IslandModel
end

local function addUnique(result, seen, marker)
	if marker
		and marker:IsA("BasePart")
		and marker.Parent
		and not seen[marker]
	then
		seen[marker] = true
		table.insert(result, marker)
	end
end

local function collectExitMarkers(context)
	local result = {}
	local seen = {}

	addUnique(result, seen, context and context.Exit)

	local island = resolveIsland(context)

	local root =
		context and context.GameplayMarkers
		or (
			island
			and island:FindFirstChild("GameplayMarkers")
		)

	local folder =
		context and context.Exits
		or (
			root
			and root:FindFirstChild("Exits")
		)

	if folder and folder:IsA("Folder") then
		for _, child in ipairs(folder:GetChildren()) do
			addUnique(result, seen, child)
		end
	end

	return result
end

local function destroyBarrierParts(island)
	if not island then
		return
	end

	for _, child in ipairs(island:GetChildren()) do
		if child:IsA("BasePart")
			and (
				child.Name == GATE_PREFIX
				or string.match(
					child.Name,
					"^" .. GATE_PREFIX .. "_%d+$"
				)
				or CollectionService:HasTag(
					child,
					"DungeonCombatGate"
				)
			)
		then
			child:Destroy()
		end
	end
end

local function publishUnlocked(context)
	local island = resolveIsland(context)

	if not island then
		return false, "GateContextInvalid"
	end

	destroyBarrierParts(island)

	local exits = collectExitMarkers(context)

	for _, exitMarker in ipairs(exits) do
		exitMarker:SetAttribute("ObjectiveLocked", false)
		exitMarker:SetAttribute("CombatLocked", false)
		exitMarker:SetAttribute("ExitLocked", false)
		exitMarker:SetAttribute("LockReason", nil)
		exitMarker:SetAttribute(
			"RecommendedLevelOnly",
			true
		)
	end

	local root =
		context.GameplayMarkers
		or island:FindFirstChild("GameplayMarkers")

	if root then
		root:SetAttribute("CombatGateCount", 0)
		root:SetAttribute("LockedExitCount", 0)
		root:SetAttribute("AllRouteExitsLocked", false)
	end

	island:SetAttribute("CombatExitLocked", false)
	island:SetAttribute("CombatGateCount", 0)
	island:SetAttribute("LockedRouteExitCount", 0)
	island:SetAttribute(
		"CombatGateVersion",
		"FreeRouteNoPhysicalGateV2"
	)
	island:SetAttribute(
		"RecommendedLevelIsHardGate",
		false
	)

	return true, nil, {}
end

function CombatGateService.Apply(context, _locked, _reason)
	return publishUnlocked(context)
end

function CombatGateService.Destroy(context)
	publishUnlocked(context)
end

function CombatGateService.GetExitMarkers(context)
	return collectExitMarkers(context)
end

return CombatGateService
