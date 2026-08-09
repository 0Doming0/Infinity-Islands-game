--[[
	Infinity Islands - Task 28
	IslandClearRecoveryService V1

	Listens to the existing CombatRouteProgression clear signal:

	DungeonIslandClearFeedbackSerial

	For each clear:
	- read which GlobalIslandIndex was cleared;
	- find living, non-downed players currently on that island;
	- restore 35% of missing health, with a small minimum;
	- never exceed MaxHealth;
	- never revive.

	No HUD is created. The authored PlayerStatus health bar simply reflects the
	real Humanoid.Health change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.IslandClearRecoveryConfig
)

local Service = {}

local started = false
local connection = nil

local lastHandledSerial = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function telemetryBaseline(player)
	return tonumber(
		player:GetAttribute(
			"DungeonInstantControlReadyAt"
		)
			or player:GetAttribute(
				"DungeonDirectEntryStartedAt"
			)
	)
end

local function insideTelemetryWindow(player)
	local baseline =
		telemetryBaseline(player)

	if not baseline then
		return false
	end

	return now() - baseline
		<= Config.TelemetryWindowSeconds
end

local function currentIsland(player)
	return math.floor(
		tonumber(
			player:GetAttribute(
				"CurrentGlobalIslandIndex"
			)
		) or 0
	)
end

local function livingHumanoid(player)
	if not player
		or player.Parent ~= Players
		or player:GetAttribute(
			"IsDowned"
		) == true
	then
		return nil
	end

	local character =
		player.Character

	local humanoid =
		character
			and character
				:FindFirstChildOfClass(
					"Humanoid"
				)

	if not humanoid
		or humanoid.Health
			< Config.MinimumHealthToRecover
	then
		return nil
	end

	return humanoid
end

local function recordRecovery(
	player,
	clearedIsland,
	before,
	after,
	maxHealth,
	serial
)
	local recovered =
		math.max(
			0,
			after - before
		)

	player:SetAttribute(
		"LastIslandClearRecovery",
		recovered
	)

	player:SetAttribute(
		"LastIslandClearRecoveryBefore",
		before
	)

	player:SetAttribute(
		"LastIslandClearRecoveryAfter",
		after
	)

	player:SetAttribute(
		"LastIslandClearRecoveryMaxHealth",
		maxHealth
	)

	player:SetAttribute(
		"LastIslandClearRecoveryIsland",
		clearedIsland
	)

	player:SetAttribute(
		"LastIslandClearRecoverySerial",
		serial
	)

	player:SetAttribute(
		"LastIslandClearRecoveryAt",
		now()
	)

	if insideTelemetryWindow(player) then
		player:SetAttribute(
			"EarlyCombatClearRecovery90s",
			(
				tonumber(
					player:GetAttribute(
						"EarlyCombatClearRecovery90s"
					)
				) or 0
			) + recovered
		)

		player:SetAttribute(
			"EarlyCombatClearRecoveryCount90s",
			(
				tonumber(
					player:GetAttribute(
						"EarlyCombatClearRecoveryCount90s"
					)
				) or 0
			) + 1
		)
	end
end

local function recoverPlayer(
	player,
	clearedIsland,
	serial
)
	if currentIsland(player)
		~= clearedIsland
	then
		return false,
			"DifferentIsland"
	end

	local humanoid =
		livingHumanoid(player)

	if not humanoid then
		return false,
			"NotLiving"
	end

	local before =
		math.max(
			0,
			tonumber(humanoid.Health)
				or 0
		)

	local maxHealth =
		math.max(
			1,
			tonumber(humanoid.MaxHealth)
				or 1
		)

	local amount =
		Config.GetRecoveryAmount(
			before,
			maxHealth
		)

	if amount <= 0 then
		player:SetAttribute(
			"LastIslandClearRecovery",
			0
		)

		player:SetAttribute(
			"LastIslandClearRecoveryIsland",
			clearedIsland
		)

		player:SetAttribute(
			"LastIslandClearRecoveryAt",
			now()
		)

		return true,
			"AlreadyFull"
	end

	local after =
		math.min(
			maxHealth,
			before + amount
		)

	humanoid.Health = after

	recordRecovery(
		player,
		clearedIsland,
		before,
		humanoid.Health,
		maxHealth,
		serial
	)

	return true,
		humanoid.Health - before
end

local function processClear()
	if not started then
		return
	end

	local serial =
		math.floor(
			tonumber(
				workspace:GetAttribute(
					"DungeonIslandClearFeedbackSerial"
				)
			) or 0
		)

	if serial <= lastHandledSerial then
		return
	end

	local clearedIsland =
		math.floor(
			tonumber(
				workspace:GetAttribute(
					"DungeonIslandClearFeedbackIsland"
				)
			) or 0
		)

	if clearedIsland <= 0 then
		return
	end

	lastHandledSerial = serial

	local recoveredPlayers = 0
	local recoveredHealth = 0

	for _, player in ipairs(
		Players:GetPlayers()
	) do
		local ok,
			result =
				recoverPlayer(
					player,
					clearedIsland,
					serial
				)

		if ok then
			recoveredPlayers += 1

			if type(result) == "number" then
				recoveredHealth +=
					math.max(
						0,
						result
					)
			end
		end
	end

	workspace:SetAttribute(
		"DungeonIslandClearRecoverySerial",
		serial
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryIsland",
		clearedIsland
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryPlayerCount",
		recoveredPlayers
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryTotalHealth",
		recoveredHealth
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryAt",
		now()
	)
end

function Service.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryReady",
		true
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryVersion",
		Config.Version
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryPolicy",
		Config.Policy
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryMissingFraction",
		Config.MissingHealthRecoveryFraction
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryMinimumMaxFraction",
		Config.MinimumRecoveryFractionOfMaxHealth
	)

	connection =
		workspace:GetAttributeChangedSignal(
			"DungeonIslandClearFeedbackSerial"
		):Connect(
			processClear
		)

	task.defer(
		processClear
	)

	return true
end

function Service.Stop()
	if not started then
		return false
	end

	started = false

	if connection then
		connection:Disconnect()
		connection = nil
	end

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryReady",
		false
	)

	return true
end

return Service
