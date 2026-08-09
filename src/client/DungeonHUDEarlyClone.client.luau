--[[
	Infinity Islands - DungeonHUDEarlyClone

	Problem:
	DungeonArtHUDController starts from StarterPlayerScripts and waits for
	PlayerGui.DungeonHUD. With CharacterAutoLoads=false, the authored StarterGui
	can be copied after that controller's old timeout.

	Fix:
	clone ONLY the designer-authored DungeonHUD from StarterGui into PlayerGui
	as soon as PlayerScripts starts. No HUD is drawn by code.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeHud =
	playerGui:FindFirstChild("DungeonHUD")

local function authoredSource()
	local source =
		StarterGui:FindFirstChild("DungeonHUD")

	if source and source:IsA("ScreenGui") then
		return source
	end

	return nil
end

local function ensureDungeonHUD()
	if activeHud
		and activeHud.Parent == playerGui
		and activeHud:IsA("ScreenGui")
	then
		activeHud.Enabled = true
		activeHud.ResetOnSpawn = false
		return activeHud
	end

	local existing =
		playerGui:FindFirstChild("DungeonHUD")

	if existing and existing:IsA("ScreenGui") then
		activeHud = existing
		activeHud.Enabled = true
		activeHud.ResetOnSpawn = false
		return activeHud
	end

	local source = authoredSource()

	if not source then
		return nil
	end

	local clone = source:Clone()
	clone.Name = "DungeonHUD"
	clone.Enabled = true
	clone.ResetOnSpawn = false
	clone:SetAttribute(
		"EarlyRuntimeClone",
		true
	)
	clone.Parent = playerGui

	activeHud = clone

	player:SetAttribute(
		"DungeonHUDEarlyCloneReady",
		true
	)

	return clone
end

-- Usually resolves in the first frame.
ensureDungeonHUD()

-- If StarterGui is authored/synchronized a little later, retry until found.
task.spawn(function()
	local startedAt = os.clock()

	while not (
		activeHud
		and activeHud.Parent == playerGui
	) do
		ensureDungeonHUD()

		if os.clock() - startedAt > 60 then
			player:SetAttribute(
				"DungeonHUDEarlyCloneReady",
				false
			)
			player:SetAttribute(
				"DungeonHUDEarlyCloneFailure",
				"DungeonHUDNotFoundInStarterGui"
			)
			return
		end

		task.wait(0.10)
	end
end)

-- Prevent a second automatic StarterGui copy from creating two DungeonHUDs.
playerGui.ChildAdded:Connect(function(child)
	if child.Name ~= "DungeonHUD"
		or not child:IsA("ScreenGui")
	then
		return
	end

	if not activeHud
		or not activeHud.Parent
	then
		activeHud = child
		activeHud.Enabled = true
		activeHud.ResetOnSpawn = false
		return
	end

	if child ~= activeHud then
		task.defer(function()
			if child.Parent == playerGui
				and activeHud
				and activeHud.Parent == playerGui
			then
				child:Destroy()
			end
		end)
	end
end)
