-- Task 20 — GuidedIntro Lobby Redirect Until Completion.
--
-- GuidedIntro is system-only and separate from Phase01.
-- While GuidedIntroCompleted ~= true, each valid Lobby entry redirects the
-- player to a solo GuidedIntro session.
--
-- Fail-safe: temporary player data does not redirect because completion could
-- not be persisted safely, which could trap the player in a tutorial loop.

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.LobbyPlayerDataService)
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

	local data = PlayerDataService.Get(player) or PlayerDataService.Load(player)
	if not data then
		player:SetAttribute("GuidedIntroRedirectBlockedReason", "PlayerDataUnavailable")
		return false, "PlayerDataUnavailable"
	end

	local completed = data.GuidedIntroCompleted == true
	publishState(player, completed)

	if completed then
		player:SetAttribute("GuidedIntroRedirecting", false)
		player:SetAttribute("GuidedIntroRedirectBlockedReason", nil)
		return true, "AlreadyCompleted"
	end

	if player:GetAttribute("PlayerDataTemporary") == true then
		player:SetAttribute("GuidedIntroRedirecting", false)
		player:SetAttribute("GuidedIntroRedirectBlockedReason", "PlayerDataTemporary")
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
		"RedirectEveryLobbyEntryUntilCompletionV1"
	)
	workspace:SetAttribute("LobbyGuidedIntroPhaseId", "GuidedIntro")
	workspace:SetAttribute("LobbyGuidedIntroContentPhaseId", "Phase01")
	return true
end

return GuidedIntroRedirectService
