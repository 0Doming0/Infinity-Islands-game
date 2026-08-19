--[[
	Infinity Islands - SessionRetentionCheckpoints V1

	Fast campaign-read retention checkpoints, intentionally separate from
	InfinityIslandsCoreLoopV2. Each event fires at most once per player/session.

	Events:
	- SessionReached2Minutes
	- SessionReached5Minutes
	- SessionReached8Minutes
	- SessionReached10Minutes

	GameplayAnalyticsService remains the single AnalyticsService authority.
]]

local Players = game:GetService("Players")

local GameplayAnalytics = require(
	script.Parent:WaitForChild("GameplayAnalyticsService")
)

local VERSION = "SessionRetentionCheckpointsV1"

local CHECKPOINTS = table.freeze({
	{ Seconds = 120, Minutes = 2, Event = "SessionReached2Minutes" },
	{ Seconds = 300, Minutes = 5, Event = "SessionReached5Minutes" },
	{ Seconds = 480, Minutes = 8, Event = "SessionReached8Minutes" },
	{ Seconds = 600, Minutes = 10, Event = "SessionReached10Minutes" },
})

local sessions = setmetatable({}, { __mode = "k" })
local reachedCounts = {}

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return 0
	end
	return math.max(0, math.floor(number))
end

local function cleanLevel(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function emitCheckpoint(player, session, checkpoint)
	if player.Parent ~= Players
		or sessions[player] ~= session
		or session.Fired[checkpoint.Minutes] == true
	then
		return false
	end

	session.Fired[checkpoint.Minutes] = true

	local islandIndex = cleanIndex(
		player:GetAttribute("CurrentGlobalIslandIndex")
	)
	local playerLevel = cleanLevel(
		player:GetAttribute("PlayerLevel")
	)

	local recorded = GameplayAnalytics.RecordCustom(
		player,
		checkpoint.Event,
		checkpoint.Seconds,
		"Island" .. tostring(islandIndex),
		"Level" .. tostring(playerLevel),
		VERSION,
		true
	)

	reachedCounts[checkpoint.Minutes] =
		(reachedCounts[checkpoint.Minutes] or 0) + 1

	workspace:SetAttribute(
		"DungeonSessionRetentionReached" .. tostring(checkpoint.Minutes) .. "mCount",
		reachedCounts[checkpoint.Minutes]
	)
	workspace:SetAttribute(
		"DungeonSessionRetentionLastCheckpointMinutes",
		checkpoint.Minutes
	)
	workspace:SetAttribute(
		"DungeonSessionRetentionLastCheckpointAt",
		workspace:GetServerTimeNow()
	)

	player:SetAttribute(
		"SessionRetentionLastCheckpointMinutes",
		checkpoint.Minutes
	)
	player:SetAttribute(
		"SessionRetentionLastCheckpointIsland",
		islandIndex
	)
	player:SetAttribute(
		"SessionRetentionLastCheckpointLevel",
		playerLevel
	)
	player:SetAttribute(
		"SessionRetentionLastCheckpointRecorded",
		recorded == true
	)

	return recorded == true
end

local function bindPlayer(player)
	if sessions[player] then
		return
	end

	local session = {
		StartedAt = os.clock(),
		Fired = {},
	}
	sessions[player] = session

	player:SetAttribute("SessionRetentionCheckpointVersion", VERSION)
	player:SetAttribute("SessionRetentionCheckpointPolicy", "SeparateFromCoreLoop")
	player:SetAttribute("SessionRetentionLastCheckpointMinutes", 0)

	for _, checkpoint in ipairs(CHECKPOINTS) do
		task.delay(checkpoint.Seconds, function()
			emitCheckpoint(player, session, checkpoint)
		end)
	end
end

local function unbindPlayer(player)
	sessions[player] = nil
end

workspace:SetAttribute("DungeonSessionRetentionCheckpointVersion", VERSION)
workspace:SetAttribute(
	"DungeonSessionRetentionCheckpointEvents",
	"2m,5m,8m,10m"
)
workspace:SetAttribute(
	"DungeonSessionRetentionCheckpointPolicy",
	"SeparateCustomEventsFromInfinityIslandsCoreLoopV2"
)

for _, checkpoint in ipairs(CHECKPOINTS) do
	reachedCounts[checkpoint.Minutes] = 0
	workspace:SetAttribute(
		"DungeonSessionRetentionReached" .. tostring(checkpoint.Minutes) .. "mCount",
		0
	)
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(unbindPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
