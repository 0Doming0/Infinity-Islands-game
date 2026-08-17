-- Experience Polish: a primeira ilha ensina combate sem atacar primeiro.
--
-- O MonsterSpawner legado marca a ilha inicial como TutorialPassive e zera o
-- dano. Para evitar uma reescrita arriscada do spawner perto do relancamento,
-- este adaptador reinicializa SOMENTE os slimes iniciais usando a propria
-- SlimeController oficial:
--   * ficam selecionaveis pelo cliente desde o inicio;
--   * nao ganham aggro por proximidade;
--   * reagem normalmente depois de LastDamagedByUserId / LastHitUserId;
--   * continuam presos a areaEnemy porque os atributos de area sao preservados.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local BlockParkour = ServerScriptService:WaitForChild("BlockParkour")
local SlimeController = require(BlockParkour:WaitForChild("SlimeController"))
local SlimeVariants = require(BlockParkour:WaitForChild("SlimeVariants"))

local VERSION = "InitialIslandNeutralUntilHitV2"
local TARGET_TAG = "CombatTarget"
local rebound = setmetatable({}, { __mode = "k" })

local function findIsland(model)
	local current = model and model.Parent
	while current and current ~= workspace do
		if current:IsA("Model") then
			local index = tonumber(current:GetAttribute("GlobalIslandIndex"))
			if current:GetAttribute("IsInitialIsland") == true
				or current:GetAttribute("NumberedIslandIndex") == 0
				or current:GetAttribute("IslandRole") == "CombatEntry"
				or (index and math.floor(index) == 1)
			then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function combatParts(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return humanoid, root
end

local function definitionFor(model)
	local variant = tostring(model:GetAttribute("SlimeVariant") or "Green")
	local source = SlimeVariants.GetDefinition(variant)
	if not source then
		return nil
	end

	local definition = table.clone(source)
	local restoredDamage = math.max(
		1,
		tonumber(model:GetAttribute("BaseAttackDamage"))
			or tonumber(definition.AttackDamage)
			or 8
	)
	definition.AttackDamage = restoredDamage
	definition.InitiallyPeaceful = true

	local groundBase = tonumber(model:GetAttribute("FireGroundBaseDamage"))
	if groundBase and definition.GroundEffectDamage ~= nil then
		definition.GroundEffectDamage = groundBase
	end

	return definition
end

local function markProvoked(model)
	if not model.Parent then
		return
	end
	model:SetAttribute("PassiveUntilAttacked", false)
	model:SetAttribute("AIBehaviorPolicy", "NeutralRetaliationAfterHit")
	model:SetAttribute("TutorialAttackGuideActive", false)
end

local function bindProvocation(model)
	local function check()
		local userId = model:GetAttribute("LastDamagedByUserId")
			or model:GetAttribute("LastHitUserId")
		if typeof(userId) == "number" and Players:GetPlayerByUserId(userId) then
			markProvoked(model)
		end
	end
	model:GetAttributeChangedSignal("LastDamagedByUserId"):Connect(check)
	model:GetAttributeChangedSignal("LastHitUserId"):Connect(check)
	check()
end

local function adapt(model)
	if rebound[model]
		or not model:IsA("Model")
		or model:GetAttribute("IsInitialIslandMob") ~= true
		or model:GetAttribute("AIController") ~= "Slime"
	then
		return
	end

	local island = findIsland(model)
	local humanoid, root = combatParts(model)
	local definition = definitionFor(model)
	if not island or not humanoid or not root or not definition then
		return
	end

	rebound[model] = true

	-- Deixa o spawner terminar SlimeController.Start antes de substituir o estado.
	task.delay(0.08, function()
		if not model.Parent or humanoid.Health <= 0 then
			return
		end

		SlimeController.Stop(model)

		model:SetAttribute("TutorialPassive", false)
		model:SetAttribute("PermanentPeaceful", nil)
		model:SetAttribute("CanDamagePlayers", true)
		model:SetAttribute("AttackDamage", definition.AttackDamage)
		model:SetAttribute("PassiveUntilAttacked", true)
		model:SetAttribute("TutorialAttackGuideActive", true)
		model:SetAttribute("AIBehaviorPolicy", "NeutralUntilPlayerHits")

		-- SlimeController captura BasePeaceful neste instante. Depois do Start o
		-- atributo visual volta a false para que soft-aim/indicadores possam mirar.
		model:SetAttribute("Peaceful", true)

		local seed = math.floor(workspace:GetServerTimeNow() * 1000) % 2147483646 + 1
		SlimeController.Start(
			{
				Model = model,
				Root = root,
				Humanoid = humanoid,
				Island = island,
			},
			definition,
			Random.new(seed),
			{
				OnTeleported = function() end,
				OnExpired = function()
					if model.Parent then
						model:Destroy()
					end
				end,
			}
		)

		-- Targetavel, mas a IA continua semanticamente pacifica por BasePeaceful.
		model:SetAttribute("Peaceful", false)
		bindProvocation(model)
	end)
end

local function schedule(instance)
	if not instance or not instance:IsA("Model") then
		return
	end
	task.defer(adapt, instance)
end

for _, instance in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
	schedule(instance)
end
CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(schedule)

workspace:SetAttribute("DungeonInitialIslandNeutralCombatReady", true)
workspace:SetAttribute("DungeonInitialIslandNeutralCombatVersion", VERSION)
