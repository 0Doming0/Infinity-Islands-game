local CollectionService = game:GetService("CollectionService")

local ObjectiveGateService = {}

local GATE_PREFIX = "ObjectiveGateBarrier"
local LABEL_NAME = "ObjectiveGateLabel"

local function resolveIsland(context)
	return context and context.IslandModel
end

local function addUnique(result, seen, marker)
	if marker and marker:IsA("BasePart") and marker.Parent and not seen[marker] then
		seen[marker] = true
		table.insert(result, marker)
	end
end

local function collectExitMarkers(context)
	local result = {}
	local seen = {}
	addUnique(result, seen, context and context.Exit)

	local island = resolveIsland(context)
	local root = context and context.GameplayMarkers
		or (island and island:FindFirstChild("GameplayMarkers"))
	local folder = context and context.Exits
		or (root and root:FindFirstChild("Exits"))
	if folder and folder:IsA("Folder") then
		for _, child in ipairs(folder:GetChildren()) do
			addUnique(result, seen, child)
		end
	end

	table.sort(result, function(left, right)
		local leftIndex = tonumber(left:GetAttribute("ConnectionIndex")) or tonumber(left:GetAttribute("MarkerIndex")) or 1
		local rightIndex = tonumber(right:GetAttribute("ConnectionIndex")) or tonumber(right:GetAttribute("MarkerIndex")) or 1
		if leftIndex == rightIndex then
			return left.Name < right.Name
		end
		return leftIndex < rightIndex
	end)
	return result
end

local function gateName(index)
	return index == 1 and GATE_PREFIX or string.format("%s_%02d", GATE_PREFIX, index)
end

local function ensureLabel(gate)
	local label = gate:FindFirstChild(LABEL_NAME)
	if label and not label:IsA("BillboardGui") then
		label:Destroy()
		label = nil
	end
	if not label then
		label = Instance.new("BillboardGui")
		label.Name = LABEL_NAME
		label.Size = UDim2.fromOffset(220, 46)
		label.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
		label.AlwaysOnTop = true
		label.MaxDistance = 80
		label.Parent = gate

		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(24, 20, 42)
		text.BackgroundTransparency = 0.18
		text.BorderSizePixel = 0
		text.TextColor3 = Color3.fromRGB(235, 229, 255)
		text.Font = Enum.Font.GothamBold
		text.TextSize = 14
		text.TextWrapped = true
		text.Text = "CONCLUA O OBJETIVO"
		text.Parent = label
		Instance.new("UICorner", text).CornerRadius = UDim.new(0, 8)
	end
	return label
end

local function ensureGate(context, exitMarker, index)
	local island = resolveIsland(context)
	if not exitMarker or not island or not island.Parent then
		return nil
	end
	local name = gateName(index)
	local gate = island:FindFirstChild(name)
	if gate and not gate:IsA("BasePart") then
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
		CollectionService:AddTag(gate, "DungeonObjectiveGate")
	end
	gate.CFrame = exitMarker.CFrame * CFrame.new(0, gate.Size.Y / 2, 0)
	gate:SetAttribute("GlobalIslandIndex", context.GlobalIslandIndex)
	gate:SetAttribute("ObjectiveGate", true)
	gate:SetAttribute("GateIndex", index)
	gate:SetAttribute("ExitMarkerName", exitMarker.Name)
	gate:SetAttribute("ConnectionDirectionId", exitMarker:GetAttribute("ConnectionDirectionId"))
	gate:SetAttribute("ConnectionTargetKey", exitMarker:GetAttribute("ConnectionTargetKey"))
	gate:SetAttribute("ConnectionBranchId", exitMarker:GetAttribute("ConnectionBranchId"))
	ensureLabel(gate)
	return gate
end

local function removeStaleGates(island, expectedCount)
	if not island then
		return
	end
	for _, child in ipairs(island:GetChildren()) do
		if child:IsA("BasePart")
			and (child.Name == GATE_PREFIX or string.match(child.Name, "^" .. GATE_PREFIX .. "_%d+$"))
		then
			local index = child.Name == GATE_PREFIX and 1
				or tonumber(string.match(child.Name, "_(%d+)$"))
			if not index or index > expectedCount then
				child:Destroy()
			end
		end
	end
end

function ObjectiveGateService.Apply(context, locked, reason)
	local island = resolveIsland(context)
	if not island or not island.Parent then
		return false, "GateContextInvalid"
	end
	local exits = collectExitMarkers(context)
	if #exits == 0 then
		return false, "ExitMarkersMissing"
	end

	locked = locked == true
	removeStaleGates(island, #exits)
	local gates = {}
	for index, exitMarker in ipairs(exits) do
		local gate = ensureGate(context, exitMarker, index)
		if not gate then
			return false, "GateCreationFailed"
		end
		gate.CanCollide = locked
		gate.CanQuery = locked
		gate.Transparency = locked and 0.22 or 1
		gate:SetAttribute("Locked", locked)
		gate:SetAttribute("LockReason", locked and tostring(reason or "ObjectiveActive") or nil)
		local label = gate:FindFirstChild(LABEL_NAME)
		if label and label:IsA("BillboardGui") then
			label.Enabled = locked
		end

		exitMarker:SetAttribute("ObjectiveLocked", locked)
		exitMarker:SetAttribute("ExitLocked", locked)
		exitMarker:SetAttribute("LockReason", locked and tostring(reason or "ObjectiveActive") or nil)
		gates[index] = gate
	end

	local root = context.GameplayMarkers or island:FindFirstChild("GameplayMarkers")
	if root then
		root:SetAttribute("ObjectiveGateCount", #gates)
		root:SetAttribute("LockedExitCount", locked and #gates or 0)
		root:SetAttribute("AllRouteExitsLocked", locked)
	end
	island:SetAttribute("ObjectiveExitLocked", locked)
	island:SetAttribute("ObjectiveGateCount", #gates)
	island:SetAttribute("LockedRouteExitCount", locked and #gates or 0)
	return true, gates[1], gates
end

function ObjectiveGateService.Destroy(context)
	local island = resolveIsland(context)
	if not island then
		return
	end
	for _, child in ipairs(island:GetChildren()) do
		if child:IsA("BasePart")
			and (child.Name == GATE_PREFIX or string.match(child.Name, "^" .. GATE_PREFIX .. "_%d+$"))
		then
			child:Destroy()
		end
	end
	local exits = collectExitMarkers(context)
	for _, exitMarker in ipairs(exits) do
		exitMarker:SetAttribute("ObjectiveLocked", false)
		exitMarker:SetAttribute("ExitLocked", false)
		exitMarker:SetAttribute("LockReason", nil)
	end
end

function ObjectiveGateService.GetExitMarkers(context)
	return collectExitMarkers(context)
end

return ObjectiveGateService
