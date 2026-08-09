-- Canonical read-only bridge for the first-session GuidedIntro.
--
-- The Dungeon already persists TutorialCompleted in SkyDungeonPlayerData_V10.
-- The Lobby reads that same field so onboarding does not create a second
-- competing persistence flag.

local DataStoreService = game:GetService("DataStoreService")

local DATASTORE_NAME = "SkyDungeonPlayerData_V10"
local LOAD_RETRIES = 3
local RETRY_DELAY_SECONDS = 0.75

local store = DataStoreService:GetDataStore(DATASTORE_NAME)

local LobbyGuidedIntroProgressService = {}

local function keyFor(player)
	return string.format("Player_%d", player.UserId)
end

local function hasLegacyProgress(raw)
	if type(raw) ~= "table" then
		return false
	end

	if math.max(0, math.floor(tonumber(raw.BestScore) or 0)) > 0 then
		return true
	end
	if math.max(0, math.floor(tonumber(raw.Coins) or 0)) > 0 then
		return true
	end

	local inventory = raw.Inventory or raw.OwnedItems
	if type(inventory) == "table" and next(inventory) ~= nil then
		return true
	end

	local phases = raw.Progression and raw.Progression.Phases
	if type(phases) == "table" then
		for _, progress in pairs(phases) do
			if type(progress) == "table"
				and math.max(0, math.floor(tonumber(progress.Completions) or 0)) > 0
			then
				return true
			end
		end
	end

	return false
end

function LobbyGuidedIntroProgressService.IsCompleted(player)
	local lastError

	for attempt = 1, LOAD_RETRIES do
		local success, raw = pcall(function()
			return store:GetAsync(keyFor(player))
		end)

		if success then
			if type(raw) ~= "table" then
				return false, "NewProfile"
			end

			local hasTutorialRecord =
				raw.TutorialCompleted ~= nil or raw.TutorialStage ~= nil

			local completed = raw.TutorialCompleted == true
				or (not hasTutorialRecord and hasLegacyProgress(raw))

			return completed, completed and "Completed" or "Required"
		end

		lastError = raw
		if attempt < LOAD_RETRIES then
			task.wait(RETRY_DELAY_SECONDS * attempt)
		end
	end

	return nil, tostring(lastError or "GuidedIntroProgressUnavailable")
end

return LobbyGuidedIntroProgressService
