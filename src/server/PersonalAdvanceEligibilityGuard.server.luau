--[[
	Infinity Islands - Personal Advance Eligibility Guard V1

	Keeps the existing ManualIslandAdvance service as the transport authority,
	but withholds its Ready attributes until the CURRENT player has personally
	unlocked the current island.

	Why this exists:
	- island combat is shared by the server;
	- a globally Cleared island must not immediately expose AVANCAR to a late
	  player before their personal progression/recovery has caught up;
	- ManualIslandAdvance keeps its own ReadyToken, so this guard preserves and
	  restores that exact token instead of inventing a second transport flow.

	Personal unlock rules:
	1. Island 2+ -> LastPersonalIslandCompleted / saved personal progress.
	2. Initial island -> player observed it incomplete before the clear, OR the
	   existing shared-clear recovery finished and restored the missing XP.
]]

local Players = game:GetService("Players")

local VERSION = "PersonalAdvanceEligibilityGuardV1"
local CHECK_SECONDS = 0.08

local stateByPlayer = setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return math.max(1, math.floor(number))
end

local function ensureState(player)
	local state = stateByPlayer[player]
	if state then
		return state
	end
	state = {
		SawIncomplete = {},
		Withheld = nil,
	}
	stateByPlayer[player] = state
	return state
end

local function markPersonalComplete(player, index, policy)
	if player.Parent ~= Players then
		return
	end
	if cleanIndex(player:GetAttribute("LastPersonalIslandCompleted")) == index then
		return
	end

	player:SetAttribute("LastPersonalIslandCompleted", index)
	player:SetAttribute("LastPersonalIslandCompletedAt", now())
	player:SetAttribute("LastPersonalIslandCompletionPolicy", policy)
end

local function initialRecoveryComplete(player)
	return cleanIndex(player:GetAttribute("ProgressionUnblockLastIsland")) == 1
		and player:GetAttribute("ProgressionUnblockLastReason") == "InitialSharedIslandAlreadyCleared"
		and player:GetAttribute("ProgressionUnblockCatchupXPGranted") == true
end

local function personallyUnlocked(player, state, index)
	if not index then
		return false
	end

	if cleanIndex(player:GetAttribute("LastPersonalIslandCompleted")) == index then
		return true
	end

	local highest = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("SavedHighestCompletedIslandIndex")) or 0)
	)
	local resume = cleanIndex(player:GetAttribute("SavedResumeIslandIndex"))
	if highest >= index or (resume and resume > index) then
		return true
	end

	if index == 1 then
		if initialRecoveryComplete(player) then
			markPersonalComplete(player, 1, "InitialSharedClearRecovery")
			return true
		end

		-- If this player was already on the initial island while it was still
		-- incomplete, the subsequent shared clear is a legitimate completion
		-- for that active run. A late joiner into an already-cleared island never
		-- satisfies this condition and must wait for the recovery path above.
		if state.SawIncomplete[1] == true
			and player:GetAttribute("DungeonCurrentObjectiveComplete") == true
		then
			markPersonalComplete(player, 1, "InitialIslandObservedClear")
			return true
		end
	end

	return false
end

local function updateObservedIncomplete(player, state)
	local current = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	local objectiveIsland = cleanIndex(player:GetAttribute("DungeonCurrentObjectiveIsland"))
	if current
		and objectiveIsland == current
		and player:GetAttribute("DungeonCurrentObjectiveComplete") == false
	then
		state.SawIncomplete[current] = true
	end
end

local function captureReady(player, state)
	if player:GetAttribute("DungeonManualAdvanceReady") ~= true then
		return
	end

	local source = cleanIndex(
		player:GetAttribute("DungeonManualAdvanceReadySource")
			or player:GetAttribute("CurrentGlobalIslandIndex")
	)
	if not source then
		return
	end

	if personallyUnlocked(player, state, source) then
		state.Withheld = nil
		player:SetAttribute("DungeonPersonalAdvanceUnlocked", true)
		player:SetAttribute("DungeonPersonalAdvanceUnlockedIsland", source)
		return
	end

	state.Withheld = {
		Token = player:GetAttribute("DungeonManualAdvanceReadyToken"),
		Source = source,
		Destination = cleanIndex(player:GetAttribute("DungeonAssistedTransportDestination")),
	}

	-- Only presentation/readiness attributes are withheld. ManualIslandAdvance
	-- keeps its private phase/token, so restoring these later uses the exact
	-- server-authored token and destination.
	player:SetAttribute("DungeonCanAdvance", false)
	player:SetAttribute("DungeonManualAdvanceReady", false)
	player:SetAttribute("DungeonPersonalAdvanceUnlocked", false)
	player:SetAttribute("DungeonPersonalAdvanceUnlockedIsland", nil)
	player:SetAttribute("DungeonPersonalAdvanceWithheldIsland", source)
	player:SetAttribute("DungeonPersonalAdvanceWithheldAt", now())
end

local function restoreReadyIfEligible(player, state)
	local withheld = state.Withheld
	if not withheld then
		return
	end

	local current = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if current ~= withheld.Source then
		state.Withheld = nil
		player:SetAttribute("DungeonPersonalAdvanceWithheldIsland", nil)
		return
	end

	local transportState = tostring(player:GetAttribute("DungeonAssistedTransportState") or "")
	if transportState == "Warning"
		or transportState == "Flying"
		or transportState == "Landing"
	then
		state.Withheld = nil
		player:SetAttribute("DungeonPersonalAdvanceWithheldIsland", nil)
		return
	end

	if not personallyUnlocked(player, state, withheld.Source) then
		player:SetAttribute("DungeonPersonalAdvanceUnlocked", false)
		return
	end

	player:SetAttribute("DungeonManualAdvanceReadyToken", withheld.Token)
	player:SetAttribute("DungeonManualAdvanceReadySource", withheld.Source)
	if withheld.Destination then
		player:SetAttribute("DungeonAssistedTransportDestination", withheld.Destination)
	end
	player:SetAttribute("DungeonCanAdvance", true)
	player:SetAttribute("DungeonManualAdvanceReady", true)
	player:SetAttribute("DungeonPersonalAdvanceUnlocked", true)
	player:SetAttribute("DungeonPersonalAdvanceUnlockedIsland", withheld.Source)
	player:SetAttribute("DungeonPersonalAdvanceWithheldIsland", nil)
	player:SetAttribute("DungeonPersonalAdvanceReleasedAt", now())
	state.Withheld = nil
end

local function inspectPlayer(player)
	if player.Parent ~= Players then
		return
	end

	local state = ensureState(player)
	updateObservedIncomplete(player, state)
	captureReady(player, state)
	restoreReadyIfEligible(player, state)

	local current = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if player:GetAttribute("DungeonManualAdvanceReady") ~= true
		and not state.Withheld
	then
		local unlocked = current and personallyUnlocked(player, state, current) or false
		player:SetAttribute("DungeonPersonalAdvanceUnlocked", unlocked)
		player:SetAttribute(
			"DungeonPersonalAdvanceUnlockedIsland",
			unlocked and current or nil
		)
	end
end

local function bindPlayer(player)
	local state = ensureState(player)
	player:SetAttribute("DungeonPersonalAdvanceEligibilityVersion", VERSION)
	player:SetAttribute("DungeonPersonalAdvancePolicy", "PersonalUnlockBeforeAdvanceButton")
	player:SetAttribute("DungeonPersonalAdvanceUnlocked", false)
	player:SetAttribute("DungeonPersonalAdvanceUnlockedIsland", nil)

	player.CharacterAdded:Connect(function()
		state.Withheld = nil
		player:SetAttribute("DungeonPersonalAdvanceWithheldIsland", nil)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	stateByPlayer[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

workspace:SetAttribute("DungeonPersonalAdvanceEligibilityVersion", VERSION)
workspace:SetAttribute(
	"DungeonPersonalAdvanceEligibilityPolicy",
	"WithholdGlobalReadyUntilPersonalIslandUnlock"
)

while true do
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, errorMessage = pcall(inspectPlayer, player)
		if not ok then
			player:SetAttribute("DungeonPersonalAdvanceEligibilityError", tostring(errorMessage))
			workspace:SetAttribute("DungeonPersonalAdvanceEligibilityLastError", tostring(errorMessage))
		end
	end
	task.wait(CHECK_SECONDS)
end
