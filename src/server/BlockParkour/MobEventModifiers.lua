-- Contrato unico entre eventos globais e qualquer mob marcado como CombatTarget.
-- IAs personalizadas podem consultar este modulo ou os atributos replicados
-- WorldEventAggroMultiplier e WorldEventForceAggressive no proprio modelo.

local CollectionService = game:GetService("CollectionService")

local MobEventModifiers = {}

local COMBAT_TAG = "CombatTarget"
local HUNT_AGGRO_MULTIPLIER = 1.45
local started = false

local function currentAggroMultiplier()
	return workspace:GetAttribute("MonsterHuntActive") == true and HUNT_AGGRO_MULTIPLIER or 1
end

local function currentForceAggressive()
	return workspace:GetAttribute("AllMobsAggressive") == true
end

local function apply(model)
	if not model or not model:IsA("Model") then
		return
	end
	model:SetAttribute("WorldEventAggroMultiplier", currentAggroMultiplier())
	model:SetAttribute("WorldEventForceAggressive", currentForceAggressive())
end

local function applyToAllMobs()
	for _, model in ipairs(CollectionService:GetTagged(COMBAT_TAG)) do
		apply(model)
	end
end

function MobEventModifiers.Start()
	if started then
		return
	end
	started = true

	CollectionService:GetInstanceAddedSignal(COMBAT_TAG):Connect(function(model)
		apply(model)
	end)
	workspace:GetAttributeChangedSignal("MonsterHuntActive"):Connect(applyToAllMobs)
	workspace:GetAttributeChangedSignal("AllMobsAggressive"):Connect(applyToAllMobs)
	applyToAllMobs()
end

function MobEventModifiers.Apply(model)
	apply(model)
end

function MobEventModifiers.GetAggroMultiplier(model)
	return currentAggroMultiplier()
end

function MobEventModifiers.GetAggroRange(model, baseRange)
	return math.max(0, tonumber(baseRange) or 0) * MobEventModifiers.GetAggroMultiplier(model)
end

function MobEventModifiers.IsForcedAggressive(model)
	return currentForceAggressive()
end

return table.freeze(MobEventModifiers)
