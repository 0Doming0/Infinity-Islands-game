--[[
	Infinity Islands - Task 12
	CombatGateService V1

	Physical route gate for the simplified Combat MVP.

	IMPORTANT:
	This service creates gameplay Parts only.
	It NEVER creates BillboardGui/TextLabel/ScreenGui or any HUD visual.

	The authored HUD/minimap owns presentation.
]]

local CollectionService = game:GetService("CollectionService")

local CombatGateService = {}

local GATE_PREFIX = "CombatGateBarrier"

local function resolveIsland(context)
	return context and context.IslandModel
end

local function addUnique(
	result,
	seen,
	marker
)
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

	addUnique(
		result,
		seen,
		context and context.Exit
	)

	local island = resolveIsland(context)

	local root =
		context and context.GameplayMarkers
			or (
				island
					and island:FindFirstChild(
						"GameplayMarkers"
					)
			)

	local folder =
		context and context.Exits
			or (
				root
					and root:FindFirstChild(
						"Exits"
					)
			)

	if folder
		and folder:IsA("Folder")
	then
		for _, child in ipairs(
			folder:GetChildren()
		) do
			addUnique(
				result,
				seen,
				child
			)
		end
	end

	table.sort(
		result,
		function(left, right)
			local leftIndex =
				tonumber(
					left:GetAttribute(
						"ConnectionIndex"
					)
				)
					or tonumber(
						left:GetAttribute(
							"MarkerIndex"
						)
					)
					or 1

			local rightIndex =
				tonumber(
					right:GetAttribute(
						"ConnectionIndex"
					)
				)
					or tonumber(
						right:GetAttribute(
							"MarkerIndex"
						)
					)
					or 1

			if leftIndex == rightIndex then
				return left.Name < right.Name
			end

			return leftIndex < rightIndex
		end
	)

	return result
end

local function gateName(index)
	return index == 1
		and GATE_PREFIX
		or string.format(
			"%s_%02d",
			GATE_PREFIX,
			index
		)
end

local function ensureGate(
	context,
	exitMarker,
	index
)
	local island =
		resolveIsland(context)

	if not exitMarker
		or not island
		or not island.Parent
	then
		return nil
	end

	local name =
		gateName(index)

	local gate =
		island:FindFirstChild(name)

	if gate
		and not gate:IsA("BasePart")
	then
		gate:Destroy()
		gate = nil
	end

	if not gate then
		gate = Instance.new("Part")
		gate.Name = name
		gate.Size = Vector3.new(18, 12, 2)
		gate.Anchored = true
		gate.CanTouch = false
		gate.CastShadow = false
		gate.Material = Enum.Material.ForceField
		gate.Color = Color3.fromRGB(115, 92, 255)
		gate.Parent = island

		CollectionService:AddTag(
			gate,
			"DungeonCombatGate"
		)
	end

	gate.CFrame =
		exitMarker.CFrame
			* CFrame.new(
				0,
				gate.Size.Y / 2,
				0
			)

	gate:SetAttribute(
		"GlobalIslandIndex",
		context.GlobalIslandIndex
	)
	gate:SetAttribute(
		"CombatGate",
		true
	)
	gate:SetAttribute(
		"GateIndex",
		index
	)
	gate:SetAttribute(
		"ExitMarkerName",
		exitMarker.Name
	)
	gate:SetAttribute(
		"ConnectionDirectionId",
		exitMarker:GetAttribute(
			"ConnectionDirectionId"
		)
	)
	gate:SetAttribute(
		"ConnectionTargetKey",
		exitMarker:GetAttribute(
			"ConnectionTargetKey"
		)
	)

	return gate
end

local function removeStaleGates(
	island,
	expectedCount
)
	if not island then
		return
	end

	for _, child in ipairs(
		island:GetChildren()
	) do
		if child:IsA("BasePart")
			and (
				child.Name == GATE_PREFIX
					or string.match(
						child.Name,
						"^"
							.. GATE_PREFIX
							.. "_%d+$"
					)
			)
		then
			local index =
				child.Name == GATE_PREFIX
					and 1
					or tonumber(
						string.match(
							child.Name,
							"_(%d+)$"
						)
					)

			if not index
				or index > expectedCount
			then
				child:Destroy()
			end
		end
	end
end

function CombatGateService.Apply(
	context,
	locked,
	reason
)
	local island =
		resolveIsland(context)

	if not island
		or not island.Parent
	then
		return false,
			"GateContextInvalid"
	end

	local exits =
		collectExitMarkers(context)

	if #exits == 0 then
		return false,
			"ExitMarkersMissing"
	end

	locked = locked == true

	removeStaleGates(
		island,
		#exits
	)

	local gates = {}

	for index, exitMarker in ipairs(exits) do
		local gate =
			ensureGate(
				context,
				exitMarker,
				index
			)

		if not gate then
			return false,
				"GateCreationFailed"
		end

		gate.CanCollide = locked
		gate.CanQuery = locked
		gate.Transparency =
			locked and 0.28 or 1

		gate:SetAttribute(
			"Locked",
			locked
		)
		gate:SetAttribute(
			"LockReason",
			locked
				and tostring(
					reason
						or "CombatActive"
				)
				or nil
		)

		exitMarker:SetAttribute(
			"ObjectiveLocked",
			false
		)
		exitMarker:SetAttribute(
			"CombatLocked",
			locked
		)
		exitMarker:SetAttribute(
			"ExitLocked",
			locked
		)
		exitMarker:SetAttribute(
			"LockReason",
			locked
				and tostring(
					reason
						or "CombatActive"
				)
				or nil
		)

		gates[index] = gate
	end

	local root =
		context.GameplayMarkers
			or island:FindFirstChild(
				"GameplayMarkers"
			)

	if root then
		root:SetAttribute(
			"CombatGateCount",
			#gates
		)
		root:SetAttribute(
			"LockedExitCount",
			locked and #gates or 0
		)
		root:SetAttribute(
			"AllRouteExitsLocked",
			locked
		)
	end

	island:SetAttribute(
		"CombatExitLocked",
		locked
	)
	island:SetAttribute(
		"CombatGateCount",
		#gates
	)
	island:SetAttribute(
		"LockedRouteExitCount",
		locked and #gates or 0
	)
	island:SetAttribute(
		"CombatGateVersion",
		"CombatGateV1"
	)

	return true,
		gates[1],
		gates
end

function CombatGateService.Destroy(context)
	local island =
		resolveIsland(context)

	if not island then
		return
	end

	for _, child in ipairs(
		island:GetChildren()
	) do
		if child:IsA("BasePart")
			and (
				child.Name == GATE_PREFIX
					or string.match(
						child.Name,
						"^"
							.. GATE_PREFIX
							.. "_%d+$"
					)
			)
		then
			child:Destroy()
		end
	end

	for _, exitMarker in ipairs(
		collectExitMarkers(context)
	) do
		exitMarker:SetAttribute(
			"CombatLocked",
			false
		)
		exitMarker:SetAttribute(
			"ExitLocked",
			false
		)
		exitMarker:SetAttribute(
			"LockReason",
			nil
		)
	end
end

function CombatGateService.GetExitMarkers(
	context
)
	return collectExitMarkers(context)
end

return CombatGateService
