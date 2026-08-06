local CollectionService = game:GetService("CollectionService")

local ObjectiveGateService = {}

local GATE_NAME = "ObjectiveGateBarrier"
local LABEL_NAME = "ObjectiveGateLabel"

local function resolveIsland(context)
	return context and context.IslandModel
end

local function ensureGate(context)
	local exit = context and context.Exit
	local island = resolveIsland(context)
	if not exit or not exit:IsA("BasePart") or not island or not island.Parent then
		return nil
	end
	local gate = island:FindFirstChild(GATE_NAME)
	if gate and not gate:IsA("BasePart") then
		gate:Destroy()
		gate = nil
	end
	if not gate then
		gate = Instance.new("Part")
		gate.Name = GATE_NAME
		gate.Size = Vector3.new(18, 12, 2)
		gate.Anchored = true
		gate.CanTouch = false
		gate.CastShadow = false
		gate.Material = Enum.Material.ForceField
		gate.Color = Color3.fromRGB(115, 92, 255)
		gate.Parent = island
		CollectionService:AddTag(gate, "DungeonObjectiveGate")
	end
	gate.CFrame = exit.CFrame * CFrame.new(0, gate.Size.Y / 2, 0)
	gate:SetAttribute("GlobalIslandIndex", context.GlobalIslandIndex)
	gate:SetAttribute("ObjectiveGate", true)

	local label = gate:FindFirstChild(LABEL_NAME)
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
	return gate
end

function ObjectiveGateService.Apply(context, locked, reason)
	local gate = ensureGate(context)
	if not gate then
		return false, "GateContextInvalid"
	end
	locked = locked == true
	gate.CanCollide = locked
	gate.CanQuery = locked
	gate.Transparency = locked and 0.22 or 1
	gate:SetAttribute("Locked", locked)
	gate:SetAttribute("LockReason", locked and tostring(reason or "ObjectiveActive") or nil)
	local label = gate:FindFirstChild(LABEL_NAME)
	if label and label:IsA("BillboardGui") then
		label.Enabled = locked
	end
	if context.Exit and context.Exit.Parent then
		context.Exit:SetAttribute("ObjectiveLocked", locked)
		context.Exit:SetAttribute("ExitLocked", locked)
		context.Exit:SetAttribute("LockReason", locked and tostring(reason or "ObjectiveActive") or nil)
	end
	if context.IslandModel and context.IslandModel.Parent then
		context.IslandModel:SetAttribute("ObjectiveExitLocked", locked)
	end
	return true, gate
end

function ObjectiveGateService.Destroy(context)
	local island = resolveIsland(context)
	local gate = island and island:FindFirstChild(GATE_NAME)
	if gate then
		gate:Destroy()
	end
end

return ObjectiveGateService
