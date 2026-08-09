-- GuidedIntro Lobby Redirect Until Completion.
--
-- GuidedIntro is system-only and uses Phase01 as its gameplay content.
-- The canonical persistent completion state is TutorialCompleted.
--
-- Fail-safe: if persistent progress cannot be read, the player remains in the
-- Lobby instead of risking an infinite tutorial redirect loop.

local Players = game:GetService("Players")

local ProgressService = require(script.Parent.LobbyGuidedIntroProgressService)
local TeleportCoordinator = require(script.Parent.TeleportCoordinator)

local GuidedIntroRedirectService = {}

local evaluated = setmetatable({}, { __mode = "k" })
local started = false

local function publishState(player, completed)
	player:SetAttribute("GuidedIntroCompleted", completed == true)
	player:SetAttribute("GuidedIntroRequired", completed ~= true)
end

function GuidedIntroRedirectService.Evaluate(player)
	if not player or player.Parent ~= Players then
		return false, "PlayerUnavailable"
	end
	if evaluated[player] then
		return false, "AlreadyEvaluatedThisLobbyEntry"
	end
	evaluated[player] = true

	local completed, progressReason = ProgressService.IsCompleted(player)
	if completed == nil then
		player:SetAttribute("GuidedIntroRedirecting", false)
		player:SetAttribute("GuidedIntroRedirectBlockedReason", "ProgressUnavailable")
		player:SetAttribute("GuidedIntroRedirectError", tostring(progressReason))
		return false, "ProgressUnavailable"
	end

	publishState(player, completed)

	if completed then
		player:SetAttribute("GuidedIntroRedirecting", false)
		player:SetAttribute("GuidedIntroRedirectBlockedReason", nil)
		player:SetAttribute("LobbyInteractionDisabledByGuidedIntro", false)
		return true, "AlreadyCompleted"
	end

	if player:GetAttribute("PlayerDataTemporary") == true then
		player:SetAttribute("GuidedIntroRedirecting", false)
		player:SetAttribute("GuidedIntroRedirectBlockedReason", "PlayerDataTemporary")
		player:SetAttribute("LobbyInteractionDisabledByGuidedIntro", false)
		warn(
			"[GuidedIntro] Redirect blocked for "
				.. player.Name
				.. ": temporary data cannot persist completion."
		)
		return false, "PlayerDataTemporary"
	end

	player:SetAttribute("GuidedIntroRedirectBlockedReason", nil)
	player:SetAttribute("GuidedIntroRedirectError", nil)
	player:SetAttribute("GuidedIntroRedirecting", true)
	player:SetAttribute("LobbyInteractionDisabledByGuidedIntro", true)

	task.defer(function()
		if player.Parent ~= Players
			or player:GetAttribute("GuidedIntroCompleted") == true
		then
			return
		end

		local success, message = TeleportCoordinator.ScheduleGuidedIntro(player)
		if not success and player.Parent == Players then
			player:SetAttribute("GuidedIntroRedirecting", false)
			player:SetAttribute("GuidedIntroRedirectError", tostring(message))
			player:SetAttribute("LobbyInteractionDisabledByGuidedIntro", false)
		end
	end)

	return true, "RedirectScheduled"
end

function GuidedIntroRedirectService.Start()
	if started then
		return true
	end
	started = true

	workspace:SetAttribute("LobbyGuidedIntroRedirectReady", true)
	workspace:SetAttribute(
		"LobbyGuidedIntroPolicy",
		"RedirectNewPlayersUsingCanonicalTutorialCompletionV2"
	)
	workspace:SetAttribute("LobbyGuidedIntroPhaseId", "GuidedIntro")
	workspace:SetAttribute("LobbyGuidedIntroContentPhaseId", "Phase01")
	return true
end

return GuidedIntroRedirectService
