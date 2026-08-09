--[[
    Infinity Islands — Rebuild Part 17
    Studio remote bootstrap.

    Problem fixed:
    some client UI scripts wait for ReplicatedStorage.MonetizationRequest
    before MonetizationService.Start() has created it.

    In Studio we create the remote contract immediately.
    MonetizationService.ensureRemote() later finds these same instances
    and reuses them instead of replacing them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
    return
end

local function ensureRemote(className, name)
    local existing = ReplicatedStorage:FindFirstChild(name)

    if existing and existing.ClassName ~= className then
        warn(string.format(
            "[StudioRemoteBootstrap] %s existed as %s; replacing with %s.",
            name,
            existing.ClassName,
            className
        ))
        existing:Destroy()
        existing = nil
    end

    if not existing then
        existing = Instance.new(className)
        existing.Name = name
        existing:SetAttribute("CreatedByStudioRemoteBootstrap", true)
        existing.Parent = ReplicatedStorage
    end

    return existing
end

ensureRemote("RemoteEvent", "MonetizationEvent")
ensureRemote("RemoteFunction", "MonetizationRequest")

workspace:SetAttribute("DungeonStudioRemoteBootstrapReady", true)
workspace:SetAttribute("DungeonStudioMonetizationRemoteReady", true)
workspace:SetAttribute("DungeonStudioRemoteBootstrapVersion", "StudioRemoteContractV1")
