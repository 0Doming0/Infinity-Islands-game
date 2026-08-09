-- First-session GuidedIntro lifecycle.
--
-- A new player is sent from the Lobby to a solo reserved Phase01 session with
-- TeleportData.GuidedIntro = true. The normal Dungeon runtime remains the
-- authority for generation, combat and rewards.
--
-- This bridge only:
-- 1) exposes GuidedIntroActive to the contextual client presentation;
-- 2) persists the existing canonical TutorialCompleted flag after the first
--    Reward Island has been committed;
-- 3) returns the player to the Lobby, where future joins no longer redirect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local PlaceConfig = require(ReplicatedStorage.Shared.Configs.PlaceConfig)
local PlayerDataService = require(
	script.Parent.BlockParkour.PlayerDataService_SkyDungeon_V10
)

local SAVE_ATTEMPTS = 3
local SAVE_RETRY_SECONDS = 1
local RETURN_DELAY_SECONDS = 1.25

local guidedUserIds = {}
local completionStarted = {}

local function isGuidedJoin(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	return type(teleportData) == "table"
		and teleportData.GuidedIntro == true
		and tostring(teleportData.PhaseId or "") == "Phase01"
end

local function returnToLobby(player)
	if not player or player.Parent ~= Players then
		return
	end

	if RunService:IsStudio() then
		player:SetAttribute("GuidedIntroStudioReturnReady", true)
		return
	end

	if PlaceConfig.LobbyPlaceId <= 0 then
		player:SetAttribute(
			"GuidedIntroReturnError",
			"LobbyPlaceIdNotConfigured"
		)
		return
	end

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		ReturnVersion = 1,
		ReturnReason = "GuidedIntroCompleted",
		PhaseId = "Phase01",
		GuidedIntroCompleted = true,
	})

	local ok, errorMessage = pcall(
		TeleportService.TeleportAsync,
		TeleportService,
		PlaceConfig.LobbyPlaceId,
		{ player },
		options
	)

	if not ok and player.Parent == Players then
		player:SetAttribute(
			"GuidedIntroReturnError",
			tostring(errorMessage)
		)
	end
end

local function persistCompletion(player)
	if not player or player.Parent ~= Players then
		return false, "PlayerUnavailable"
	end

	PlayerDataService.Load(player)

	if not PlayerDataService.CanSave(player) then
		return false, "PlayerDataNotSaveable"
	end

	PlayerDataService.SetTutorialProgress(player, 5, true)

	for attempt = 1, SAVE_ATTEMPTS do
		if PlayerDataService.Save(player, true) then
			return true
		end

		if attempt < SAVE_ATTEMPTS then
			task.wait(SAVE_RETRY_SECONDS * attempt)
		end
	end

	return false, "TutorialCompletionSaveFailed"
end

local function completePlayer(player)
	if not player
		or player.Parent ~= Players
		or not guidedUserIds[player.UserId]
		or completionStarted[player.UserId]
	then
		return
	end

	completionStarted[player.UserId] = true

	player:SetAttribute("GuidedIntroCompleting", true)
	workspace:SetAttribute("DungeonGuidedIntroCompleting", true)

	task.spawn(function()
		local saved, errorCode = persistCompletion(player)

		if player.Parent ~= Players then
			return
		end

		player:SetAttribute("GuidedIntroCompletionSaved", saved == true)
		player:SetAttribute("GuidedIntroCompleted", saved == true)
		player:SetAttribute(
			"GuidedIntroCompletionError",
			saved and nil or tostring(errorCode)
		)

		if not saved then
			player:SetAttribute("GuidedIntroCompleting", false)
			completionStarted[player.UserId] = nil
			workspace:SetAttribute("DungeonGuidedIntroCompleting", false)
			return
		end

		task.delay(RETURN_DELAY_SECONDS, function()
			if player.Parent == Players then
				player:SetAttribute("GuidedIntroActive", false)
				returnToLobby(player)
			end
		end)
	end)
end

local function checkRewardCommit()
	local committedRound = math.max(
		0,
		math.floor(
			tonumber(
				workspace:GetAttribute(
					"DungeonLastCommittedRewardRound"
				)
			) or 0
		)
	)

	if committedRound < 1 then
		return
	end

	for userId in pairs(guidedUserIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			completePlayer(player)
		end
	end
end

local function bindPlayer(player)
	if not isGuidedJoin(player) then
		return
	end

	guidedUserIds[player.UserId] = true

	player:SetAttribute("GuidedIntroActive", true)
	player:SetAttribute("GuidedIntroCompleted", false)
	player:SetAttribute("GuidedIntroCompletionSaved", false)
	player:SetAttribute("GuidedIntroCompleting", false)
	player:SetAttribute("GuidedIntroVersion", 1)

	PlayerDataService.Load(player)

	local _, alreadyCompleted =
		PlayerDataService.GetTutorialProgress(player)

	if alreadyCompleted then
		player:SetAttribute("GuidedIntroCompletionSaved", true)
		player:SetAttribute("GuidedIntroCompleted", true)

		task.delay(0.5, function()
			if player.Parent == Players then
				player:SetAttribute("GuidedIntroActive", false)
				returnToLobby(player)
			end
		end)
		return
	end

	task.defer(checkRewardCommit)
end

Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	guidedUserIds[player.UserId] = nil
	completionStarted[player.UserId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(bindPlayer, player)
end

workspace:GetAttributeChangedSignal(
	"DungeonLastCommittedRewardRound"
):Connect(checkRewardCommit)

workspace:SetAttribute("DungeonGuidedIntroBridgeReady", true)
workspace:SetAttribute(
	"DungeonGuidedIntroCompletionPolicy",
	"FirstRewardCommitThenLobbyV1"
)
