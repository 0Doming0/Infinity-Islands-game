--[[
	Infinity Islands - Legacy Disable Flags V1

	O novo MVP nao utiliza os sistemas antigos de:
	- ObjectiveSequence;
	- Reward/Round progression;
	- Boss progression.

	O validator exige estes flags como contrato de migracao.
]]

local FLAGS = {
	"DungeonLegacyObjectiveSystemDisabled",
	"DungeonLegacyRewardProgressionDisabled",
	"DungeonLegacyBossProgressionDisabled",
}

local function enforce()
	for _, name in ipairs(FLAGS) do
		if workspace:GetAttribute(name) ~= true then
			workspace:SetAttribute(name, true)
		end
	end
end

for _, name in ipairs(FLAGS) do
	workspace:GetAttributeChangedSignal(name):Connect(function()
		if workspace:GetAttribute(name) ~= true then
			workspace:SetAttribute(name, true)
		end
	end)
end

enforce()

workspace:SetAttribute("DungeonLegacyFlagsAuthority", "DungeonLegacyFlagsV1")
workspace:SetAttribute("DungeonLegacyFlagsReady", true)
