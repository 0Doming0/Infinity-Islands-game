--[[
    Infinity Islands — Rebuild Part 16
    Roblox Studio beginner-guide bootstrap.

    This script is intentionally Studio-only.
    Published servers return immediately and keep the normal production flow.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
    return
end

workspace:SetAttribute("DungeonStudioBeginnerGuideEnabled", true)
workspace:SetAttribute("DungeonStudioBeginnerGuidePolicy", "ForceOnStudioStartV1")
workspace:SetAttribute("DungeonGuidedIntroCompleting", false)

local function forceBeginnerGuide(player)
    if not player or player.Parent ~= Players then
        return
    end

    -- Studio is a deterministic test environment. Persistent tutorial state
    -- must never prevent the beginner guide from appearing.
    player:SetAttribute("DungeonStudioForceBeginnerGuide", true)
    player:SetAttribute("GuidedIntroActive", true)
    player:SetAttribute("GuidedIntroCompletionSaved", false)
    player:SetAttribute("GuidedIntroPresentationStage", "Mission")
    player:SetAttribute("DungeonStudioBeginnerGuideStartedAt", workspace:GetServerTimeNow())
end

local function bindPlayer(player)
    forceBeginnerGuide(player)

    player.CharacterAdded:Connect(function()
        -- Runtime/player-data initialization may finish after PlayerAdded.
        -- Reassert on the next scheduler step so Studio tests always begin
        -- with the guide active.
        task.defer(function()
            forceBeginnerGuide(player)
        end)
    end)

    task.delay(1.0, function()
        forceBeginnerGuide(player)
    end)
end

Players.PlayerAdded:Connect(bindPlayer)

for _, player in ipairs(Players:GetPlayers()) do
    bindPlayer(player)
end
