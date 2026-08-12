-- Training Dummy respawn controller.
-- Dummies stay anchored and immovable when hit (NoKnockback attribute).
-- When health reaches 0, parts unanchor and fall. After a delay, the dummy resets.

local DUMMY_NAME = "Training Dummy"
local RESPAWN_DELAY = 5 -- seconds before the dummy resets

-- Store original part data for each dummy so we can restore it
local dummyData = setmetatable({}, { __mode = "k" })

local function capturePartData(dummy)
    local parts = {}
    for _, child in ipairs(dummy:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(parts, {
                Part = child,
                CFrame = child.CFrame,
                Size = child.Size,
            })
        end
    end
    return parts
end

local function resetDummy(dummy, data)
    if not dummy or not dummy.Parent then
        return
    end

    -- Re-anchor and restore all parts to their original positions
    for _, partData in ipairs(data.Parts) do
        local part = partData.Part
        if part and part.Parent then
            part.Anchored = true
            part.CFrame = partData.CFrame
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end

    -- Reset the Humanoid health
    local humanoid = dummy:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = humanoid.MaxHealth
    end

    dummy:SetAttribute("DummyDown", nil)
    data.IsDown = false
end

local function onDummyDied(dummy, data)
    if data.IsDown then
        return
    end
    data.IsDown = true
    dummy:SetAttribute("DummyDown", true)

    -- Unanchor all parts so they fall apart visually
    for _, partData in ipairs(data.Parts) do
        local part = partData.Part
        if part and part.Parent then
            part.Anchored = false
        end
    end

    -- Schedule the reset
    task.delay(RESPAWN_DELAY, function()
        resetDummy(dummy, data)
    end)
end

local function setupDummy(dummy)
    if dummyData[dummy] then
        return -- already set up
    end

    local humanoid = dummy:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    -- Ensure NoKnockback is set so the knockback system doesn't unanchor parts
    dummy:SetAttribute("NoKnockback", true)
    humanoid.BreakJointsOnDeath = false

    local data = {
        Parts = capturePartData(dummy),
        IsDown = false,
    }
    dummyData[dummy] = data

    humanoid.Died:Connect(function()
        onDummyDied(dummy, data)
    end)
end

local function scanForDummies(parent)
    for _, descendant in ipairs(parent:GetDescendants()) do
        if descendant:IsA("Model") and descendant.Name == DUMMY_NAME then
            setupDummy(descendant)
        end
    end
end

-- Set up existing dummies in the workspace
scanForDummies(workspace)

-- Watch for new dummies added at runtime (e.g. when the template is cloned)
workspace.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("Model") and descendant.Name == DUMMY_NAME then
        -- Small delay to ensure the model is fully populated
        task.wait(0.1)
        setupDummy(descendant)
    end
end)
